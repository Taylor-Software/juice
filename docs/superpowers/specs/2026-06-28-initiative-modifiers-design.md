# Initiative Modifiers (Tier-2 combat depth)

**Date:** 2026-06-28
**Status:** Design approved (batch consent — "do them all"), pending plan
**Part of:** GM-tool epic, Tier-2. One of four remaining Tier-2 items (init modifiers → pacing timers → run-screen polish → bestiary library), each its own spec/PR.

## Summary

Give each combatant a per-combatant **initiative modifier** so "Roll all init"
rolls `d20 + mod` and ties break by the higher modifier. Edited by tapping the
initiative avatar on the Encounter row. Facts-only; no system rules asserted.

## Decisions

- **Storage:** `Combatant.initMod` (int, default 0), alongside the existing
  `initiative`. Persists in the existing `juice.encounter.v1` combatant JSON.
- **Roll:** `rollInitiativeForAll` rolls `d20 + initMod` for combatants whose
  `initiative <= 0` (unset); typed initiatives are preserved. Sort descending by
  final initiative; **tie-break by `initMod` descending** (higher mod acts first).
- **Edit:** tapping the Encounter row's leading initiative `CircleAvatar` opens
  a small `_InitDialog` (initiative value + mod) → `updateCombatant`. Covers both
  ad-hoc and linked combatants (initiative/mod live on the combatant, not the
  sheet).
- **Display:** when `initMod != 0`, the Encounter row shows a compact `init +N` /
  `init -N` marker in its subtitle.
- Run-screen: inherits the mod-aware `rollInitiativeForAll` (no run-screen UI
  change in this slice).

## Model (`lib/engine/models.dart`)

`Combatant` gains `final int initMod;` (default 0):
- constructor param `this.initMod = 0`;
- `copyWith({int? initMod})` → `initMod: initMod ?? this.initMod`;
- `toJson`: `if (initMod != 0) 'initMod': initMod`;
- `fromJson`: `initMod: (j['initMod'] as int?) ?? 0` (legacy-tolerant).

## Roll (`lib/state/providers.dart`)

`rollInitiativeForAll` updated:
```dart
final rolled = [
  for (final c in s.combatants)
    c.initiative <= 0 ? c.copyWith(initiative: d.dN(20) + c.initMod) : c,
]..sort((a, b) {
    final byInit = b.initiative.compareTo(a.initiative);
    return byInit != 0 ? byInit : b.initMod.compareTo(a.initMod);
  });
```

## UI (`lib/features/encounter_screen.dart`)

- Wrap the leading `CircleAvatar` (currently `Text('${c.initiative}')`) in an
  `InkWell`/`GestureDetector` (key `enc-init-${c.id}`) → `_editInit(context, ref, c)`.
- `_editInit` → `showDialog<({int initiative, int mod})>` (`_InitDialog`,
  StatefulWidget): two int `TextField`s (`init-dialog-value`, `init-dialog-mod`),
  Save (`init-dialog-save`) → `updateCombatant(c.copyWith(initiative: v, initMod: m))`.
- In the row subtitle, when `c.initMod != 0`, render a small
  `Text('init ${fmtSigned(c.initMod)}')` (reuse `fmtSigned` from sheet_widgets,
  or inline). Keyed `enc-initmod-${c.id}` for testing.

## Testing

- Model: `Combatant.initMod` round-trips; `toJson` omits 0; copyWith sets it;
  legacy JSON (no key) → 0.
- `rollInitiativeForAll`: an unset combatant with `initMod` 3 gets `d20+3`
  (deterministic `Dice(Random(seed))`); two combatants tying on final initiative
  sort with the higher `initMod` first.
- Encounter widget: tap `enc-init-<id>`, set value + mod, save → persisted;
  `enc-initmod-<id>` shows when mod nonzero, absent when 0.

## Out of scope

- Auto-deriving mod from a linked sheet's DEX (system-specific; the GM types it).
- Run-screen init-mod display/edit (roll-all already honors it).
- Initiative re-roll-all-including-typed (kept: only unset are rolled).
