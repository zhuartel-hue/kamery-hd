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
    # Logo AriView: litera „A”, w której poprzeczkę zastępuje obiektyw.
    apex, left, right = (96*s, 30*s), (38*s, 160*s), (154*s, 160*s)
    w = int(24*s)
    d.line([apex, left], fill=WHITE, width=w)
    d.line([apex, right], fill=WHITE, width=w)
    r = w / 2
    for x, y in (apex, left, right):
        d.ellipse([x-r, y-r, x+r, y+r], fill=WHITE)
    cx, cy = 96*s, 116*s
    d.ellipse([cx-31*s, cy-31*s, cx+31*s, cy+31*s], fill=WHITE)
    d.ellipse([cx-22*s, cy-22*s, cx+22*s, cy+22*s], fill=ABYSS)
    d.ellipse([cx-13*s, cy-13*s, cx+13*s, cy+13*s], fill=AQUA)
    d.ellipse([cx-9*s, cy-10*s, cx-2*s, cy-3*s], fill=WHITE)
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
