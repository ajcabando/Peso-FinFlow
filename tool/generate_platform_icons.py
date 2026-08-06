#!/usr/bin/env python3
"""Generate Android launcher + macOS app icons from dist/finflow_icon_1024.png.

- Android: legacy launcher PNGs in each mipmap density (launchers apply the
  mask, so the art stays a full-bleed opaque square).
- macOS: app icons with Apple-style rounded corners baked in (macOS does not
  mask icons). Corner radius follows Apple's icon template (~18.1%).

Usage: python3 tool/generate_platform_icons.py
"""

import os

from PIL import Image, ImageDraw, ImageOps

MASTER = "dist/finflow_icon_1024.png"

# Android legacy launcher icons: density -> pixels.
ANDROID = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# macOS app icons (from Contents.json): filename -> pixels.
MACOS = {
    "app_icon_16.png": 16,
    "app_icon_32.png": 32,
    "app_icon_64.png": 64,
    "app_icon_128.png": 128,
    "app_icon_256.png": 256,
    "app_icon_512.png": 512,
    "app_icon_1024.png": 1024,
}

# Apple's macOS icon corner radius: 185.4px on a 1024px canvas.
MACOS_CORNER_FRACTION = 185.4 / 1024.0


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def main():
    if not os.path.isfile(MASTER):
        raise SystemExit(f"missing {MASTER} (run tool/generate_ios_icons.py first)")

    master = Image.open(MASTER).convert("RGB")
    print(f"master: {master.size}")

    # ---- Android legacy launchers ----
    for density, size in ANDROID.items():
        path = f"android/app/src/main/res/{density}/ic_launcher.png"
        if not os.path.isdir(os.path.dirname(path)):
            print(f"skip (missing dir): {os.path.dirname(path)}")
            continue
        master.resize((size, size), Image.LANCZOS).convert("RGB").save(path)
        print(f"android: {path} ({size}x{size})")

    # ---- macOS app icons (rounded corners) ----
    macos_dir = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    if not os.path.isdir(macos_dir):
        raise SystemExit(f"missing {macos_dir}")

    mask = rounded_mask(1024, int(1024 * MACOS_CORNER_FRACTION))
    rounded = Image.new("RGBA", (1024, 1024))
    rounded.paste(master, (0, 0), mask)
    for name, size in MACOS.items():
        path = os.path.join(macos_dir, name)
        rounded.resize((size, size), Image.LANCZOS).save(path)
        print(f"macos: {path} ({size}x{size})")


if __name__ == "__main__":
    main()
