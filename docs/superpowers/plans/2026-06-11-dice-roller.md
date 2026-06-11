# Dice Roller (Redesign Phase 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A robust dice-notation roller (NdX, d%, dF, modifiers, multi-group, keep/drop, adv/dis) as a launcher tool with per-die breakdown, quick chips, session history, and add-to-journal.

**Architecture:** A pure-Dart notation engine in `lib/engine/dice_notation.dart` — hand-written tokenizer + recursive-descent parser producing a term list, evaluated against the existing `Dice` primitive (injectable for tests; `Dice.dN`/`fate` are virtual, so a scripted fake works by overriding). UI is a new `DiceRollerScreen` registered under a new 'Dice' launcher group; tool state (history, field) survives close via the existing keep-alive ToolHost. No new packages.

**Tech Stack:** Flutter + flutter_riverpod (existing rails). Spec: `docs/superpowers/specs/2026-06-11-journal-redesign-design.md` (Phase 3). Baseline: 98 tests green; `flutter analyze --no-fatal-infos` = exactly 1 pre-existing info (models.dart dangling doc comment). `Oracle.dice` is public (`lib/engine/oracle.dart:36`).

---

### Task 1: Notation engine

**Files:**
- Create: `lib/engine/dice_notation.dart`
- Test: `test/dice_notation_test.dart`

**Grammar (case-insensitive, whitespace allowed between tokens):**

```
expr   := sign? term (('+'|'-') term)*
term   := dice | INT
dice   := INT? 'd' (INT | '%' | 'f') suffix?
suffix := ('kh'|'kl'|'dh'|'dl') INT | 'adv' | 'dis'
```

Rules: count default 1, max 100; sides 2..1000 (`d%` = 100, `df` = fate dice); keep/drop count 1..count-? (`khN`/`klN` keep N of count, N in 1..count; `dhN`/`dlN` drop N, N in 1..count-1); `adv`/`dis` only valid when no explicit count or count==1, desugars to 2 dice kh1/kl1; keep/drop not combined with adv/dis; a leading '-' negates the first term; plain INT terms are flat modifiers. Errors throw `FormatException` with a position-anchored message, e.g. `Expected die size at position 3` — position = 0-based index into the input string.

**API (binding):**

```dart
/// One die's outcome inside a group.
class RolledDie {
  const RolledDie({required this.value, required this.kept, required this.display});
  final int value;       // dF: -1/0/+1
  final bool kept;
  final String display;  // '4'; dF: '+', '−', '0'
}

/// One evaluated term: a dice group or a flat modifier.
class RolledGroup {
  const RolledGroup({
    required this.label,     // normalized, e.g. '4d6kh3', 'd%', '+3', '-2'
    required this.sign,      // +1 | -1 (sign applied in the sum)
    required this.dice,      // empty for modifiers
    required this.subtotal,  // unsigned group value (kept dice summed; or modifier magnitude)
  });
  final String label;
  final int sign;
  final List<RolledDie> dice;
  final int subtotal;
}

class DiceRollResult {
  const DiceRollResult({required this.expression, required this.total, required this.groups});
  final String expression; // normalized form, e.g. '2d6+1d8+3'
  final int total;
  final List<RolledGroup> groups;

  /// Plain-text rendering for the journal:
  /// '2d6+1d8+3 = 14\n2d6: 4, 5 (9)\n1d8: 2 (2)\n+3'
  /// Dropped dice render struck as '[4]'.
  String get asText;
}

/// Parse only (validation); throws FormatException on bad input.
DiceExpression parseDice(String input);

class DiceExpression {
  final List<...> terms;       // internal term representation
  String get normalized;       // canonical text, adv/dis desugared
  DiceRollResult roll(Dice dice);
}
```

- [ ] **Step 1: Failing tests** (`test/dice_notation_test.dart`). Include AT LEAST:

```dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/dice_notation.dart';

/// Scripted dice: dN/fate pop from a fixed list.
class FakeDice extends Dice {
  FakeDice(this._values);
  final List<int> _values;
  int _i = 0;
  @override
  int dN(int n) => _values[_i++];
  @override
  int fate() => _values[_i++];
}

void main() {
  group('parser accepts', () {
    for (final input in [
      'd20', '3d6', '2d6+1d8+3', '4d6kh3', '10d10kl4', '4d6dh1', '4d6dl1',
      'd%', 'dF', '4df', 'd20adv', 'd20dis', '1d20adv',
      '2d6-1', '-d6+10', ' 2D6 + 3 ', '100d1000',
    ]) {
      test(input, () => expect(() => parseDice(input), returnsNormally));
    }
  });

  group('parser rejects with position', () {
    // Binding rule: syntax errors anchor where the expected token should
    // start; semantic errors (count/sides/keep bounds, adv-with-count)
    // anchor at the START of the offending token.
    final cases = {
      '': 0, 'd': 1, '2d': 2, 'xd6': 0, '2d6++3': 4, 'd6kh': 4,
      '0d6': 0, '101d6': 0, 'd1': 1, 'd1001': 1,
      'd6kh2': 2, // keep > count; suffix starts at 2
      '4d6kh0': 3, '4d6dh4': 3, '2d20adv': 4, 'd6foo': 2, '2d6 3': 4,
    };
    cases.forEach((input, pos) {
      test("'$input'", () {
        expect(
          () => parseDice(input),
          throwsA(isA<FormatException>().having(
              (e) => e.message, 'message', contains('position $pos'))),
        );
      });
    });
  });

  group('evaluation', () {
    test('multi-group sum with modifier and dF', () {
      // 2d6: 4,5; 1d8: 2; dF: +1  => 4+5+2+1+3 = 15
      final r = parseDice('2d6+1d8+dF+3').roll(FakeDice([4, 5, 2, 1]));
      expect(r.total, 15);
      expect(r.groups.length, 4);
      expect(r.groups[0].dice.map((d) => d.value), [4, 5]);
      expect(r.groups[3].label, '+3');
    });

    test('kh keeps highest, marks dropped', () {
      final r = parseDice('4d6kh3').roll(FakeDice([1, 4, 6, 3]));
      expect(r.total, 13); // 4+6+3
      final kept = r.groups.single.dice.where((d) => d.kept).map((d) => d.value);
      expect(kept, containsAll([4, 6, 3]));
      expect(r.groups.single.dice.where((d) => !d.kept).single.value, 1);
    });

    test('kh1 over 2d2: enumerated max', () {
      for (final pair in [[1, 1], [1, 2], [2, 1], [2, 2]]) {
        final r = parseDice('2d2kh1').roll(FakeDice(pair));
        expect(r.total, pair.reduce((a, b) => a > b ? a : b));
      }
    });

    test('kl/dh/dl semantics', () {
      expect(parseDice('2d2kl1').roll(FakeDice([1, 2])).total, 1);
      // dh1 drops the highest (5): 2 + 3 = 5.
      expect(parseDice('3d6dh1').roll(FakeDice([2, 5, 3])).total, 5);
      // dl1 drops the lowest (2): 5 + 3 = 8.
      expect(parseDice('3d6dl1').roll(FakeDice([2, 5, 3])).total, 8);
    });

    test('adv/dis desugar', () {
      expect(parseDice('d20adv').normalized, '2d20kh1');
      expect(parseDice('d20adv').roll(FakeDice([7, 15])).total, 15);
      expect(parseDice('d20dis').roll(FakeDice([7, 15])).total, 7);
    });

    test('negative groups subtract', () {
      final r = parseDice('d20-2d4').roll(FakeDice([18, 1, 2]));
      expect(r.total, 15);
      expect(r.groups[1].sign, -1);
    });

    test('asText journal rendering', () {
      final r = parseDice('4d6kh3+2').roll(FakeDice([1, 4, 6, 3]));
      expect(r.asText, contains('4d6kh3+2 = 15'));
      expect(r.asText, contains('[1]')); // dropped die bracketed
    });

    test('d% rolls 1..100 and dF dice sum in range', () {
      final rng = Dice(Random(7));
      for (var i = 0; i < 2000; i++) {
        expect(parseDice('d%').roll(rng).total, inInclusiveRange(1, 100));
        expect(parseDice('4dF').roll(rng).total, inInclusiveRange(-4, 4));
      }
    });

    test('3d6 distribution sanity (mean ~10.5)', () {
      final rng = Dice(Random(11));
      var sum = 0;
      const n = 20000;
      for (var i = 0; i < n; i++) {
        sum += parseDice('3d6').roll(rng).total;
      }
      expect(sum / n, closeTo(10.5, 0.1));
    });
  });
}
```

- [ ] **Step 2: Run** `flutter test test/dice_notation_test.dart` — FAIL (file missing).
- [ ] **Step 3: Implement** `lib/engine/dice_notation.dart`. Structure: private `_Token`izer (scan once, record each token's input position), `_Parser` (recursive descent over tokens; every throw includes the offending token's position), term types (`_DiceTerm{count, sides, isFate, keep: _Keep?{mode, n}, sign}` and `_ModTerm{value, sign}`), `DiceExpression.normalized` (canonical lowercase, no spaces, adv/dis already desugared to `2dXkh1`/`2dXkl1`), `roll(Dice)` evaluating in order: roll count dice (`dice.dN(sides)` or `dice.fate()`), apply keep/drop by sorting indices by value (stable: when values tie, keep earlier dice), subtotal = kept sum (fate dice sum may be negative — fine), total = Σ sign × subtotal. Display: dF die → '+', '−' (U+2212), '0'.
- [ ] **Step 4: Run** the file's tests, then full `flutter test` — green; analyze — no new infos.
- [ ] **Step 5: Commit** `git add -A lib test && git commit -m "feat: dice notation engine (parser + evaluator, position-anchored errors)"`

### Task 2: Dice roller screen

**Files:**
- Create: `lib/features/dice_roller_screen.dart`
- Test: `test/dice_roller_screen_test.dart`

- [ ] **Step 1: Failing tests:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/features/dice_roller_screen.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(body: DiceRollerScreen(dice: Dice())))));
    await tester.pumpAndSettle();
  }

  testWidgets('chips build expressions; repeat tap increments', (tester) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'd6'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'd6'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'd6'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '2d6'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'd20'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '2d6+d20'), findsOneWidget);
  });

  testWidgets('invalid input shows error and disables Roll', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('dice-input')), '2d6++3');
    await tester.pump();
    expect(find.textContaining('position'), findsOneWidget);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Roll'));
    expect(button.onPressed, isNull);
  });

  testWidgets('roll renders breakdown and total; history rerolls; journal add',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('dice-input')), '2d6+3');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Roll'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dice-total')), findsOneWidget);
    expect(find.textContaining('2d6'), findsWidgets);
    // History entry exists; tapping rerolls (a new total widget remains).
    await tester.tap(find.byKey(const Key('dice-history-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dice-total')), findsOneWidget);
    // Add to journal.
    await tester.tap(find.byTooltip('Add to journal'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(DiceRollerScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.single.title, 'Dice Roll');
    expect(entries.single.body, contains('= '));
  });
}
```

- [ ] **Step 2: Run** — FAIL (missing file).
- [ ] **Step 3: Implement** `DiceRollerScreen extends ConsumerStatefulWidget` taking `required Dice dice`. Layout (Column in padding):
  - TextField key `Key('dice-input')`, controller, `textInputAction: TextInputAction.done`, `onSubmitted` rolls when valid; live validation in `onChanged`: try `parseDice`; on FormatException store message → `decoration.errorText` (null when valid or empty).
  - Quick chips Wrap: d4 d6 d8 d10 d12 d20 d100 dF as ActionChips. Tap logic: let `t = text.trim()`; if `t` is empty → set to `dX`; else if the LAST '+'-separated segment matches `^(\d*)d(X)$` for the same X (case-insensitive, no suffix) → increment that segment's count (absent count = 1 → 2); else append `+dX`. ('d100' chip inserts `d100`, 'dF' inserts `dF`.)
  - Roll button: `FilledButton` labeled 'Roll', onPressed null when invalid/empty; on roll: `parseDice(text).roll(widget.dice)` → set `_last`, insert at history front (cap 20).
  - Result card: normalized expression, big total (key `Key('dice-total')`), per-group rows — group label + dice as inline spans: kept dice normal weight, dropped dice with `TextDecoration.lineThrough` + muted color; modifiers as text. IconButton tooltip 'Add to journal' → `ref.read(journalProvider.notifier).add('Dice Roll', _last!.asText)` + SnackBar 'Added to journal'.
  - History: 'History' label + ListView (shrinkWrap inside the scrollable Column — or Expanded ListView; screen lives in the tool panel, so prefer `ListView` as the root scrollable with all sections as children). Each entry `Key('dice-history-$i')`, shows `expression = total`, tap → re-roll that expression (new result + new history entry at front).
  - Heading: 'Dice Roller', subtitle one-liner: 'NdX, d%, dF, kh/kl/dh/dl, adv/dis — e.g. 4d6kh3+2'.
- [ ] **Step 4: Full** `flutter test` green; analyze — no new infos.
- [ ] **Step 5: Commit** `git add -A lib test && git commit -m "feat: dice roller screen (chips, live validation, breakdown, history, journal)"`

### Task 3: Registry + group wiring (controller may run inline)

**Files:**
- Modify: `lib/shared/tool_registry.dart` (+ 'Dice' in toolGroups after 'Ask the Oracle'; new entry)
- Modify: `test/tool_registry_test.dart` (counts 10→11 and 11→12; add 'dice' to core ids)

- [ ] Registry entry:

```dart
ToolDef(
  id: 'dice',
  label: 'Dice Roller',
  icon: Icons.casino_outlined,
  group: 'Dice',
  builder: (o) => DiceRollerScreen(dice: o!.dice),
),
```

- [ ] `flutter test` green (home_shell/tool_host tests unaffected — fake registries don't use 'Dice').
- [ ] Commit `git commit -am "feat: dice roller in the launcher (new Dice group)"`

### Task 4: Verify, docs, ship (controller-run)

- [ ] Gates: analyze (1 baseline info), `flutter test`, `python3 build_oracle.py`, `flutter build web`.
- [ ] Browser verify: Tools → Dice group → Dice Roller; chip taps build `2d6+d20`; Roll → breakdown + total render; Add to journal → entry in home journal; close/reopen → history retained (keep-alive). Text-field typing headless-impossible — chips cover expression building; typing covered by widget tests; disclose in PR.
- [ ] README: feature paragraph gains dice roller sentence (notation list).
- [ ] ROADMAP: phase 3 → Done; phase 4 → next.
- [ ] PR `feat/dice-roller`, CI green BEFORE merge, squash-merge, deploy verify.
