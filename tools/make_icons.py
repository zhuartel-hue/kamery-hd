"""Generuje ikony aplikacji dla Androida i iOS: python3 tools/make_icons.py"""
import glob
import os
import re

from PIL import Image, ImageDraw, ImageFilter

LAGOON, AZURE, ABYSS, AQUA, WHITE = (6, 182, 212), (59, 130, 246), (6, 20, 35), (34, 211, 238), (255, 255, 255)


def gradient(size):
    """Ukośny gradient turkus -> błękit."""
    g = Image.new("RGB", (size, size))
    px = g.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size - 2)
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(LAGOON, AZURE))
    return g


def draw(size, rounded):
    s = size / 192
    bg = gradient(size)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    if rounded:
        md.rounded_rectangle([8*s, 8*s, 184*s, 184*s], radius=44*s, fill=255)
    else:
        md.rectangle([0, 0, size, size], fill=255)
    img.paste(bg, (0, 0), mask)

    # miękka poświata pod kamerą
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([40*s, 60*s, 160*s, 150*s], fill=(255, 255, 255, 50))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(14*s)))

    d = ImageDraw.Draw(img)
    # korpus kamery
    d.rounded_rectangle([34*s, 64*s, 132*s, 122*s], radius=18*s, fill=WHITE)
    d.polygon([(132*s, 82*s), (160*s, 68*s), (160*s, 118*s), (132*s, 104*s)], fill=WHITE)
    # obiektyw
    d.ellipse([50*s, 72*s, 92*s, 114*s], fill=ABYSS)
    d.ellipse([60*s, 82*s, 82*s, 104*s], fill=AQUA)
    d.ellipse([64*s, 85*s, 71*s, 92*s], fill=WHITE)
    # dioda nagrywania
    d.ellipse([110*s, 74*s, 120*s, 84*s], fill=(255, 122, 89))
    # uchwyt
    d.rounded_rectangle([78*s, 122*s, 92*s, 146*s], radius=4*s, fill=WHITE)
    d.rounded_rectangle([56*s, 142*s, 114*s, 154*s], radius=6*s, fill=WHITE)
    return img if rounded else img.convert("RGB")


def icon(px, rounded):
    return draw(1024, rounded).resize((px, px), Image.LANCZOS)


root = os.path.join(os.path.dirname(__file__), "..")
for path in glob.glob(f"{root}/android/app/src/main/res/mipmap-*/ic_launcher.png"):
    px = Image.open(path).size[0]
    icon(px, rounded=True).save(path)
for path in glob.glob(f"{root}/ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png"):
    m = re.search(r"(\d+(?:\.\d+)?)x\d+(?:\.\d+)?@(\d)x", path)
    px = round(float(m.group(1)) * int(m.group(2)))
    icon(px, rounded=False).save(path)  # iOS sam zaokrągla rogi, ikona bez przezroczystości
print("ok")
