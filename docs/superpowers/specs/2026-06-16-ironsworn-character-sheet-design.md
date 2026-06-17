# Pre-made character sheets — Slice A: Classic Ironsworn

**Date:** 2026-06-16
**Status:** Design approved, pending spec review
**Slice:** A of 3 (see "Larger context")

## Larger context

The headline request: let the user optionally pick a TTRPG ruleset to play, with
**pre-made character sheets** whose UI presentation is specific to each game (D&D,
Shadowdark, Ironsworn + derivatives), backed by the app's generic character model,
and eventually with the game's rules fed to the on-device LLM interpreter.

That request decomposes into three independent subsystems, each its own
spec → plan → build cycle:

- **Slice A — Character-sheet templates (this spec).** Per-system pre-made sheets +
  system-specific UI over the existing `Character` model. Starts with **Classic
  Ironsworn**, built to extend to the rest of the Ironsworn family and, later, to
  new systems.
- **Slice B — Rules-as-LLM-context.** Make the interpreter "know" the chosen game.
  NOT "feed a PDF" — the on-device model (Gemma 3 1B web / Qwen 0.6B mobile, ~700-token
  prompts, no network, no RAG) cannot ingest a rulebook, and D&D 5e full rules /
  Shadowdark core are not freely redistributable (only the D&D **SRD 5.1** and
  Shadowdark **quickstart** are; Ironsworn/Starforged are already CC-BY). Realistic
  shape: a small curated per-system rules primer (~200–400 tokens) or structured
  snippet retrieval from the datasworn JSON already vendored. Deferred.
- **Slice C — New d20 systems (D&D SRD, Shadowdark).** New system flags, new data
  assets, new dice/creation mechanics. Largest, most net-new. Deferred.

This spec covers **Slice A, Classic Ironsworn only**. Slices B and C, and the rest of
the Ironsworn family (Starforged/Delve/Sundered Isles), are explicitly out of scope
here but the design leaves clean seams for them.

## Goal & success criteria

A solo player whose campaign has the `ironsworn` system enabled can create a
**pre-made Classic Ironsworn player character** in one tap and play from a bespoke
sheet that looks and behaves like an Ironsworn sheet — five stats, three condition
meters, signed momentum with the burn/max/reset rules, debilities, XP, a bonds track,
vows as progress tracks, and assets picked from the vendored datasworn data.

Done when:

1. With `ironsworn` enabled, the Threads & Characters tool offers **"New Ironsworn
   character"**, which creates a `Character` carrying a pre-filled `IronswornSheet`
   (stats 3/2/2/1/1, meters 5/5/5, momentum +2) and opens the bespoke editor.
2. The bespoke sheet edits all of: stats (1..3), Health/Spirit/Supply (0..5), signed
   momentum (−6..max) with a working **Burn** button, debilities (toggling adjusts max
   momentum and re-clamps current), XP earned/spent, bonds (0..10), vows
   (add + advance by rank), assets (pick from datasworn + per-ability enable toggles).
3. A non-Ironsworn character still opens today's generic stat/track editor unchanged.
4. The sheet survives JSON round-trip and tolerates malformed stored data; it is
   included in campaign export/import with no schema bump.
5. `python3 build_datasworn.py` emits `asset_collections` for all rulesets and
   self-verifies them; `flutter analyze` and `flutter test` are clean.

## Non-goals (this slice)

- Feeding any rules text to the LLM interpreter (Slice B).
- Companion/asset **condition meters** and asset **input fields** (e.g. companion
  name) — the data is captured by the build script but the UI ignores it this phase.
- A multi-step guided creation wizard (we pre-fill sensible defaults and edit inline).
- Starforged, Delve, Sundered Isles sheets; D&D / Shadowdark (Slices C).

## Architecture

### Data model — `lib/engine/models.dart`

Add one optional typed sub-object to `Character`, mirroring the existing
`CharacterEmulation? emulation` pattern verbatim (constructor param → field →
conditional `toJson` → tolerant `maybeFromJson` → `copyWith` with a `clearIronsworn`
flag). No new SharedPreferences key, no campaign schema version bump — it persists in
`juice.characters.v1.<sessionId>` and is already covered by campaign export. A
character is an Ironsworn PC **iff** `ironsworn != null`.

```
class IronswornSheet
  // fixed five stats, each 1..3 (editable for tweak-inline)
  int edge, heart, iron, shadow, wits
  // condition meters 0..5
  int health, spirit, supply
  int momentum            // signed, −6..momentumMax   (see Mechanics)
  int xpEarned, xpSpent   // ≥0
  int bonds               // bond progress boxes 0..10
  Set<String> debilities  // ids from kIronswornDebilities (see Mechanics)
  List<ProgressTrack> vows
  List<AssetState> assets

class ProgressTrack       // reusable — Starforged legacy tracks reuse it later
  String name
  ProgressRank rank       // troublesome|dangerous|formidable|extreme|epic
  int ticks               // 0..40  (4 ticks = 1 box, 10 boxes)

class AssetState
  String assetId          // datasworn id, e.g. classic/assets/combat_talent/swordmaster
  String name
  String category
  List<bool> enabledAbilities   // parallel to the asset's abilities[]
```

Conventions to follow exactly (from the existing models):

- `toJson()` omits null/empty: scalars always present; `if (debilities.isNotEmpty)`,
  `if (vows.isNotEmpty)`, `if (assets.isNotEmpty)`.
- `static IronswornSheet? maybeFromJson(dynamic j)` returns null if `j is! Map`, and
  uses the shared local helpers `intOr` / `strings` (and a new `enumOr` for
  `ProgressRank`) so malformed values degrade to defaults rather than throwing. Same
  for `ProgressTrack.maybeFromJson` / `AssetState.maybeFromJson`.
- `copyWith` on `IronswornSheet` takes plain nullable params (value-or-this); the
  *clearing* flag lives on `Character.copyWith` (`bool clearIronsworn = false`).

`ProgressRank` is a top-level enum in `models.dart`. A small const
`kIronswornDebilities` lists the eight Classic debility ids + display labels (conditions:
wounded, shaken, unprepared, encumbered; banes: maimed, corrupted; burdens: cursed,
tormented).

### Asset data — `build_datasworn.py` + `assets/ruleset_*.json`

The build script currently emits only `move_categories` and `oracle_collections`;
`src["assets"]` is ignored. Extend it (the script is the source of truth — never
hand-edit the generated JSON):

- Add `transform_assets(src.get("assets") or {})` that flattens each asset collection's
  `contents` map into a list, emitting per asset:
  `{ id, name, category, requirement, abilities: [{ text, enabled }] }`.
  Capture `options` and `controls.health` into the output too (forward-compatible for
  the deferred companion-meter phase) but the Dart side ignores them for now.
- Emit a new top-level key `asset_collections` alongside the existing keys, for **all
  four** rulesets (classic has 78 assets across Combat Talent/Companion/Path/Ritual;
  the others come for free and feed future slices).
- Add an asset block to `verify()` matching the existing style: non-empty when the
  source has assets, every asset id well-formed, every ability `text` non-empty.
- Print an asset count line per output, like the existing move/oracle counts.

Rerun `python3 build_datasworn.py`, copy the regenerated `ruleset_*.json` into
`assets/`. Loaded at runtime via the existing `rulesetDataProvider('classic')` family
provider — no new provider needed.

### Mechanics

- **Momentum** is the one value the generic `CharTrack` cannot hold (it clamps ≥0), so
  it is a plain signed int on the sheet. Derived, not stored:
  `momentumMax = 10 − debilities.length`,
  `momentumReset = max(0, 2 − debilities.length)`.
  - +/- steppers clamp current momentum to `[-6, momentumMax]`.
  - **Burn** button sets `momentum = momentumReset`.
  - Toggling a debility recomputes max and re-clamps current momentum down if needed.
- **Stats** editable 1..3. **Meters** 0..5 box steppers. **XP/Bonds** integer steppers
  (bonds 0..10). 
- **Vows / progress tracks**: a "+" advances `ticks` by the rank's mark size
  (troublesome 12, dangerous 8, formidable 4, extreme 2, epic 1 ticks per mark),
  clamped 0..40; tapping a box does a manual single-box (±4 tick) edit. Rank editable.

### UI — `lib/features/ironsworn_sheet.dart` (new) + `lib/features/tracker_screen.dart`

- **Render branch:** in `CharactersPane._buildSheet` resolution (tracker_screen.dart
  ~:137), if `c.ironsworn != null` render the new `IronswornSheetView(character: c)`;
  else the current generic editor. The bespoke widget lives in its own file to keep
  `tracker_screen.dart` focused.
- **Create action:** `CharactersPane` reads
  `ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ?? kAllSystems`.
  When it contains `ironsworn`, the add affordance offers two choices — "New character"
  (today's generic quick-add) and **"New Ironsworn character"**. The Ironsworn path
  creates a `Character` whose `ironsworn` is a pre-filled `IronswornSheet`
  (3/2/2/1/1, meters 5/5/5, momentum +2, empty vows/assets/debilities) and opens it.
- **Asset picker:** a dialog that reads `rulesetDataProvider('classic')`, lists assets
  grouped by `category`, and on pick appends an `AssetState` (abilities seeded from each
  ability's `enabled` default). Each asset card on the sheet shows its abilities with a
  per-ability enable checkbox; "+ Add asset" opens the picker; assets are removable.
  If no Ironsworn ruleset is active in `rulesetsProvider`, the create action enables
  `classic` first (so the picker has data).
- All edits persist immediately via `charactersProvider.notifier.replace(updated)`,
  exactly like the generic editor's steppers.

### Extensibility (seam only — nothing speculative built)

The repeatable template is: an optional typed sheet field on `Character` + a
render-branch in `_buildSheet` + a system-gated create action. Documented for:

- **Ironsworn family:** reuse `IronswornSheet` + `ProgressTrack`; branch
  debilities↔impacts and bonds↔legacy-tracks by the active ruleset.
- **New systems (Slice C):** parallel `dnd` / `shadowdark` optional fields, their own
  system flags and data assets.

If a third system sheet ever lands, revisit collapsing the parallel fields into a
sealed `SystemSheet` — not now (YAGNI).

## Testing

- **Model** (`test/character_sheet_test.dart`): `IronswornSheet` / `ProgressTrack` /
  `AssetState` JSON round-trip; tolerant parse of malformed/partial maps (degrade to
  defaults, never throw); `Character` copyWith set + `clearIronsworn`; momentum
  max/reset derivation from debilities.
- **Widget** (`test/character_sheet_ui_test.dart`): stat edit; meter steppers clamp
  0..5; signed momentum stepper + Burn; debility toggle lowers max and re-clamps;
  asset pick from a fixture + ability toggle; vow add + rank advance; and that a
  non-Ironsworn character still shows the generic editor.
  - **Must** override `rulesetDataProvider` with an in-memory/file fixture and mock
    SharedPreferences; never call any `*.load()` (the rootBundle widget-test hang).
- **Build:** `python3 build_datasworn.py` self-verifies assets and exits non-zero on
  failure; regenerated JSON copied into `assets/`.
- **Gate:** `flutter analyze` clean, `flutter test` green.

## Risks / open points

- **Datasworn ability text is Markdown with move links** (`[Strike](id)`); render as
  plain text this phase (strip/loosely render link syntax) — faithful move-link
  resolution is not in scope.
- **Asset count (78)** makes the picker long; group-by-category + a search field keeps
  it usable. Search is a nice-to-have, not a gate.
- **"c" approval** during brainstorming was read as approve-all; if any section was
  meant to be revised, fix before implementation.
