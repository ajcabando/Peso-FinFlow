#!/usr/bin/env python3
"""Generate the FinFlow branded iOS app icons.

Draws the app icon (brand gradient + white wallet glyph, matching the app's
own branding) at 1024px and writes every size expected by
ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json.

The wallet glyph is the real Material icon used in the app
(Icons.account_balance_wallet_rounded, U+F520) rasterized from Flutter's
bundled MaterialIcons-Regular.otf, so the icon matches the in-app UI.

Usage:  python3 tool/generate_ios_icons.py
"""

import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 1024

# FinFlow brand gradient (AppColors.brandBright -> brand).
C_TOP_LEFT = (0x9C, 0x6B, 0xFF)
C_BOTTOM_RIGHT = (0x6D, 0x5D, 0xF6)

# Asset catalog icons: filename -> pixel size (from Contents.json).
ICONS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

FLUTTER_ICON_FONT = os.path.expanduser(
    "~/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf"
)

GLYPH = chr(0xF520)  # Icons.account_balance_wallet_rounded
GLYPH_SIZE = int(SIZE * 0.45)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def build_master() -> Image.Image:
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            # Diagonal gradient, t = 0 at top-left, 1 at bottom-right.
            t = (x + y) / (2.0 * SIZE)
            base = lerp(C_TOP_LEFT, C_BOTTOM_RIGHT, t)
            # Soft top-left light (white 14% fading out by t = 0.42).
            light = max(0.0, 1.0 - t / 0.42) * 0.14
            px[x, y] = lerp(base, (255, 255, 255), light)
    return img


def add_vignette(img: Image.Image) -> Image.Image:
    """Deepen the bottom-right corner so the white glyph pops."""
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    lpx = layer.load()
    cx, cy = 0.85 * SIZE, 0.90 * SIZE
    for y in range(SIZE):
        for x in range(SIZE):
            dx, dy = (x - cx) / SIZE, (y - cy) / SIZE
            r = (dx * dx + dy * dy) ** 0.5 / 0.9
            alpha = int(0.20 * max(0.0, 1.0 - r) * 255)
            if alpha:
                lpx[x, y] = (0, 0, 0, alpha)
    return Image.alpha_composite(img.convert("RGBA"), layer)


def add_glyph(img: Image.Image) -> Image.Image:
    """White wallet glyph with a soft drop shadow."""
    font = ImageFont.truetype(FLUTTER_ICON_FONT, GLYPH_SIZE)
    probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    bbox = probe.textbbox((0, 0), GLYPH, font=font)
    gw, gh = bbox[2] - bbox[0], bbox[3] - bbox[1]

    def center(offset_x=0, offset_y=0):
        return (
            (SIZE - gw) / 2 - bbox[0] + offset_x,
            (SIZE - gh) / 2 - bbox[1] + offset_y,
        )

    # Soft shadow (slightly below-right of the glyph).
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text(
        center(14, 26), GLYPH, font=font, fill=(0, 0, 0, 85)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(16))
    img = Image.alpha_composite(img, shadow)

    # White glyph.
    white = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(white).text(center(), GLYPH, font=font, fill=(255, 255, 255, 255))
    img = Image.alpha_composite(img, white)

    # Flatten to opaque RGB: the App Store marketing icon must have no alpha.
    return img.convert("RGB")


def main():
    out_dir = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    if not os.path.isdir(out_dir):
        raise SystemExit(f"missing {out_dir}")

    print("drawing 1024px master...")
    master = add_glyph(add_vignette(build_master()))
    master.save("dist/finflow_icon_1024.png")
    print("master: dist/finflow_icon_1024.png")

    for name, size in ICONS.items():
        target = os.path.join(out_dir, name)
        master.resize((size, size), Image.LANCZOS).save(target)
        print(f"wrote {name} ({size}px)")


if __name__ == "__main__":
    main()
