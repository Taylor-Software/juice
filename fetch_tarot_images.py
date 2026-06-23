#!/usr/bin/env python3
"""Fetch the 78 public-domain Rider-Waite-Smith (1909) tarot images from
Wikimedia Commons, verify each is Public Domain, optimize, and write them to
assets/tarot/<slug>.jpg. Also writes assets/CARD_ART_SOURCES.md (provenance).

This is the source of truth + provenance record for the bundled tarot art
(like build_oracle.py for data). Re-runnable. ABORTS if any image is missing or
not Public Domain — we bundle only unencumbered assets.

Requires: curl (Python's urllib lacks CA certs in this env), Pillow.
Run: python3 fetch_tarot_images.py
"""
import io
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse

from PIL import Image

# Wikimedia requires a descriptive User-Agent; bulk hits without one get blocked.
UA = "juice-tarot-fetch/1.0 (https://github.com/Taylor-Software/juice)"
OUT_DIR = "assets/tarot"
SOURCES_MD = "assets/CARD_ART_SOURCES.md"
MAX_EDGE = 600
JPEG_QUALITY = 82

MAJORS = {
    "The Fool": "RWS_Tarot_00_Fool",
    "The Magician": "RWS_Tarot_01_Magician",
    "The High Priestess": "RWS_Tarot_02_High_Priestess",
    "The Empress": "RWS_Tarot_03_Empress",
    "The Emperor": "RWS_Tarot_04_Emperor",
    "The Hierophant": "RWS_Tarot_05_Hierophant",
    "The Lovers": "RWS_Tarot_06_Lovers",
    "The Chariot": "RWS_Tarot_07_Chariot",
    "Strength": "RWS_Tarot_08_Strength",
    "The Hermit": "RWS_Tarot_09_Hermit",
    "Wheel of Fortune": "RWS_Tarot_10_Wheel_of_Fortune",
    "Justice": "RWS_Tarot_11_Justice",
    "The Hanged Man": "RWS_Tarot_12_Hanged_Man",
    "Death": "RWS_Tarot_13_Death",
    "Temperance": "RWS_Tarot_14_Temperance",
    "The Devil": "RWS_Tarot_15_Devil",
    "The Tower": "RWS_Tarot_16_Tower",
    "The Star": "RWS_Tarot_17_Star",
    "The Moon": "RWS_Tarot_18_Moon",
    "The Sun": "RWS_Tarot_19_Sun",
    "Judgement": "RWS_Tarot_20_Judgement",
    "The World": "RWS_Tarot_21_World",
}
RANKS = ["Ace", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight",
         "Nine", "Ten", "Page", "Knight", "Queen", "King"]
SUITS = {"Wands": "Wands", "Cups": "Cups", "Swords": "Swords",
         "Pentacles": "Pents"}


def card_titles():
    """Returns {card name: Commons File base (no 'File:' / extension)}."""
    out = dict(MAJORS)
    for suit, prefix in SUITS.items():
        for i, rank in enumerate(RANKS, start=1):
            out[f"{rank} of {suit}"] = f"{prefix}{i:02d}"
    return out


def slug(name):
    return re.sub(r"^-|-$", "", re.sub(r"[^a-z0-9]+", "-", name.lower()))


def api_imageinfo(file_titles):
    """Batch query Commons for url + license. file_titles: ['File:...jpg', ...]."""
    out = {}
    for i in range(0, len(file_titles), 25):
        batch = file_titles[i:i + 25]
        url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({
            "action": "query", "prop": "imageinfo",
            "iiprop": "url|extmetadata", "format": "json",
            "titles": "|".join(batch),
        })
        res = subprocess.run(["curl", "-s", "-m", "30", "-A", UA, url],
                             capture_output=True, text=True)
        data = json.loads(res.stdout)
        for p in data["query"]["pages"].values():
            ii = p.get("imageinfo")
            if not ii:
                out[p["title"]] = None
                continue
            em = ii[0].get("extmetadata", {})
            out[p["title"]] = {
                "url": ii[0]["url"],
                "license": em.get("LicenseShortName", {}).get("value", "?"),
            }
    return out


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    cards = card_titles()
    # Commons normalizes "File:Foo.jpg" titles with spaces; query with spaces.
    file_titles = [f"File:{base.replace('_', ' ')}.jpg" for base in cards.values()]
    info = api_imageinfo(file_titles)

    # License gate first: every card must resolve to a Public-Domain file.
    rows, license_errors = [], []
    for name, base in sorted(cards.items()):
        title = f"File:{base.replace('_', ' ')}.jpg"
        meta = info.get(title)
        if not meta:
            license_errors.append(f"{name}: NOT FOUND ({title})")
        elif "public domain" not in meta["license"].lower():
            license_errors.append(
                f"{name}: NON-PD license '{meta['license']}' ({title})")
        else:
            rows.append((name, slug(name), meta["url"], meta["license"]))
    if license_errors:
        print("\nABORT — unresolved or non-PD images:", file=sys.stderr)
        for e in license_errors:
            print("  " + e, file=sys.stderr)
        sys.exit(1)

    # Download missing files (idempotent: skip existing; retry + be polite).
    missing = []
    for name, s, url, _lic in rows:
        dst = f"{OUT_DIR}/{s}.jpg"
        if os.path.exists(dst):
            continue
        img = None
        for attempt in range(5):
            raw = subprocess.run(["curl", "-sL", "-m", "60", "-A", UA, url],
                                 capture_output=True).stdout
            try:
                img = Image.open(io.BytesIO(raw)).convert("RGB")
                break
            except Exception:  # noqa: BLE001
                time.sleep(1.5 * (attempt + 1))
        if img is None:
            missing.append(name)
            continue
        img.thumbnail((MAX_EDGE, MAX_EDGE), Image.LANCZOS)
        img.save(dst, "JPEG", quality=JPEG_QUALITY, optimize=True)
        print(f"  ok  {name:20s} -> {dst}  ({img.size[0]}x{img.size[1]})")
        time.sleep(0.3)

    if missing:
        print(f"\n{len(missing)} still missing (transient — re-run to finish): "
              + ", ".join(missing), file=sys.stderr)
        sys.exit(1)

    with open(SOURCES_MD, "w") as f:
        f.write("# Bundled card art — sources & licenses\n\n")
        f.write("Generated by `fetch_tarot_images.py`. All Public Domain.\n\n")
        f.write("## Tarot (Rider–Waite–Smith, Pamela Colman Smith, 1909)\n\n")
        f.write("| slug | source | license |\n|---|---|---|\n")
        for _name, s, url, lic in rows:
            f.write(f"| {s} | {url} | {lic} |\n")
    print(f"\nWrote {len(rows)} tarot images + {SOURCES_MD}")


if __name__ == "__main__":
    main()
