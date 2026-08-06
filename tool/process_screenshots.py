#!/usr/bin/env python3
"""Verify the simulator screenshots rendered real content and produce the
exact App Store Connect sizes (RGB, no alpha).

- iPhone native 1320x2868 (6.9") -> 1290x2796 (6.7-inch slot) + keep 6.9"
- iPad native 2064x2752 (13")   -> 2048x2732 (12.9-inch slot) + keep 13"

Usage: python3 tool/process_screenshots.py
"""

import os

from PIL import Image

OUT = "dist/screenshots"


def analyze(name, path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    total = white = purple = dark = colorful = 0
    for y in range(0, h, 12):
        for x in range(0, w, 12):
            r, g, b = px[x, y]
            total += 1
            if r > 235 and g > 235 and b > 235:
                white += 1
            if b > 150 and r < 160 and g < 160:  # brand purples / blues
                purple += 1
            if r < 60 and g < 60 and b < 60:
                dark += 1
            if max(r, g, b) - min(r, g, b) > 60:
                colorful += 1
    print(
        f"{name}: {w}x{h} white={white/total:.1%} purple={purple/total:.1%} "
        f"dark={dark/total:.1%} colorful={colorful/total:.1%}"
    )
    return im


def save_rgb(im, name):
    target = os.path.join(OUT, name)
    im.convert("RGB").save(target)
    print(f"saved {name} ({im.size[0]}x{im.size[1]})")
    return target


def main():
    os.makedirs(OUT, exist_ok=True)

    iphone = analyze("iphone", f"{OUT}/iphone-6.7-dashboard.png")
    ipad = analyze("ipad", f"{OUT}/ipad-13-dashboard.png")

    # 6.7-inch slot: 1290x2796 (from 1320x2868). 6.9-inch variant kept.
    save_rgb(iphone.resize((1290, 2796), Image.LANCZOS), "iphone-6.7-dashboard.png")
    save_rgb(iphone, "iphone-6.9-dashboard.png")

    # 12.9-inch slot: 2048x2732 (from 2064x2752). 13-inch variant kept.
    save_rgb(ipad.resize((2048, 2732), Image.LANCZOS), "ipad-12.9-dashboard.png")
    save_rgb(ipad, "ipad-13-dashboard.png")


if __name__ == "__main__":
    main()
