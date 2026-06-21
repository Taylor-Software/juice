"""Generates the app icon (Solo Adventurer's Journal) at 1024px with Pillow.

Supersamples 4x then downsamples for clean edges. Motif: an open journal with
ruled lines + an oracle "spark", cream on the deep-amber brand color. Run:
    python3 tool/make_icon.py
Output: assets/icon/app_icon.png (full-bleed) + app_icon_fg.png (android adaptive
foreground, transparent with the motif in the maskable safe zone).
"""
import os
from PIL import Image, ImageDraw

S = 4096            # supersample canvas
OUT = 1024
CREAM = (251, 244, 233, 255)
AMBER_TOP = (200, 94, 20, 255)
AMBER_BOT = (150, 62, 10, 255)
RIBBON = (140, 40, 24, 255)
LINE = (200, 94, 20, 255)   # ruled lines (amber, on the cream page)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(4))


def vgradient(size, top, bot):
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        c = lerp(top, bot, y / (size - 1))
        for x in range(size):
            px[x, y] = c
    return img


def draw_motif(d, s):
    """Draw the open-book + spark motif onto draw `d` on an s x s canvas."""
    cx = s / 2
    # --- open book: two pages meeting at a center valley ---
    top = s * 0.40       # page top edge height
    valley = s * 0.50    # center dip
    bottom = s * 0.72    # page bottom (spine area)
    left = s * 0.16
    right = s * 0.84
    inset = s * 0.05     # spine gap at center
    # left page quad
    d.polygon([
        (left, top + s * 0.02),
        (cx - inset, valley),
        (cx - inset, bottom),
        (left, bottom - s * 0.05),
    ], fill=CREAM)
    # right page quad (mirror)
    d.polygon([
        (right, top + s * 0.02),
        (cx + inset, valley),
        (cx + inset, bottom),
        (right, bottom - s * 0.05),
    ], fill=CREAM)
    # ruled text lines on each page
    lw = max(2, int(s * 0.008))
    for i, fy in enumerate((0.56, 0.62, 0.68)):
        y = s * fy
        d.line([(left + s * 0.05, y), (cx - inset - s * 0.03, y + s * 0.012)],
               fill=LINE, width=lw)
        d.line([(cx + inset + s * 0.03, y + s * 0.012),
                (right - s * 0.05, y)], fill=LINE, width=lw)
    # ribbon bookmark hanging from the spine
    d.polygon([
        (cx - s * 0.025, bottom - s * 0.02),
        (cx + s * 0.025, bottom - s * 0.02),
        (cx + s * 0.025, bottom + s * 0.12),
        (cx, bottom + s * 0.08),
        (cx - s * 0.025, bottom + s * 0.12),
    ], fill=RIBBON)
    # --- d20 die above the book (solo-RPG mark) ---
    import math
    sx, sy = cx, s * 0.26
    R = s * 0.135
    # pointy-top hexagon outline (cream fill)
    hexp = [(sx + R * math.cos(math.radians(90 + 60 * k)),
             sy - R * math.sin(math.radians(90 + 60 * k))) for k in range(6)]
    d.polygon(hexp, fill=CREAM)
    # inner upward triangle (the top face) + spokes to alternate hex vertices
    r2 = R * 0.46
    tri = [(sx + r2 * math.cos(math.radians(90 + 120 * k)),
            sy - r2 * math.sin(math.radians(90 + 120 * k))) for k in range(3)]
    lw = max(2, int(s * 0.0065))
    for i in range(3):
        d.line([tri[i], tri[(i + 1) % 3]], fill=LINE, width=lw)
    # spokes: each triangle vertex to the hex vertex it points at (0,2,4)
    for i in range(3):
        d.line([tri[i], hexp[(i * 2) % 6]], fill=LINE, width=lw)


def main():
    # Full-bleed icon
    big = vgradient(S, AMBER_TOP, AMBER_BOT)
    d = ImageDraw.Draw(big)
    draw_motif(d, S)
    icon = big.resize((OUT, OUT), Image.LANCZOS)

    # Android adaptive foreground: transparent bg, motif shrunk into the inner
    # ~66% safe zone (adaptive masks crop the outer ~18% per side; a circle mask
    # is tighter still), so the d20 tip + page corners never clip.
    fg_big = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fg_big)
    draw_motif(fd, S)
    safe = round(OUT * 0.66)
    scaled = fg_big.resize((safe, safe), Image.LANCZOS)
    fg = Image.new("RGBA", (OUT, OUT), (0, 0, 0, 0))
    off = (OUT - safe) // 2
    fg.paste(scaled, (off, off), scaled)

    os.makedirs("assets/icon", exist_ok=True)
    icon.save("assets/icon/app_icon.png")
    fg.save("assets/icon/app_icon_fg.png")
    print("wrote assets/icon/app_icon.png + app_icon_fg.png")


if __name__ == "__main__":
    main()
