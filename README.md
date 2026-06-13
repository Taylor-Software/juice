# Juice Oracle

**Play it now:** https://taylor-software.github.io/juice/ — free, no account,
your campaigns stay on your device.

![The campaign journal: scenes with chaos factor, oracle results, prose, an
on-device AI reading, and thread links](docs/screenshots/journal.png)

A cross-platform (iOS / Android / web / desktop) Flutter app implementing the
**Juice** solo-RPG oracle by jrruethe — Fate Check, all generators (quest,
scene, NPC, settlement, wilderness, dungeon, treasure, names, meaning,
immersion, plot points, extended NPC tables), plus a persistent campaign
journal (your prose, scene dividers with a chaos-factor snapshot, and every
roll you choose to keep — searchable, taggable, and exportable as Markdown or
a styled standalone HTML page for sharing) with threads tracking and flexible,
system-agnostic
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

Oracle and dice results land in the journal as **structured entries**: a
summary, the individual roll rows, a one-tap **re-roll**, and **open-in-tool**
to jump back to the tool that produced them.

- Slash commands: type `/` in the journal to roll a fate check, dice, or a
  quick generator without opening a tool — the result lands inline.

- Campaign header: a collapsible band over the journal shows the current scene, Mythic chaos, pinned threads, starred characters, and crawl state — each opens its tool. Set the campaign's default oracle here.

- System profiles: pick which systems a campaign uses (Juice, Mythic, Ironsworn, Party) when you create it — the tools, slash commands, and header scope to that set. Existing campaigns keep everything.

- Mentions: type `@` in the journal to link a character or thread; mentions render as tappable links and filter the journal. Save an NPC or location result as a tracked entity in one tap.

- **Oracle interpreter (on-device AI, optional):** any oracle result in the
  journal can be expanded into four short readings — literal, symbolic,
  complication, foreshadow — by a small language model that runs entirely
  on your device (WebGPU in the browser; arm64 on mobile). One-time model
  download (~670 MB web / ~480 MB mobile) after explicit consent; nothing
  you write leaves your device. The dice stay authoritative — the model
  only suggests, you decide. Readings can draw on the most relevant earlier
  journal entries, retrieved on device, so interpretations remember your
  campaign's people and places. Set your campaign's genre and tone from the
  sheet to steer the voice. Web uses Gemma 3 1B (Google, Gemma license);
  mobile uses Qwen3 0.6B (Alibaba, Apache 2.0).
  Mobile builds target arm64 (Android) and iOS 16+.

Also includes **Mythic GME** support (Fate Chart with Chaos Factor dial, Scene
Test, Event Focus rolling against your tracked Threads/Characters lists, and
all 47 Meaning Tables).
Mythic Game Master Emulator © Word Mill Games, content used under CC-BY-NC 4.0
— this app is free and non-commercial.

A **Party** toolkit begins with Behavior Tables — all thirteen Triple-O spark
and specific d66 tables (© Cezar Capacle / Critical Kit, CC-BY-SA 4.0) for
deciding what characters do, with the zine's spark combos (Action + Focus,
Action + Method, Action + Motivation) and one-tap add-to-journal. The Party
Emulator runs the Triple-O check itself: name the Obvious / Option / Odd (or
let dice assign a group's three courses), then roll a d6 — or Double-Down with
2d6 and keep your favorite. Doubles grow the behavior into a character Trait,
adding a new tag or marking an existing one prominent on the character sheet.
PET procedures complete the emulator: each character keeps an Agenda, a Focus,
and tokens — ACT rolls the agenda with a coin (the Ask as written or inverted)
plus a modifier die (as written / inverted / exaggerated) and grants a token on
an agenda match, spending a personality tag yields two readings, and session
start deals a fresh Focus, a real-life event, and a clean slate of tags.
Sidekick Dialogue gives characters words: 2d6 lines keyed to a persisted mood
(doubles change the mood first), tone/topic/said-how chips, and a 19-hex
conversation hexflower that walks between history and current events with a
me/you/us priority die — and any rolled line can be voiced into a full
in-character utterance by the on-device interpreter.

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

An in-app **Help** tool (in the launcher, plus a "?" on every tool's header)
covers every tool with a user guide, gives a quick-reference summary of each
supported system, and ends in a credits page listing all content licenses —
with Flutter's package-license viewer one tap away.

Oracle content: [github.com/jrruethe/juice](https://github.com/jrruethe/juice),
CC BY-NC-SA. This app is an unofficial implementation of those tables.
Party emulator content: Triple-O © Cezar Capacle / Critical Kit, CC-BY-SA 4.0
(the derived table data in `assets/emulator_data.json` stays CC-BY-SA 4.0);
PET & Sidekick © Tam H (hedonic.ink), CC-BY 4.0.

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
- ~~Location compass grid~~ — implemented: 1d100 onto the 5×5 compass grid,
  formula verified against the PDF's cell ranges (`build_oracle.py` verify
  section 11), rolled from the Exploration tool.

If you want any of these brought to full fidelity, point me at the relevant PDF
page and I'll encode it and add a verification.
