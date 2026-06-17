# Starforged character sheet — slice A continued

**Date:** 2026-06-17
**Status:** Design approved, pending spec review
**Builds on:** `docs/superpowers/specs/2026-06-16-ironsworn-character-sheet-design.md` (Classic Ironsworn sheet, shipped in PR #69)

## Context

Slice A of the pre-made-character-sheets feature shipped a bespoke **Classic
Ironsworn** sheet over the generic `Character` model (`IronswornSheet` optional
typed field, `lib/features/ironsworn_sheet.dart`, datasworn asset picker). This
spec extends slice A to **Starforged**, the second Ironsworn-family ruleset
(`assets/ruleset_starforged.json` is already vendored). Sundered Isles (which
extends Starforged the way Delve extends Classic) is explicitly **out of scope**
here; the design leaves a clean seam for it.

## Verified Starforged deltas (from `data/datasworn/starforged.json`)

Same as Classic: the five stats (edge/heart/iron/shadow/wits, 1..3), the three
condition meters (health/spirit/supply, 0..5), and momentum (−6..max, max/reset
derived from marked impacts). Different:

- **Debilities → Impacts.** 10 impacts in 4 categories: `misfortunes` (wounded,
  shaken, unprepared), `vehicle_troubles` (battered, cursed), `burdens` (doomed,
  tormented, indebted), `lasting_effects` (permanently_harmed, traumatized).
  Each marked impact lowers max momentum by 1 (same rule as Classic debilities).
- **XP + single bonds track → three Legacy tracks.** Quests, Bonds, Discoveries —
  each a 10-box track. (XP itself stays a manual earned/spent counter, as in
  Classic — see Non-goals.)
- **Connections.** Starforged tracks relationships as progress tracks (rank +
  ticks), mechanically identical to sworn vows.
- **Assets.** 87 assets across 6 categories (Path 46, Module 15, Companion 11,
  Deed 7, Support Vehicle 7, Command Vehicle 1) — already emitted by
  `build_datasworn.py` as `asset_collections` in `ruleset_starforged.json`.

## Goal & success criteria

A player whose campaign has the `ironsworn` system enabled can create a pre-made
**Starforged** player character in one tap and play from a bespoke sheet:
stats, three condition meters, signed momentum with Burn, **impacts**, **three
legacy tracks**, XP, sworn **vows**, **connections**, and **Starforged assets**
picked from the vendored datasworn data.

Done when:

1. With `ironsworn` enabled, the Threads & Characters create flow offers a
   three-way choice — **Generic / Ironsworn / Starforged** — and "Starforged"
   creates a `Character` carrying a pre-filled `StarforgedSheet` (stats 3/2/2/1/1,
   meters 5/5/5, momentum +2, empty legacy/impacts/vows/connections/assets) and
   opens the bespoke editor.
2. The Starforged sheet edits: stats (1..3), Health/Spirit/Supply (0..5), signed
   momentum (−6..max) with Burn, impacts (toggling adjusts max momentum + re-clamps
   current), XP earned/spent, the three legacy tracks (0..10 boxes each), vows and
   connections (add + advance by rank), assets (pick from the 87 Starforged assets
   + per-ability enable toggles).
3. A Classic Ironsworn character still opens `IronswornSheetView`; a non-family
   character still opens the generic editor; both unchanged.
4. The sheet survives JSON round-trip, tolerates malformed stored data, and is
   included in campaign export/import with no schema bump.
5. The shared sheet widgets are extracted and reused by both sheets; `flutter
   analyze` + `flutter test` clean.

## Non-goals (this slice)

- **Sundered Isles** (its own later slice; reuses `StarforgedSheet`).
- **Auto-deriving XP** from legacy-track boxes — the Starforged formula is fiddly
  and error-prone; XP stays a manual earned/spent counter (mirrors Classic).
- **Beyond-10 legacy checkmarks** (the advanced "10+" row).
- Companion/asset condition meters + asset input fields (still deferred from
  slice A), guided creation wizard, D&D/Shadowdark, LLM-rules.

## Architecture

### Decision: separate `StarforgedSheet` + shared widgets

A new `StarforgedSheet` model and an optional `Character.starforged` field, parallel
to `Character.ironsworn` (same additive pattern: constructor param → field →
conditional `toJson` → tolerant `maybeFromJson` → `copyWith` with `clearStarforged`
flag). No campaign-schema bump. The bulky reusable UI is extracted into a new
`lib/features/sheet_widgets.dart`; both sheets consume it.

### Data model — `lib/engine/models.dart`

```
class StarforgedSheet
  int edge, heart, iron, shadow, wits        // 1..3
  int health, spirit, supply                 // 0..5
  int momentum                               // −6..momentumMax
  int xpEarned, xpSpent                       // ≥0
  int questsLegacy, bondsLegacy, discoveriesLegacy  // 0..10 boxes
  Set<String> impacts                        // ids from kStarforgedImpacts
  List<ProgressTrack> vows
  List<ProgressTrack> connections
  List<AssetState> assets

  int get momentumMax   => 10 - impacts.length
  int get momentumReset => (2 - impacts.length).clamp(0, 2)
  factory StarforgedSheet.premade()          // 3/2/2/1/1, meters 5, momentum 2
```

Reuses `ProgressTrack` (+`ProgressRank`), `AssetState`, and `IronswornAssetDef`
from slice A unchanged. `copyWith` re-clamps momentum to the new max when impacts
change (identical to `IronswornSheet`). `maybeFromJson` drops unknown impact ids,
clamps all ranges, tolerates junk — same conventions as `IronswornSheet`.

`kStarforgedImpacts` is a const `Map<String,String>` (id→label) authored in Dart,
parallel to `kIronswornDebilities`: wounded, shaken, unprepared, battered, cursed,
doomed, tormented, indebted, permanently_harmed, traumatized. (No build-script
change — only this small impacts list is authored; the 87 SF assets are already
emitted.)

### Shared widgets — `lib/features/sheet_widgets.dart` (new)

Extract from `ironsworn_sheet.dart` and reuse in both sheets:

- `StatStepper` (label + value + −/+), `MeterStepper` (0..5 box stepper),
  `IntStepper` (generic ±), `MomentumRow` (signed value + −/+ + Burn + max/reset
  caption), `ProgressTrackRow` (vow/connection row: name, rank dropdown, mark/un-mark,
  delete, boxes/10), the progress-track add dialog, and `AssetCard` + `addAssetDialog`
  (the datasworn picker). Each takes plain values + callbacks so it is sheet-agnostic.

`ironsworn_sheet.dart` is refactored to consume these (pure refactor; slice-A widget
tests stay green, same widget keys preserved). This is a targeted improvement to the
code being extended, not unrelated refactoring.

### Slice-A correctness fix (folded in)

Today `IronswornSheetView` computes its asset `assetRid` from the global
`rulesetsProvider` toggle (`starforged` else `classic`). With two sheet types
coexisting and the toggle being mutually exclusive, a Classic sheet could read
Starforged assets. Fix: **each sheet pins its own ruleset** — `IronswornSheetView`
always uses `classic`, `StarforgedSheetView` always uses `starforged`. The asset
picker no longer depends on the global toggle. (`rulesetDataProvider(id)` loads the
bundled JSON regardless of toggle state.)

### UI placement + create flow — `lib/features/tracker_screen.dart`

- **Render branch** (in `CharactersPaneState.build`, after id resolution):
  `c.starforged != null` → `StarforgedSheetView`; else `c.ironsworn != null` →
  `IronswornSheetView`; else `_buildSheet` (generic).
- **Create flow:** the existing chooser (shown when `enabledSystems` contains
  `ironsworn`) becomes three buttons — **Generic / Ironsworn / Starforged**.
  Selecting Starforged ensures the `starforged` ruleset toggle is on (via
  `rulesetsProvider.setRuleset('starforged', true)`, for Moves-tool parity — note
  this drops the `classic` toggle, which is fine; existing Classic sheets keep
  rendering and pin their own `classic` assets) and calls a new
  `CharacterNotifier.addStarforged()` that prepends a `Character` with a pre-filled
  `StarforgedSheet`, then opens it. Keys: `new-generic`, `new-ironsworn`,
  `new-starforged`.
- **`StarforgedSheetView`** (new file `lib/features/starforged_sheet.dart`):
  a ConsumerWidget mirroring `IronswornSheetView`'s structure, built from the
  shared widgets. Sections top→bottom: header/rename, Stats, Condition Meters,
  Momentum, Impacts (flat chip `Wrap` over `kStarforgedImpacts`), Legacy Tracks
  (3 box-steppers), Experience (earned/spent), Vows, Connections, Assets, Notes.
  Edits persist via `charactersProvider.notifier.replace(c.copyWith(starforged:…))`.

## Extensibility (seam only)

Sundered Isles reuses `StarforgedSheet` + `ruleset_sundered_isles.json` assets;
only the impact set / asset deltas differ. A later slice adds a `sundered_isles`
create option and branches the small deltas — nothing built now.

## Testing

- **Model** (`test/character_sheet_test.dart`): `StarforgedSheet` premade defaults;
  momentum max/reset derivation from impacts + re-clamp; range clamps; JSON
  round-trip with legacy/impacts/vows/connections/assets; tolerant parse of junk +
  unknown impact ids; `Character.copyWith` set + `clearStarforged`; null omitted
  from `toJson`.
- **Provider** (`test/character_provider_test.dart`): `addStarforged()` prepends a
  premade Starforged character.
- **Widget** (`test/character_sheet_ui_test.dart`): open a Starforged character →
  bespoke sheet; meter/momentum steppers persist; Burn → reset; impact toggle lowers
  max + re-clamps; legacy-track steppers persist; vow + connection add/mark; asset
  pick + ability toggle (override `rulesetDataProvider('starforged')` with a fixture,
  **never** rootBundle); three-way create flow makes a premade Starforged character;
  a Classic character still shows `IronswornSheetView`; generic still shows generic.
  Refactor keeps all existing slice-A widget tests green (same keys).
- **Real data** (`test/ruleset_assets_test.dart`): extend to assert the shipped
  `ruleset_starforged.json` parses into 87 well-formed asset defs across its 6
  categories.
- **Gate:** `flutter analyze` clean, `flutter test` green.

## Risks / open points

- **Shared-widget extraction churns `ironsworn_sheet.dart`** (slice A). Mitigated by
  doing it as a pure refactor first (keys + behavior preserved, tests green) before
  adding `StarforgedSheet`.
- **Asset Markdown** (move links in ability text) still rendered as "Ability N"
  toggles this phase, same as slice A.
- **Mutually-exclusive ruleset toggle:** creating a Starforged character flips the
  active base ruleset to `starforged`. Existing Classic sheets are unaffected
  because each sheet pins its own asset ruleset (the correctness fix above); only
  the Moves/oracles tool follows the toggle, which is expected.
