# Third-party content & licenses

Loreseer incorporates third-party tabletop content, oracle
tables, and artwork under the licenses below. This file is the canonical
inventory; in-app attributions live in **Settings → Third-party content**
(`lib/features/settings_sheet.dart`), and each vendored data set carries its
provenance in the header of its `build_*.py` rail.

> **The app is free and non-commercial.** Several sources are licensed
> CC BY-**NC**(-SA), which requires it. See "License obligations" at the end.

---

## Vendored rules / oracle content

Actual third-party text and tables, transcribed or transformed into the bundled
assets.

| Content | Author / publisher | License | Incorporated as |
|---|---|---|---|
| Ironsworn, Starforged, Sundered Isles, Delve (Datasworn) | Shawn Tomkin | CC BY 4.0 | `data/datasworn/*.json` → `assets/ruleset_*.json` (`build_datasworn.py`) |
| Juice oracle (tables + engine logic) | jrruethe | CC BY-NC-SA | `assets/oracle_data.json` (`build_oracle.py`) |
| Mythic GME 2e (Fate Chart + 47 Meaning Tables) | Word Mill Games (Tana Pigeon) | CC BY-NC 4.0 | `data/mythic_meaning/` → `assets/oracle_data.json` |
| Triple-O — The Player Character Emulator v1.0.2 | Cezar Capacle / Critical Kit | CC BY-SA 4.0 | `assets/emulator_data.json` (`build_emulator.py`) |
| Pettish — PET (Player Emulator with Tags) + Sidekick oracle | Tam H (hedonic.ink) | CC BY 4.0 | `assets/emulator_data.json` |
| Verdant Hexcrawling | Vince Pinton / Ibir Publishing | CC BY-NC-SA 4.0 | `assets/verdant_data.json` (`build_verdant.py`) |
| Lonelog notation legend (core rulebook + 7 addons) | Roberto Bisceglie | CC BY-SA 4.0 | `assets/lonelog_data.json` (`build_lonelog.py`) |

The generic Hexcrawl toolkit (`assets/hexcrawl_data.json`) is **authored,
system-agnostic content** released CC0 — not third-party.

---

## Bundled artwork

| Art | Source | License | Location |
|---|---|---|---|
| Tarot deck — 78 cards (Rider–Waite–Smith, Pamela Colman Smith, 1909) | Wikimedia Commons | Public domain | `assets/tarot/*.jpg` |
| Standard 52-card deck (English pattern) | Wikimedia Commons | CC0 | `assets/playing/*.svg` |
| Abstract Icons — 60 icons | itch.io release | CC BY-NC-SA 4.0 | `assets/abstract_icons/` |

Per-file sources are tracked in `assets/CARD_ART_SOURCES.md`.

---

## Character sheets — facts-only

The bespoke character sheets reproduce **only non-copyrightable game-mechanic
facts** (ability/stat names, class/archetype names, save/pact names, dice
formulas). No rulebook prose, art, tables, or feature text is bundled. Where a
system's license is open or a courtesy notice is appropriate, an attribution
appears in Settings → Third-party content.

**With an in-app attribution notice:**

| Sheet | Notice |
|---|---|
| Draw Steel | Independent product under the Draw Steel Creator License; not affiliated with MCDM Productions, LLC. |
| Tales of Argosa | CC BY-SA 4.0, © Pickpocket Press / S J Grodzicki. Not affiliated. |
| Cairn | CC BY-SA 4.0, © Yochai Gal. Not affiliated. |
| Knave 2e | CC BY 4.0, © Ben Milton (Questing Beast). Not affiliated. |
| OSE / B/X | Non-copyrightable B/X mechanics; compatible with Old-School Essentials (Necrotic Gnome / Gavin Norman). Not affiliated. |

**No attribution (strictest facts-only posture — restrictive or absent license):**

| Sheet | Reason |
|---|---|
| Shadowdark | No open license; 3rd-party license excludes apps. |
| Kal-Arath | © 2023 Castle Grief, personal-use-copy only (not an app license). |
| D&D 5e | Authored mechanic constants only; vendored SRD content deferred. |
| Nimble | Facts-only P1 (open license allows a richer version later). |

---

## License obligations

- **Non-commercial (the app must remain free):** Juice (CC BY-NC-SA),
  Mythic GME (CC BY-NC), Verdant (CC BY-NC-SA), and Abstract Icons
  (CC BY-NC-SA) all forbid commercial use.
- **Share-alike (derived data stays under the same license):** Juice, Triple-O,
  Verdant, Lonelog, Cairn, Tales of Argosa, and Abstract Icons are all `-SA`.
- **Attribution:** required by every CC BY/BY-SA/BY-NC source above; rendered in
  Settings → Third-party content and in this file.

No bundled rulebook PDFs or licensed prose. Pre-made sheets are mechanics-only.
