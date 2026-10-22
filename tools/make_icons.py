"""Generuje ikony aplikacji dla Androida i iOS: python3 tools/make_icons.py"""
import glob
import os
import re

from PIL import Image, ImageDraw

NAVY, WHITE, ORANGE = (31, 58, 95), (240, 240, 240), (224, 102, 43)


def draw(size, rounded):
    s = size / 192
    img = Image.new("RGBA" if rounded else "RGB", (size, size), (0, 0, 0, 0) if rounded else NAVY)
    d = ImageDraw.Draw(img)
    if rounded:
        d.rounded_rectangle([8*s, 8*s, 184*s, 184*s], radius=40*s, fill=NAVY)
    d.rounded_rectangle([34*s, 66*s, 134*s, 122*s], radius=14*s, fill=WHITE)
    d.polygon([(134*s, 80*s), (162*s, 66*s), (162*s, 122*s), (134*s, 108*s)], fill=WHITE)
    d.ellipse([52*s, 78*s, 84*s, 110*s], fill=NAVY)
    d.ellipse([60*s, 86*s, 76*s, 102*s], fill=ORANGE)
    d.rectangle([76*s, 122*s, 92*s, 146*s], fill=WHITE)
    d.rounded_rectangle([56*s, 142*s, 112*s, 156*s], radius=5*s, fill=WHITE)
    return img


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
