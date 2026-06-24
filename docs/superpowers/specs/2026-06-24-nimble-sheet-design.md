# Nimble character sheet (facts-only P1)

**Date:** 2026-06-24
**Status:** Design — approved

## Problem

Add a pre-made **Nimble** character sheet — the next bespoke sheet after the
Ironsworn family, D&D 5e, and Shadowdark. Nimble (Nimble Co., 5e-compatible) is
a streamlined fantasy TTRPG with 4 stats, a Wounds dying-track, and slot
inventory.

## Licensing

Nimble has an **open, app-friendly 3rd-party license** (you may reference any
Nimble text in compatible products, including apps, with attribution — it builds
on WotC SRD 5.1 / CC-BY 4.0). So unlike Shadowdark, richer use is *permitted*.
**P1 still ships facts-only** for consistency with the D&D-P1 / Shadowdark
sheets and fastest delivery: authored, non-copyrightable **mechanic facts only**
(the 4 stat names, the 10 class names), NO rulebook prose, NO attribution
notice, NO content pickers. A **P2** (deferred) may add Nimble class/feature
text + pickers under the Nimble 3rd-Party Creator License + the SRD-5.1/WotC
attribution chain — genuinely open later, unlike Shadowdark.

## Approach: author names, freeform values

Authoritative for P1: the **stat names** (`str/dex/int/wis`) and the **10 class
names**. NOT confidently known: per-class hit dice, the ancestry list, exact
inventory math. So — exactly like Shadowdark-P1 — the sheet authors the certain
facts (class dropdown, stat labels) and leaves the rest **editable** (the player
fills their character's actual numbers). Robust without over-asserting rules.
Note: **Nimble stats are modifiers** (small ± numbers), not 3–18 scores — so the
stat field is a plain signed stepper, NOT the D&D/Shadowdark `abilityBox`
(score→derived-mod).

## Architecture (mirrors the Shadowdark sheet, #75)

### 1. Model + constants — `lib/engine/models.dart`

```dart
const kNimbleStats = <String>['str', 'dex', 'int', 'wis'];
const kNimbleClasses = <String>[
  'The Cheat', 'Commander', 'Hunter', 'Mage', 'Oathsworn',
  'Shadowmancer', 'Shepherd', 'Songweaver', 'Stormshifter', 'Zephyr',
];
```

`class NimbleSheet` (const ctor + `copyWith` + tolerant `maybeFromJson`/`toJson`,
mirroring `ShadowdarkSheet`):
- `Map<String,int> stats` (the 4 stats, default `0` each — modifiers).
- `Map<String,int> saveAdv` (per stat: `1` advantaged / `-1` disadvantaged /
  `0` none; default all `0`).
- `String className` (default `'The Cheat'`), `String ancestry` (freeform '').
- `int level` (1), `int hitDieSize` (default `6`, editable).
- `int maxHp` (1), `int currentHp` (1).
- `int wounds` (0), `int maxWounds` (6) — the dying track.
- `int speed` (6), `int gearSlotsUsed` (0).
- `String talents` (''), `String notes` ('') — freeform.

Derived: `int get slotCap => 10 + (stats['str'] ?? 0);` (Nimble's 10+STR).

### 2. `Character.nimble` — `lib/engine/models.dart`

Add `final NimbleSheet? nimble;` to `Character` (ctor, `copyWith` with a
`clearNimble`), `if (nimble != null) 'nimble': nimble!.toJson()` in `toJson`,
`nimble: NimbleSheet.maybeFromJson(j['nimble'])` in `fromJson`.

### 3. System registration

- `kSystemLabels['nimble'] = 'Nimble'`.
- Add `'nimble'` to `formatSystems`'s order list (near the other sheets) and any
  systems-validation/known-systems list that lists the opt-in sheet systems
  (mirror exactly where `'shadowdark'` appears — `nimble` is NOT in
  `kAllSystems`).
- New-campaign dialog (`home_shell.dart`) + the edit-systems dialog: add a
  `sys-nimble` opt-in toggle (mirror `sys-shadowdark` / the dnd/shadowdark
  add-on toggles).

### 4. System primer — `lib/engine/system_primer.dart`

Add a `nimble` line to `kSystemPrimers` (facts-only flavor + resolution
vocabulary, e.g. *"Nimble: fast, tactical 5e-compatible fantasy. Resolution:
d20 + stat vs DC/armor; advantage/disadvantage; wounds track; slot
inventory."*). Add `nimble` to `resolveSystemPrimer` + `resolveSystem` priority
(place beside shadowdark, e.g. `dnd > shadowdark > nimble > Ironsworn-family`).

### 5. Sheet view — `lib/features/nimble_sheet.dart` (new)

`NimbleSheetView` (ConsumerWidget, mirroring `ShadowdarkSheetView`):
- `nimble-class` class `DropdownButton` (`kNimbleClasses`); `nimble-ancestry`
  freeform `TextField`.
- A row of 4 stat steppers (`nimble-stat-<key>`, signed) — each with an adv/dis
  save toggle (`nimble-save-<key>` cycling +/−/none).
- HP stepper (`nimble-hp`, current/max); **Wounds** stepper (`nimble-wounds`,
  current/max — the signature dying track, like Shadowdark's torch countdown).
- `nimble-level` / `nimble-speed` / `nimble-hitdie` steppers; an inventory
  readout `gearSlotsUsed / slotCap` with a `nimble-slots` stepper.
- Shared `conditionsSection(context, ref, character, 'nimble')`.
- Freeform `nimble-talents` / `nimble-notes` `TextField`s.
- All edits persist via `CharacterNotifier.replace(character.copyWith(nimble:
  _s.copyWith(...)))` (the Shadowdark `_save` pattern).

### 6. Render + creation

- `tracker_screen.dart` sheet selection: add `if (c.nimble != null) return
  NimbleSheetView(character: c);` beside the shadowdark/dnd branches.
- Sheet creation: add a "New Nimble sheet" roster affordance gated on the
  `nimble` system (mirror how a Shadowdark sheet is created), setting
  `Character.nimble = const NimbleSheet()`.

### 7. HP read-through — `lib/engine/models.dart` + `lib/features/encounter_screen.dart`

`Character.withHpDelta` (party-effect + combatant HP) must resolve the `nimble`
pool (its `currentHp`), mirroring the `dnd`/`shadowdark` branches — the #121
lesson (cover sheet pools, not just tracks). The encounter combatant-row
read-through (`encounter_screen.dart` ~122) adds a `nimble` branch.

## Testing

- `NimbleSheet` model round-trip (`toJson`→`maybeFromJson`, tolerant of junk /
  missing keys; defaults applied) + `slotCap` derivation.
- `Character` round-trip carries `nimble`.
- `withHpDelta` adjusts a nimble character's `currentHp`.
- `NimbleSheetView` widget test (pump a `Character` with `nimble`): class
  dropdown changes persist; a stat stepper persists; the HP + Wounds steppers
  persist; rendered under the `nimble` system. (Mirror `character_sheet_ui_test`
  / the Shadowdark sheet tests; override the data providers per the
  rootbundle-hang note.)

## Out of scope (P2, deferred — but ALLOWED by Nimble's license)

- Nimble class-feature / spell / talent **text** + content pickers (needs the
  Nimble 3rd-Party Creator License attribution + the SRD-5.1/WotC chain);
  per-class hit-dice / ancestry authoritative tables; armor/AC automation;
  level-up automation; a Nimble asset ruleset.

## Files touched

| File | Change |
|------|--------|
| `lib/engine/models.dart` | `kNimbleStats`/`kNimbleClasses`, `NimbleSheet`, `Character.nimble`, `withHpDelta` nimble branch, `kSystemLabels`/`formatSystems` |
| `lib/engine/system_primer.dart` | `nimble` primer + `resolveSystemPrimer`/`resolveSystem` |
| `lib/features/nimble_sheet.dart` | NEW — `NimbleSheetView` |
| `lib/features/tracker_screen.dart` | render `NimbleSheetView`; "New Nimble sheet" creation |
| `lib/features/home_shell.dart` | `sys-nimble` opt-in toggle (new-campaign + edit-systems) |
| `lib/features/encounter_screen.dart` | nimble HP read-through |
| tests | `NimbleSheet`/`Character` round-trip, `withHpDelta`, `NimbleSheetView` widget |
