#!/usr/bin/env python3
"""Fetch the 52 CC0 standard playing-card SVGs (English pattern) from Wikimedia
Commons, verify each is CC0/Public Domain, and write them to
assets/playing/<slug>.svg. Appends a "Standard deck" section to
assets/CARD_ART_SOURCES.md.

SVGs are rendered at runtime by flutter_svg, so no rasterization. Re-runnable;
ABORTS if any image is missing or not CC0/PD — we bundle only unencumbered art.

Requires: curl (Python urllib lacks CA certs here).
Run: python3 fetch_playing_images.py
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse

UA = "juice-cards-fetch/1.0 (https://github.com/Taylor-Software/juice)"
OUT_DIR = "assets/playing"
SOURCES_MD = "assets/CARD_ART_SOURCES.md"

RANKS = {"Ace": "ace", "2": "2", "3": "3", "4": "4", "5": "5", "6": "6",
         "7": "7", "8": "8", "9": "9", "10": "10", "Jack": "jack",
         "Queen": "queen", "King": "king"}
SUITS = ["Spades", "Hearts", "Diamonds", "Clubs"]


def slug(name):
    return re.sub(r"^-|-$", "", re.sub(r"[^a-z0-9]+", "-", name.lower()))


def card_titles():
    """{card name: 'File:English pattern <rank> of <suit>.svg'}."""
    out = {}
    for suit in SUITS:
        for rank, word in RANKS.items():
            out[f"{rank} of {suit}"] = \
                f"File:English pattern {word} of {suit.lower()}.svg"
    return out


def api_imageinfo(titles):
    info = {}
    for i in range(0, len(titles), 25):
        url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({
            "action": "query", "prop": "imageinfo",
            "iiprop": "url|extmetadata", "format": "json",
            "titles": "|".join(titles[i:i + 25]),
        })
        out = subprocess.run(["curl", "-s", "-m", "30", "-A", UA, url],
                             capture_output=True, text=True).stdout
        for p in json.loads(out)["query"]["pages"].values():
            ii = p.get("imageinfo")
            info[p["title"]] = {
                "url": ii[0]["url"],
                "license": ii[0]["extmetadata"].get(
                    "LicenseShortName", {}).get("value", "?"),
            } if ii else None
    return info


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    cards = card_titles()
    info = api_imageinfo([t.replace("_", " ") for t in cards.values()])

    rows, license_errors = [], []
    for name, title in sorted(cards.items()):
        meta = info.get(title.replace("_", " "))
        if not meta:
            license_errors.append(f"{name}: NOT FOUND ({title})")
        elif meta["license"].upper() != "CC0" and \
                "public domain" not in meta["license"].lower():
            license_errors.append(
                f"{name}: NON-CC0/PD '{meta['license']}' ({title})")
        else:
            rows.append((name, slug(name), meta["url"], meta["license"]))
    if license_errors:
        print("\nABORT — unresolved or encumbered images:", file=sys.stderr)
        for e in license_errors:
            print("  " + e, file=sys.stderr)
        sys.exit(1)

    missing = []
    for name, s, url, _lic in rows:
        dst = f"{OUT_DIR}/{s}.svg"
        if os.path.exists(dst):
            continue
        ok = False
        for attempt in range(5):
            raw = subprocess.run(["curl", "-sL", "-m", "60", "-A", UA, url],
                                 capture_output=True).stdout
            if b"<svg" in raw[:4000]:
                with open(dst, "wb") as f:
                    f.write(raw)
                ok = True
                break
            time.sleep(1.5 * (attempt + 1))
        if not ok:
            missing.append(name)
            continue
        print(f"  ok  {name:18s} -> {dst}")
        time.sleep(0.2)

    if missing:
        print(f"\n{len(missing)} still missing (re-run to finish): "
              + ", ".join(missing), file=sys.stderr)
        sys.exit(1)

    # Append/replace the Standard-deck section in the shared sources file.
    section = "## Standard deck (English pattern, CC0)\n\n"
    section += "| slug | source | license |\n|---|---|---|\n"
    for _name, s, url, lic in rows:
        section += f"| {s} | {url} | {lic} |\n"
    existing = ""
    if os.path.exists(SOURCES_MD):
        existing = open(SOURCES_MD).read().split("## Standard deck")[0].rstrip()
    open(SOURCES_MD, "w").write(existing + "\n\n" + section)
    print(f"\nWrote {len(rows)} standard-deck SVGs + updated {SOURCES_MD}")


if __name__ == "__main__":
    main()
