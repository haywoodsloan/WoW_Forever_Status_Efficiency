#!/usr/bin/env python3
"""Draws the three status icons and writes them as TGA files the game can load.

    python3 tools/make_icons.py

Needs Pillow. The client wants uncompressed 32-bit TGA with power-of-two sides,
so the files are written by hand rather than trusting an encoder's defaults.
"""

import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 64  # pixels, final
SCALE = 8  # supersampling factor

GREEN = (70, 222, 88, 255)
RED = (240, 62, 52, 255)
YELLOW = (255, 208, 40, 255)
WHITE = (255, 255, 255, 255)
OUTLINE = (0, 0, 0, 255)
HOLLOW = (28, 28, 28, 235)

STROKE = 11  # width of a coloured stroke, in final pixels
EDGE = 4  # black border on each side of a stroke


def canvas():
    image = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def px(value):
    return int(round(value * SCALE))


def stroke(draw, points, colour, width):
    """A polyline with round joints and round ends."""
    scaled = [(px(x), px(y)) for x, y in points]
    draw.line(scaled, fill=colour, width=px(width), joint="curve")
    radius = px(width) / 2
    for x, y in scaled:
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=colour)


def disc(draw, centre, radius, colour):
    x, y = px(centre[0]), px(centre[1])
    r = px(radius)
    draw.ellipse((x - r, y - r, x + r, y + r), fill=colour)


def finish(image):
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def check():
    image, draw = canvas()
    points = [(12, 34), (26, 48), (52, 16)]
    stroke(draw, points, OUTLINE, STROKE + 2 * EDGE)
    stroke(draw, points, GREEN, STROKE)
    return finish(image)


def cross():
    image, draw = canvas()
    arms = [[(15, 15), (49, 49)], [(49, 15), (15, 49)]]
    for arm in arms:
        stroke(draw, arm, OUTLINE, STROKE + 2 * EDGE)
    for arm in arms:
        stroke(draw, arm, RED, STROKE)
    return finish(image)


def partial():
    image, draw = canvas()
    centre = (32, 32)
    disc(draw, centre, 27, OUTLINE)
    disc(draw, centre, 23, YELLOW)
    # Hollow out the right half, leaving a yellow rim.
    x, y, r = px(centre[0]), px(centre[1]), px(17)
    draw.pieslice((x - r, y - r, x + r, y + r), start=-90, end=90, fill=HOLLOW)
    return finish(image)


def plus():
    image, draw = canvas()
    arms = [[(32, 13), (32, 51)], [(13, 32), (51, 32)]]
    for arm in arms:
        stroke(draw, arm, OUTLINE, STROKE + 2 * EDGE)
    for arm in arms:
        stroke(draw, arm, GREEN, STROKE)
    return finish(image)


def exclaim():
    image, draw = canvas()
    bar = [(32, 12), (32, 34)]
    stroke(draw, bar, OUTLINE, STROKE + 2 * EDGE)
    disc(draw, (32, 52), 6.5 + EDGE, OUTLINE)
    stroke(draw, bar, YELLOW, STROKE)
    disc(draw, (32, 52), 6.5, YELLOW)
    return finish(image)


def stop():
    image, draw = canvas()
    centre = (32, 32)
    disc(draw, centre, 27, OUTLINE)
    disc(draw, centre, 23, RED)
    stroke(draw, [(20, 32), (44, 32)], WHITE, 8)
    return finish(image)


def dot(colour):
    image, draw = canvas()
    centre = (32, 32)
    disc(draw, centre, 24, OUTLINE)
    disc(draw, centre, 20, colour)
    return finish(image)


def ring():
    image, draw = canvas()
    centre = (32, 32)
    disc(draw, centre, 27, OUTLINE)
    disc(draw, centre, 23, YELLOW)
    disc(draw, centre, 17, OUTLINE)
    disc(draw, centre, 13, (0, 0, 0, 0))  # see-through middle
    return finish(image)


def write_tga(image, path):
    """Uncompressed true-colour TGA, 32 bits, rows stored bottom to top."""
    image = image.convert("RGBA")
    width, height = image.size
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0,  # no image id
        0,  # no colour map
        2,  # uncompressed true colour
        0, 0, 0,  # colour map: unused
        0, 0,  # origin
        width, height,
        32,  # bits per pixel
        8,  # 8 alpha bits, origin at the bottom left
    )
    pixels = image.load()
    rows = bytearray()
    for y in range(height - 1, -1, -1):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            rows += bytes((b, g, r, a))
    path.write_bytes(header + bytes(rows))


def main():
    root = Path(__file__).resolve().parent.parent
    media = root / "StatusEfficiency" / "Media"
    media.mkdir(parents=True, exist_ok=True)
    icons = {
        "Check": check(),
        "Partial": partial(),
        "Cross": cross(),
        "DotGreen": dot(GREEN),
        "DotYellow": dot(YELLOW),
        "DotRed": dot(RED),
        "Plus": plus(),
        "Exclaim": exclaim(),
        "Stop": stop(),
        "Ring": ring(),
    }
    for name, image in icons.items():
        write_tga(image, media / (name + ".tga"))
        print("wrote", media / (name + ".tga"))

    if len(sys.argv) > 1:
        # Optional preview sheet: python3 tools/make_icons.py preview.png
        sheet = Image.new("RGBA", (74 * len(icons) + 10, 64 + 20 + 40), (58, 44, 36, 255))
        for i, image in enumerate(icons.values()):
            sheet.alpha_composite(image, (10 + i * 74, 10))
            small = image.resize((18, 18), Image.LANCZOS)
            sheet.alpha_composite(small, (10 + i * 74, 88))
        sheet.save(sys.argv[1])
        print("wrote", sys.argv[1])


if __name__ == "__main__":
    main()
