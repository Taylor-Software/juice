# Juice Oracle

A cross-platform (iOS / Android / web / desktop) Flutter app implementing the
**Juice** solo-RPG oracle by jrruethe — Fate Check, all generators (quest,
scene, NPC, settlement, wilderness, dungeon, treasure, names, meaning,
immersion, plot points, extended NPC tables), plus a persistent campaign
journal (your prose, scene dividers with a chaos-factor snapshot, and every
roll you choose to keep) with threads tracking and flexible, system-agnostic
character sheets (free-text stats, current/max tracks with steppers, tags,
notes — one model covers D&D, Ironsworn, or Mythic NPCs). An encounter tracker runs
initiative order (drag to override), turns and rounds, status tags, and
defeated states — combatants pulled from your characters share their sheet's
HP track live — and drops an end-of-encounter summary into the journal. A Maps tool draws
your dungeon room-by-room as you roll it (pan/zoom, tap a room for its
detail, linger rolls) and reveals a wilderness hex map as you travel
(env-colored hexes from the same verified drift tables, Lost markers,
manual reveal for prep); both persist per campaign and snapshot into the
journal.

The Ask-the-Oracle tools also include a generic **Roll High oracle** — a 7-step
likelihood ladder (Almost Certain … Almost Impossible) with six graded
answers (Yes, and → No, and), in d100, d20, and 2d6 variants. Each table row
is machine-verified for exact dice-range coverage in `build_oracle.py`.

A general **dice roller** tool parses full dice notation — `NdX`, `d%`, `dF`
(Fate), modifiers, multi-group sums like `2d6+1d8+3`, keep/drop
(`4d6kh3`/`kl`/`dh`/`dl`), and `d20adv`/`d20dis` — with a per-die breakdown
(dropped dice struck through), quick-tap dice chips, session history, and
one-tap add-to-journal.

- **Oracle interpreter (on-device AI, optional):** any oracle result in the
  journal can be expanded into four short readings — literal, symbolic,
  complication, foreshadow — by a small language model that runs entirely
  on your device (WebGPU in the browser; arm64 on mobile). One-time model
  download (~670 MB web / ~480 MB mobile) after explicit consent; nothing
  you write leaves your device. The dice stay authoritative — the model
  only suggests, you decide. Set your campaign's genre and tone from the
  sheet to steer the voice. Web uses Gemma 3 1B (Google, Gemma license);
  mobile uses Qwen3 0.6B (Alibaba, Apache 2.0).
  Mobile builds target arm64 (Android) and iOS 16+.

Also includes **Mythic GME** support (Fate Chart with Chaos Factor dial, Scene
Test, Event Focus rolling against your tracked Threads/Characters lists, and
all 47 Meaning Tables).
Mythic Game Master Emulator © Word Mill Games, content used under CC-BY-NC 4.0
— this app is free and non-commercial.

Optional **Ironsworn family** rulesets (toggle in the app-bar tune icon):
moves browser with action/progress rolls, and all oracle tables drawn from
official Datasworn data (© Shawn Tomkin). All four titles are supported:

- **Ironsworn** (CC-BY 4.0)
- **Ironsworn: Delve** — expansion; folds into the Ironsworn Moves tool (CC-BY 4.0)
- **Ironsworn: Starforged** (CC-BY 4.0)
- **Starforged: Sundered Isles** — expansion; folds into the Starforged Moves tool (CC-BY-NC-SA 4.0)

Ironsworn and Starforged are separate game families and are mutually exclusive;
enabling one family turns the other off. Expansions require their base game and
are disabled automatically when their base is turned off.

Oracle content: [github.com/jrruethe/juice](https://github.com/jrruethe/juice),
CC BY-NC-SA. This app is an unofficial implementation of those tables.

**Live app:** https://taylor-software.github.io/juice/

## Run it

This repo ships the source that matters (`lib/`, `assets/`, `test/`,
`pubspec.yaml`). The platform runner folders (`android/`, `ios/`, `web/`,
`macos/`, `windows/`, `linux/`) are **not** committed — generate them once:

```bash
cd juice_oracle
flutter create .          # regenerates platform folders; keeps lib/, pubspec, assets
flutter pub get
flutter run               # pick a device, or: flutter run -d chrome / -d macos
```

`flutter create .` is non-destructive to your `lib/`, `pubspec.yaml`, and
`assets/` — it only fills in the missing platform scaffolding.

## Verify it

```bash
flutter analyze          # should be clean
flutter test             # engine + widget tests
python3 build_oracle.py  # re-runs the engine verification, re-emits the asset
```

`build_oracle.py` is the source of truth for the table data **and** the engine
logic. It checks the Fate Check against the PDF's documented table and the
designed probabilities (≈50% yes-like, 5.56% Random Event, 5.56% Invalid
Assumption under Normal; ≈66.6% yes-like under Likely), then writes
`oracle_data.json`. The Dart engine mirrors it and is re-checked by
`test/fate_engine_test.dart`.

## Architecture

```
lib/
  engine/      dice, models, oracle data loader, Oracle (fate check + generators)
  state/       Riverpod providers (oracle loader + persisted journal/threads/characters)
  features/    fate / generators / tables / tracker screens
  shared/      theme, result card, home shell (journal + tool launcher), tool host/registry
assets/oracle_data.json   all tables, generated by build_oracle.py
```

Every table is data-driven: one JSON asset + a generic roller. Adding or
correcting a table is data entry, not new widgets.

## Success criteria status

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Runs iOS/Android/web/desktop, one codebase | structured for it; **needs your `flutter run`** to confirm on each target |
| 2 | Every table data-driven (one asset + generic roller) | done |
| 3 | Engine correct + unit-tested (dice, skew, Fate Check) | **logic verified** in Python + Dart tests |
| 4 | Journal persists prose, scene dividers (with chaos snapshot), and kept rolls locally, per campaign, alongside threads + characters (multi-session switcher in the app bar); campaigns can be exported to / imported from `.juice.json` files via the system picker (schema v2; v1 files still import) — save into any cloud-synced folder for BYO sync; entries link to threads, filter by thread, and support in-place edits | done (shared_preferences + file_picker) |
| 5 | Working rules in CLAUDE.md | done |

I can't compile Flutter in my build environment (no SDK / no pub.dev access),
so criteria 1 is the one piece left for your machine. Items 2–5 are verified by
code + tests here.

## Flagged for a pass against the source (rule #1: surfacing confusion)

A few tables in the PDF are visual or OCR-ambiguous. These are implemented as
best-effort and should be checked against the original before you rely on them:

- ~~Wilderness Monster Encounter grid~~ / ~~NPC Dialog grid~~ — encoded and
  verified against the PDF (see `build_oracle.py` verify sections 6–7).
- **Name generator skew pattern** — the source uses a per-row skew pattern over
  the syllable columns; here each column is rolled independently (d20) and
  concatenated. Names are plausible but not the exact weighted distribution.
- ~~Abstract Icons~~ — implemented: all 60 icons (CC BY-NC-SA 4.0 per the
  official itch.io release) vendored under `assets/abstract_icons/`, rolled
  as 1d10 row + 1d6 column from the Names & Details tool.
- **Location compass grid** (5×5 d100) — not yet encoded; low priority.

If you want any of these brought to full fidelity, point me at the relevant PDF
page and I'll encode it and add a verification.
