#!/usr/bin/env python3
"""Loreseer app icon generator — source of truth for the app icon.

Concept: 'eye-in-open-book' — a gold eye (upper lid + radiant iris) above an
open book whose fanned pages form the lower lid, on a deep indigo/violet field.
Brand palette: deep indigo/violet field + warm gold (the mystical/oracle lane).

This script is the source of truth (like build_oracle.py et al): it writes the
re-editable vector master `assets/icon/app_icon.svg`, the 1024 raster master
`assets/icon/app_icon.png`, and every derived platform asset at the exact sizes
the project already ships (web icons + maskable + favicon, Android mipmaps, iOS
+ macOS appiconsets, Windows .ico). Edit this script, then:

    pip install cairosvg Pillow      # one-time (not part of the app's Dart stack)
    python3 build_app_icon.py

`dart run flutter_launcher_icons` (configured in pubspec.yaml from
assets/icon/app_icon.png) reproduces the same platform assets from the PNG
master, so either path works; this script additionally keeps the SVG in sync.
"""
import io
import os
import cairosvg
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))

# ---- palette ----
BG_CTR, BG_EDGE = "#3a2f80", "#14122e"
PARCH = "#f4e9cf"
GOLD_HI, GOLD, AMBER = "#ffe07a", "#f2c14e", "#c87b22"
PUPIL = "#1b1740"
PAGE_HI, PAGE_LO = "#fff6df", "#e7c878"

DEFS = f'''
    <radialGradient id="bg" cx="50%" cy="42%" r="78%">
      <stop offset="0%" stop-color="{BG_CTR}"/><stop offset="100%" stop-color="{BG_EDGE}"/>
    </radialGradient>
    <radialGradient id="iris" cx="50%" cy="45%" r="60%">
      <stop offset="0%" stop-color="{GOLD_HI}"/><stop offset="55%" stop-color="{GOLD}"/>
      <stop offset="100%" stop-color="{AMBER}"/>
    </radialGradient>
    <linearGradient id="pageL" x1="0" y1="0" x2="1" y2="0.3">
      <stop offset="0%" stop-color="{PAGE_LO}"/><stop offset="100%" stop-color="{PAGE_HI}"/>
    </linearGradient>
    <linearGradient id="pageR" x1="1" y1="0" x2="0" y2="0.3">
      <stop offset="0%" stop-color="{PAGE_LO}"/><stop offset="100%" stop-color="{PAGE_HI}"/>
    </linearGradient>
    <radialGradient id="glow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="{GOLD_HI}" stop-opacity="0.55"/>
      <stop offset="100%" stop-color="{GOLD_HI}" stop-opacity="0"/>
    </radialGradient>'''

BG = f'''
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <g fill="{PARCH}" opacity="0.5">
    <circle cx="210" cy="190" r="4"/><circle cx="820" cy="230" r="5"/>
    <circle cx="160" cy="760" r="4"/><circle cx="860" cy="800" r="4"/>
    <circle cx="300" cy="120" r="3"/><circle cx="700" cy="140" r="3"/>
  </g>'''

FG = f'''
  <circle cx="512" cy="438" r="210" fill="url(#glow)"/>
  <!-- upper lid -->
  <path d="M168,452 C 330,292 694,292 856,452 C 700,372 324,372 168,452 Z"
        fill="url(#pageL)" stroke="{AMBER}" stroke-width="6" stroke-linejoin="round"/>
  <path d="M210,420 C 350,318 674,318 814,420"
        fill="none" stroke="{GOLD}" stroke-width="7" stroke-linecap="round" opacity="0.65"/>
  <!-- iris -->
  <circle cx="512" cy="446" r="126" fill="url(#iris)"/>
  <circle cx="512" cy="446" r="55" fill="{PUPIL}"/>
  <circle cx="490" cy="424" r="18" fill="{PAGE_HI}" opacity="0.92"/>
  <g stroke="{AMBER}" stroke-width="6" opacity="0.5" stroke-linecap="round">
    <line x1="512" y1="338" x2="512" y2="372"/><line x1="386" y1="446" x2="420" y2="446"/>
    <line x1="604" y1="446" x2="638" y2="446"/><line x1="426" y1="368" x2="448" y2="390"/>
    <line x1="598" y1="368" x2="576" y2="390"/>
  </g>
  <!-- open book -->
  <path d="M512,556 C 430,536 280,532 162,516 L 150,552 C 270,616 420,668 512,694 Z"
        fill="url(#pageL)" stroke="{AMBER}" stroke-width="5.5" stroke-linejoin="round"/>
  <path d="M512,556 C 594,536 744,532 862,516 L 874,552 C 754,616 604,668 512,694 Z"
        fill="url(#pageR)" stroke="{AMBER}" stroke-width="5.5" stroke-linejoin="round"/>
  <path d="M512,556 L512,694" stroke="{AMBER}" stroke-width="8" stroke-linecap="round"/>
  <g stroke="{AMBER}" stroke-width="4.5" opacity="0.55" stroke-linecap="round" fill="none">
    <path d="M232,558 C 330,602 430,628 498,640"/><path d="M210,592 C 318,640 426,664 498,674"/>
    <path d="M792,558 C 694,602 594,628 526,640"/><path d="M814,592 C 706,640 598,664 526,674"/>
  </g>'''


def svg(fg_scale=1.0):
    fg = FG
    if fg_scale != 1.0:
        fg = (f'<g transform="translate(512,512) scale({fg_scale}) '
              f'translate(-512,-512)">{FG}</g>')
    return ('<?xml version="1.0" encoding="UTF-8"?>'
            '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            f'viewBox="0 0 1024 1024"><defs>{DEFS}</defs>{BG}{fg}</svg>')


def render(fg_scale=1.0, size=1024):
    png = cairosvg.svg2png(bytestring=svg(fg_scale).encode(),
                           output_width=size, output_height=size)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def save(img, rel):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


def main():
    master = render(1.0, 1024)
    save(master, "assets/icon/app_icon.png")
    with open(os.path.join(ROOT, "assets/icon/app_icon.svg"), "w") as f:
        f.write(svg(1.0))

    def down(size):
        return master.resize((size, size), Image.LANCZOS)

    # maskable master: content scaled into the safe zone, full-bleed background
    maskable = render(0.80, 1024)

    # web
    save(down(192), "web/icons/Icon-192.png")
    save(down(512), "web/icons/Icon-512.png")
    save(maskable.resize((192, 192), Image.LANCZOS), "web/icons/Icon-maskable-192.png")
    save(maskable.resize((512, 512), Image.LANCZOS), "web/icons/Icon-maskable-512.png")
    save(down(16), "web/favicon.png")

    # android (legacy full-bleed launcher)
    for d, s in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                 ("xxhdpi", 144), ("xxxhdpi", 192)]:
        save(down(s), f"android/app/src/main/res/mipmap-{d}/ic_launcher.png")

    # ios (flatten alpha — iOS icons must be opaque)
    ios_dir = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for fn in os.listdir(os.path.join(ROOT, ios_dir)):
        if fn.endswith(".png"):
            s = Image.open(os.path.join(ROOT, ios_dir, fn)).size[0]
            save(down(s).convert("RGB"), f"{ios_dir}/{fn}")

    # macos
    mac_dir = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for fn in os.listdir(os.path.join(ROOT, mac_dir)):
        if fn.endswith(".png"):
            s = Image.open(os.path.join(ROOT, mac_dir, fn)).size[0]
            save(down(s), f"{mac_dir}/{fn}")

    # windows .ico
    master.save(os.path.join(ROOT, "windows/runner/resources/app_icon.ico"),
                sizes=[(16, 16), (24, 24), (32, 32), (48, 48),
                       (64, 64), (128, 128), (256, 256)])

    print("generated all platform icon assets.")


if __name__ == "__main__":
    main()
