#!/usr/bin/env python3
"""Generate web/PWA icons from dist/finflow_icon_1024.png.

Outputs into web/icons/:
- Icon-192.png / Icon-512.png          (Android Chrome / PWA manifest)
- Icon-maskable-192.png / Icon-maskable-512.png  (same art, full-bleed square)
- apple-touch-icon.png                 (iOS "Add to Home Screen", 180px, RGB)

Usage: python3 tool/generate_web_icons.py
"""

import os

from PIL import Image

MASTER = "dist/finflow_icon_1024.png"
OUT = "web/icons"

SIZES = {
    "Icon-192.png": 192,
    "Icon-512.png": 512,
    "Icon-maskable-192.png": 192,
    "Icon-maskable-512.png": 512,
    "apple-touch-icon.png": 180,  # iOS; RGB, no alpha (iOS applies its own mask)
}


def main():
    if not os.path.isfile(MASTER):
        raise SystemExit(f"missing {MASTER}")
    os.makedirs(OUT, exist_ok=True)
    master = Image.open(MASTER).convert("RGBA")
    print(f"master: {master.size}")
    for name, size in SIZES.items():
        img = master.resize((size, size), Image.LANCZOS)
        if name == "apple-touch-icon.png":
            img = img.convert("RGB")
        path = os.path.join(OUT, name)
        img.save(path)
        print(f"{path} ({size}x{size})")


if __name__ == "__main__":
    main()
