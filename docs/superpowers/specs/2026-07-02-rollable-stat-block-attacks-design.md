# Rollable stat-block attacks — design

**Date:** 2026-07-02
**Status:** approved
**Follow-up to:** combat resolve (#247)

## Problem

The Encounter combat-resolve dialog (`_AttackDialog` in
`lib/features/encounter_screen.dart`, shipped in #247) makes the GM type the
attack and damage dice by hand into the `attack-roll` (default `1d20`) and
`attack-damage` (default `1d6`) fields. The attacker's stat-block attacks
(`Combatant.statBlock.attacks` — each an `Attack {name, detail}`, `detail`
freeform e.g. `"Scimitar +4, 1d6+2 slashing"`) already appear in the dialog, but
only as a read-only reference caption. The dice have to be re-typed from that
text on every attack.

## Goal

Let the GM tap one of the attacker's stat-block attacks to auto-fill the attack
and damage dice fields from its freeform `detail`, then roll as usual. No new
model, no stored parsed stats — a best-effort convenience over the existing
resolve flow.

## Non-goals

- No auto-roll: tapping fills the fields; the GM still taps **Roll** (chosen
  interaction: "tappable chips, fill only").
- No synthesis of a to-hit roll from a bare `+N` modifier (e.g. turning `+4`
  into `1d20+4`) — bare modifiers aren't dice and are left out; the `1d20`
  attack default stands and the GM adds their modifier if they want.
- No change to `Attack`/`StatBlock`/persistence.

## Design

### Pure helper (`lib/engine/combat.dart`)

```dart
/// Best-effort extraction of the attack and damage dice from a freeform
/// stat-block attack detail. Uses [scanDice] (dice_scan.dart), which returns
/// only validated dice notations (a bare "+4" is not a die and is ignored).
/// The first token containing "d20" is the attack roll; the first remaining
/// token is the damage. Either may be null when the detail has no such token.
({String? attack, String? damage}) attackDiceFromDetail(String detail)
```

Behaviour (order-independent for the attack — the `d20` heuristic beats strict
positional parsing because damage-only attacks read `"Claw 2d4"` with the die
first):

| `detail`                          | attack   | damage   |
|-----------------------------------|----------|----------|
| `"Scimitar +4, 1d6+2 slashing"`   | `null`   | `1d6+2`  |
| `"Longbow 1d20+5, 1d8+3"`         | `1d20+5` | `1d8+3`  |
| `"Claw 2d4"`                      | `null`   | `2d4`    |
| `"1d20+7 to hit"`                 | `1d20+7` | `null`   |
| `""` / `"grapple, no damage"`     | `null`   | `null`   |

Implementation: `final toks = scanDice(detail).map((s) => s.notation).toList();`
then pick the first `toLowerCase().contains('d20')` token as `attack`, and the
first token `!= attack` as `damage` (plain loops; no new dependency).

### UI (`_AttackDialog`)

Replace the read-only "Your attacks: …" caption with a `Wrap` of `ActionChip`s,
one per `widget.attacker.statBlock!.attacks` entry:

- key `attack-pick-<i>`, label = `attack.name` (falls back to the detail when the
  name is blank).
- On tap: `final d = attackDiceFromDetail(a.detail);` set
  `if (d.attack != null) _atk.text = d.attack!;` and
  `if (d.damage != null) _dmg.text = d.damage!;` — a field is only overwritten
  when a token was found, so a damage-only attack keeps the `1d20` attack
  default. Then reset the rolled state (`_attackTotal = null; _hit = null;`) via
  `setState` so a prior roll doesn't linger against the new dice. If the detail
  yields neither token the tap is a no-op (the fields and state are unchanged).

Shown only when `attacks.isNotEmpty` (unchanged from today). The chips sit in the
dialog's scrolling content `Column`, above the attack-roll `Row`.

## Testing

- **Unit** (`test/combat_test.dart`): `attackDiceFromDetail` across the table
  above (d20+other, damage-only, attack-only, none, empty).
- **Widget** (`test/encounter_attack_test.dart`, under the real `AppTheme`): seed
  an attacker whose stat block has an attack with `detail` `"Bite 1d20+4, 2d6+2"`;
  open the dialog, tap `attack-pick-0`, assert the `attack-roll` field reads
  `1d20+4` and `attack-damage` reads `2d6+2`; then Roll → resolve as before.

## Files touched

- `lib/engine/combat.dart` — add `attackDiceFromDetail` (+ import `dice_scan.dart`).
- `lib/features/encounter_screen.dart` — swap the attacks caption for tappable
  chips in `_AttackDialog`.
- `test/combat_test.dart`, `test/encounter_attack_test.dart` — coverage.
