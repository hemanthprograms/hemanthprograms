#!/usr/bin/env python3
"""Draws the 1024x1024 app icon (a crescent moon over a soft sound wave).

Requires Pillow. Usage: python3 Tools/make_app_icon.py
"""

import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUTPUT = pathlib.Path(__file__).resolve().parent.parent / "SnoreGuard" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
TOP = (22, 28, 64)
BOTTOM = (7, 9, 24)
ACCENT = (168, 153, 255)


def main() -> None:
    icon = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(icon)
    for y in range(SIZE):
        f = y / (SIZE - 1)
        draw.line([(0, y), (SIZE, y)], fill=tuple(round(TOP[i] * (1 - f) + BOTTOM[i] * f) for i in range(3)))

    # Glow behind the moon.
    glow = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(glow).ellipse([262, 150, 762, 650], fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(90))
    icon.paste(Image.new("RGB", (SIZE, SIZE), ACCENT), mask=glow)

    # Crescent: a full disc with an offset disc cut out.
    moon = Image.new("L", (SIZE, SIZE), 0)
    moon_draw = ImageDraw.Draw(moon)
    moon_draw.ellipse([322, 200, 702, 580], fill=255)
    moon_draw.ellipse([432, 150, 792, 510], fill=0)
    icon.paste(Image.new("RGB", (SIZE, SIZE), ACCENT), mask=moon.filter(ImageFilter.GaussianBlur(1.2)))

    # A row of rounded wave bars, tallest in the middle.
    bars = Image.new("L", (SIZE, SIZE), 0)
    bars_draw = ImageDraw.Draw(bars)
    count, width, gap, base = 9, 44, 30, 790
    left = (SIZE - (count * width + (count - 1) * gap)) // 2
    for i in range(count):
        height = 40 + 150 * math.sin(math.pi * (i + 0.5) / count) ** 2
        x = left + i * (width + gap)
        bars_draw.rounded_rectangle([x, base - height / 2, x + width, base + height / 2], radius=width // 2, fill=220)
    icon.paste(Image.new("RGB", (SIZE, SIZE), (226, 222, 255)), mask=bars.filter(ImageFilter.GaussianBlur(0.8)))

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUTPUT, optimize=True)
    print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
