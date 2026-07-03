# Rollable stat-block attacks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the GM tap an attacker's stat-block attack to auto-fill the attack + damage dice in the combat-resolve dialog.

**Architecture:** A pure `attackDiceFromDetail` helper (in `lib/engine/combat.dart`) extracts dice from a freeform `Attack.detail` via the existing `scanDice`; `_AttackDialog` renders one tappable `ActionChip` per attack that fills the dice fields on tap. No model or persistence change.

**Tech Stack:** Dart/Flutter, Riverpod, `package:flutter_test`. Run tests with `export PATH="$HOME/development/flutter/bin:$PATH"; flutter test`.

---

### Task 1: `attackDiceFromDetail` pure helper

**Files:**
- Modify: `lib/engine/combat.dart` (add function + import)
- Test: `test/combat_test.dart` (append a group)

- [ ] **Step 1: Write the failing tests** — append to `test/combat_test.dart` inside `main()`:

```dart
  group('attackDiceFromDetail', () {
    test('d20 token is the attack, the other die is damage', () {
      final r = attackDiceFromDetail('Longbow 1d20+5, 1d8+3');
      expect(r.attack, '1d20+5');
      expect(r.damage, '1d8+3');
    });
    test('a bare +N modifier is not a die; only damage is filled', () {
      final r = attackDiceFromDetail('Scimitar +4, 1d6+2 slashing');
      expect(r.attack, isNull);
      expect(r.damage, '1d6+2');
    });
    test('damage-only attack fills damage, leaves attack null', () {
      final r = attackDiceFromDetail('Claw 2d4');
      expect(r.attack, isNull);
      expect(r.damage, '2d4');
    });
    test('attack-only detail fills attack, leaves damage null', () {
      final r = attackDiceFromDetail('1d20+7 to hit');
      expect(r.attack, '1d20+7');
      expect(r.damage, isNull);
    });
    test('no dice yields two nulls', () {
      expect(attackDiceFromDetail('grapple, no damage').attack, isNull);
      expect(attackDiceFromDetail('').damage, isNull);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `export PATH="$HOME/development/flutter/bin:$PATH"; flutter test test/combat_test.dart`
Expected: FAIL — `attackDiceFromDetail` is undefined.

- [ ] **Step 3: Implement** — in `lib/engine/combat.dart`, add the import at the top (below the header comment, before/near existing content) and the function at the end:

```dart
import 'dice_scan.dart';
```

```dart
/// Best-effort extraction of the attack and damage dice from a freeform
/// stat-block attack [detail]. Uses [scanDice], which returns only validated
/// dice notations (a bare "+4" is not a die and is ignored). The first token
/// containing "d20" is the attack roll; the first remaining token is the
/// damage. Either may be null when the detail has no matching token.
({String? attack, String? damage}) attackDiceFromDetail(String detail) {
  final toks = scanDice(detail).map((s) => s.notation).toList();
  String? attack;
  for (final t in toks) {
    if (t.toLowerCase().contains('d20')) {
      attack = t;
      break;
    }
  }
  String? damage;
  for (final t in toks) {
    if (t != attack) {
      damage = t;
      break;
    }
  }
  return (attack: attack, damage: damage);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `export PATH="$HOME/development/flutter/bin:$PATH"; flutter test test/combat_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/combat.dart test/combat_test.dart
git commit -m "feat(combat): attackDiceFromDetail — parse attack/damage dice from a stat-block attack"
```

---

### Task 2: Tappable attack chips in `_AttackDialog`

**Files:**
- Modify: `lib/features/encounter_screen.dart` (`_AttackDialogState`: add `_pickAttack`, swap the caption for chips)

- [ ] **Step 1: Add the `_pickAttack` handler** — inside `_AttackDialogState`, near `_rollAttack`:

```dart
  /// Fills the dice fields from a stat-block attack's freeform detail and
  /// clears any prior roll so the next Roll uses the new dice.
  void _pickAttack(Attack a) {
    final d = attackDiceFromDetail(a.detail);
    setState(() {
      if (d.attack != null) _atk.text = d.attack!;
      if (d.damage != null) _dmg.text = d.damage!;
      _attackTotal = null;
      _hit = null;
    });
  }
```

- [ ] **Step 2: Replace the read-only caption with chips** — find this block in `_AttackDialogState.build`:

```dart
            if (attacks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Your attacks: ${attacks.map((a) => a.detail.isEmpty ? a.name : '${a.name} — ${a.detail}').join(' · ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
```

Replace it with:

```dart
            if (attacks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final (i, a) in attacks.indexed)
                      ActionChip(
                        key: Key('attack-pick-$i'),
                        label: Text(a.name.isEmpty ? a.detail : a.name),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        onPressed: () => _pickAttack(a),
                      ),
                  ],
                ),
              ),
```

- [ ] **Step 3: Analyze**

Run: `export PATH="$HOME/development/flutter/bin:$PATH"; flutter analyze lib/features/encounter_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/encounter_screen.dart
git commit -m "feat(encounter): tappable stat-block attack chips prefill the resolve dialog dice"
```

---

### Task 3: Widget test — tapping a chip fills the fields

**Files:**
- Test: `test/encounter_attack_test.dart` (append a test)

- [ ] **Step 1: Write the test** — append inside `main()`:

```dart
  testWidgets('tapping a stat-block attack chip fills the dice fields',
      (t) async {
    await pump(
        t,
        _enc([
          _c('g', 'Goblin', 15, attacks: [
            {'name': 'Bite', 'detail': '1d20+4, 2d6+2'}
          ]),
          _c('m', 'Mira', 10,
              ac: 1, track: {'label': 'HP', 'current': 10, 'max': 10}),
        ]));

    await t.tap(find.byKey(const Key('enc-attack-g')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('attack-pick-0')));
    await t.pumpAndSettle();

    expect(
        t.widget<TextField>(find.byKey(const Key('attack-roll'))).controller!.text,
        '1d20+4');
    expect(
        t.widget<TextField>(find.byKey(const Key('attack-damage'))).controller!.text,
        '2d6+2');

    // The prefilled dice still resolve to a hit + damage.
    await t.tap(find.byKey(const Key('attack-roll-go')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('attack-apply')));
    await t.pumpAndSettle();
    final mira = (await c.read(encounterProvider.future))
        .combatants
        .firstWhere((x) => x.id == 'm');
    expect(mira.track!.current, lessThan(10));
  });
```

Note: this reuses the file's existing `pump`, `_enc`, `_c` helpers. `pump` returns the `ProviderContainer` — bind it (`final c = await pump(...)`) since the assertion reads `encounterProvider`. Adjust the first line to `final c = await pump(...)`.

- [ ] **Step 2: Run to verify it passes**

Run: `export PATH="$HOME/development/flutter/bin:$PATH"; flutter test test/encounter_attack_test.dart`
Expected: PASS (all tests, including the new one).

- [ ] **Step 3: Commit**

```bash
git add test/encounter_attack_test.dart
git commit -m "test(encounter): attack chip prefills the resolve dialog dice"
```

---

### Task 4: Full verification

- [ ] **Step 1: Analyze + full suite**

Run: `export PATH="$HOME/development/flutter/bin:$PATH"; flutter analyze && flutter test`
Expected: `No issues found!` and `All tests passed!`

- [ ] **Step 2: Update CLAUDE.md** — in the Combat resolve bullet, change the deferred note `rollable stat-block attacks (prefill dice from Attack.detail)` to reflect it shipped (mention `attack-pick-<i>` chips + `attackDiceFromDetail`). Commit.
