# Sundered Isles sheet support — slice A continued

**Date:** 2026-06-17
**Status:** Design approved, pending spec review
**Builds on:** `docs/superpowers/specs/2026-06-17-starforged-character-sheet-design.md` (Starforged sheet, shipped in PR #70)

## Context

Sundered Isles is "powered by Starforged." Verified against the vendored
datasworn (`data/datasworn/sundered_isles.json`): SI **inherits Starforged's
rules wholesale** — identical 5 stats (edge/heart/iron/shadow/wits), identical 3
condition meters (health/spirit/supply, 0..5), identical momentum, the **same 10
impacts** (misfortunes/vehicle_troubles/burdens/lasting_effects), and the **same
3 legacy tracks** (quests/bonds/discoveries). The only character-sheet-relevant
difference is the **asset set**: SI ships 60 assets (a curated variant across the
same 6 categories) as `assets/ruleset_sundered_isles.json`, already emitted by
`build_datasworn.py`.

Therefore SI needs **no new sheet, no new model class, no new impacts/tracks**.
The entire deliverable is: let a character created as "Sundered Isles" pull
assets from `ruleset_sundered_isles.json` instead of `ruleset_starforged.json`,
and label itself accordingly. It reuses `StarforgedSheetView` verbatim otherwise.

## Goal & success criteria

With the `ironsworn` system enabled, a player can create a **Sundered Isles**
character in one tap. It renders via the existing Starforged sheet (stats,
meters, momentum, impacts, legacy tracks, XP, vows, connections), but its asset
picker lists the 60 Sundered Isles assets and the header reads "Sundered Isles".

Done when:

1. The create chooser offers a fourth option, **Sundered Isles**, which creates a
   `Character` whose `starforged` is a premade `StarforgedSheet` with
   `assetRuleset == 'sundered_isles'`, enables the `sundered_isles` ruleset, and
   opens the sheet.
2. That sheet's asset picker reads `ruleset_sundered_isles.json` (60 assets); a
   plain Starforged character's picker still reads `ruleset_starforged.json` (87).
3. The header label reads "Sundered Isles" for an SI character, "Starforged"
   otherwise.
4. `assetRuleset` round-trips in JSON, defaults to `'starforged'` for existing
   Starforged characters (legacy-safe), and is validated to
   `{starforged, sundered_isles}`. No campaign-schema bump.
5. `flutter analyze` + `flutter test` clean.

## Non-goals

- Any new sheet/model class (`SunderedIslesSheet`, `Character.sunderedIsles`).
- Impact/meter/track changes (SI has none vs Starforged).
- Build-script changes (SI assets already emitted).
- A Sundered Isles–specific asset *interactivity* beyond what Starforged already
  has (still: pick + ability toggles; companion/vehicle meters deferred).

## Architecture

### Data model — `lib/engine/models.dart`

Add one field to `StarforgedSheet`:

```
String assetRuleset   // 'starforged' (default) | 'sundered_isles'
```

- Constructor default `'starforged'` (existing characters + `maybeFromJson` of
  legacy JSON resolve to it, so nothing changes for current Starforged sheets).
- `maybeFromJson` reads it but coerces any value outside
  `{starforged, sundered_isles}` back to `'starforged'`.
- `toJson` writes it only when `!= 'starforged'` (byte-stable for existing
  Starforged characters — mirrors how `starred`/`emulation` are conditionally
  written).
- `copyWith` passes it through (value-or-this).
- `premade({String assetRuleset = 'starforged'})` takes it as a named arg.
- A getter `bool get isSundered => assetRuleset == 'sundered_isles';` for the UI.

All other `StarforgedSheet` fields/logic are unchanged.

### Provider — `lib/state/providers.dart`

`CharacterNotifier.addStarforged` gains an optional named arg:

```
Future<String> addStarforged({String assetRuleset = 'starforged'}) // name 'New Starforged character' / 'New Sundered Isles character'
```

It prepends a `Character` with `StarforgedSheet.premade(assetRuleset: …)`; the
default-arg call from the existing Starforged path is unchanged.

### UI — `lib/features/starforged_sheet.dart` + `lib/features/tracker_screen.dart`

- `StarforgedSheetView`:
  - Asset picker uses `_s.assetRuleset` instead of the hardcoded `'starforged'`
    (`addAssetDialog(context, ref, _s.assetRuleset)`).
  - Header label: `_s.isSundered ? 'Sundered Isles' : 'Starforged'`.
  - Everything else unchanged (it already renders impacts/legacy/vows/connections
    from the shared widgets).
- `tracker_screen.dart` `_onAdd` chooser: add a fourth button keyed
  `new-sundered`. Its handler calls a new `_newSundered()` that ensures the
  `sundered_isles` ruleset is on (`rulesetsProvider.setRuleset('sundered_isles',
  true)` — the family rules pull in base `starforged`), then
  `addStarforged(assetRuleset: 'sundered_isles')`, then opens the sheet.

The render branch is unchanged: `c.starforged != null → StarforgedSheetView`
already covers SI characters (they are Starforged sheets with a different asset
ruleset).

## Testing

- **Model** (`test/character_sheet_test.dart`): `assetRuleset` defaults to
  `'starforged'`; `premade(assetRuleset:'sundered_isles')` sets it; round-trips;
  omitted from `toJson` when default; legacy JSON (no key) → `'starforged'`;
  junk/unknown value → `'starforged'`; `isSundered` getter.
- **Widget** (`test/character_sheet_ui_test.dart`): create-flow `new-sundered`
  makes a premade SI character (`assetRuleset == 'sundered_isles'`) and the sheet
  shows the "Sundered Isles" label; the SI asset picker lists SI fixture assets
  (override `rulesetDataProvider('sundered_isles')`); a plain Starforged character
  still shows "Starforged" and (by the existing Task-7 test) reads `'starforged'`
  assets. No rootBundle.
- **Real data** (`test/ruleset_assets_test.dart`): assert the shipped
  `ruleset_sundered_isles.json` parses into 60 well-formed asset defs.
- **Gate:** `flutter analyze` clean, `flutter test` green.

## Risks / open points

- **Asset-ruleset id correctness:** SI assets use the Datasworn 0.1.0 id form
  (`asset:sundered_isles/...`). The picker keys `pick-asset-<id>` and the stored
  `AssetState.assetId` handle arbitrary id strings (slice A verified), so no
  special handling is needed.
- **Chooser growth:** the create dialog now has four actions (Generic / Ironsworn
  / Starforged / Sundered Isles). Acceptable in an `AlertDialog` actions row; if
  it ever overflows on narrow widths, switch to a `SimpleDialog` list (not needed
  now).
