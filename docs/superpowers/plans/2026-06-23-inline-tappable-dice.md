# Inline Tappable Dice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make dice notation (`2d6+3`, `d20`, `4d6kh3`) in rendered journal prose tap-to-roll, logging a rerollable dice entry.

**Architecture:** A pure `scanDice` (regex candidates validated by the existing `parseDice`, which throws on invalid) finds dice tokens in text. `mention_text.dart` turns those tokens into tappable link-styled spans (non-lonelog runs only) via a new `onDiceTap` callback. `journal_screen.dart` wires `onDiceTap` to a `_rollDice` handler that rolls + logs through the existing dice pipeline (`diceRollGenResult` + the `expression` payload that makes entries rerollable).

**Tech Stack:** Dart, Flutter, flutter_riverpod, flutter_test. Reuses `parseDice`/`DiceExpression.roll`/`diceRollGenResult` (`dice_notation.dart`), `MentionText` (`mention_text.dart`), `oracleProvider`/`journalProvider`.

---

## File Structure

- **Create** `lib/engine/dice_scan.dart` — `DiceSpan` + `scanDice(text)`. Pure, no Flutter. Depends only on `dice_notation.dart` (`parseDice`).
- **Modify** `lib/shared/mention_text.dart` — add `onDiceTap` callback; in non-lonelog text runs, split by `scanDice` into tappable dice spans.
- **Modify** `lib/features/journal_screen.dart` — add `_rollDice` handler; pass `onDiceTap: _rollDice` to the entry-body `MentionText`s.
- **Create** `test/dice_scan_test.dart` — pure detection + false-positive tests.
- **Modify** `test/mention_text_test.dart` — dice-span render/tap/lonelog-skip tests.
- **Create** `test/journal_inline_dice_test.dart` — tapping an inline dice token logs a `dice` entry.

---

## Task 1: Pure dice scanner

**Files:**
- Create: `lib/engine/dice_scan.dart`
- Test: `test/dice_scan_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/dice_scan_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice_scan.dart';

void main() {
  List<String> tokens(String s) =>
      scanDice(s).map((d) => d.notation).toList();

  test('finds common dice forms', () {
    expect(tokens('hit for 2d6+3 damage'), ['2d6+3']);
    expect(tokens('roll d20 to notice'), ['d20']);
    expect(tokens('4d6kh3 for stats'), ['4d6kh3']);
    expect(tokens('d20adv on this'), ['d20adv']);
    expect(tokens('roll d% now'), ['d%']);
    expect(tokens('4dF aspects'), ['4dF']);
  });

  test('finds multiple, in order, with correct ranges', () {
    final s = 'I rolled 2d6 and d20.';
    final spans = scanDice(s);
    expect(spans.map((d) => d.notation).toList(), ['2d6', 'd20']);
    // Ranges point at the actual substrings.
    for (final d in spans) {
      expect(s.substring(d.start, d.end), d.notation);
    }
    // Non-overlapping, ascending.
    expect(spans[0].end, lessThanOrEqualTo(spans[1].start));
  });

  test('rejects false positives', () {
    expect(tokens('sword20 is sharp'), isEmpty); // d not at a word boundary
    expect(tokens('just add it'), isEmpty); // "add" has no dice
    expect(tokens('rolled a d1'), isEmpty); // d1 fails parseDice (sides 2-1000)
    expect(tokens('a lone d here'), isEmpty); // bare d, no sides
    expect(tokens('100 gold'), isEmpty); // number, no die
    expect(tokens('the road20 sign'), isEmpty); // d inside a word
  });

  test('blank / no-dice text yields nothing', () {
    expect(scanDice(''), isEmpty);
    expect(scanDice('a plain sentence with no rolls'), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/dice_scan_test.dart`
Expected: FAIL — `dice_scan.dart` / `scanDice` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/engine/dice_scan.dart`:

```dart
import 'dice_notation.dart';

/// A run of text that is valid dice notation, by half-open range
/// [start, end). `notation == text.substring(start, end)`.
class DiceSpan {
  const DiceSpan(this.start, this.end, this.notation);
  final int start; // inclusive
  final int end; // exclusive
  final String notation;
}

// A dice term (optional count, `d`, then sides / `%` / `F`) with an optional
// keep-drop or adv/dis suffix, optional `!` explode, and an optional single
// flat modifier — anchored by non-alphanumeric lookarounds so it can't match
// inside a word (`sword20`, `add`). Permissive on shape; parseDice is the real
// grammar check (see scanDice).
final _diceCandidate = RegExp(
  r'(?<![A-Za-z0-9])\d{0,3}d(?:\d{1,4}|%|f)'
  r'(?:(?:kh|kl|dh|dl)\d{1,3}|adv|dis)?!?(?:[+-]\d{1,4})?'
  r'(?![A-Za-z0-9])',
  caseSensitive: false,
);

/// Non-overlapping, in-order dice-notation spans in [text]. Each regex
/// candidate is validated by running [parseDice] in a try/catch; candidates
/// that don't parse (e.g. `d1` — sides must be 2-1000) are dropped, so every
/// returned span is guaranteed valid. `RegExp.allMatches` is already
/// non-overlapping and left-to-right.
List<DiceSpan> scanDice(String text) {
  final out = <DiceSpan>[];
  for (final m in _diceCandidate.allMatches(text)) {
    final token = m[0]!;
    try {
      parseDice(token);
    } on FormatException {
      continue; // looked dice-ish but isn't valid notation
    }
    out.add(DiceSpan(m.start, m.end, token));
  }
  return out;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/dice_scan_test.dart`
Expected: PASS (4 tests). If the `false positives` test fails on `sword20`/`road20`, the Dart regex lookbehind isn't behaving — STOP and report (do not weaken the anchors).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/dice_scan.dart test/dice_scan_test.dart
git commit -m "feat(dice): pure scanDice (regex candidates validated by parseDice)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Tappable dice spans in MentionText

**Files:**
- Modify: `lib/shared/mention_text.dart`
- Test: `test/mention_text_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `test/mention_text_test.dart` inside `void main()` (after the existing tests, before the final closing `}`). Reuse the existing file-level helpers `hasRecognizer` / the `RichText` walking pattern; these tests add their own walkers inline:

```dart
  // -- Inline tappable dice ---------------------------------------------------

  // Collects TextSpans carrying a tap recognizer, as (text, span) pairs.
  List<(String, TextSpan)> recognizerSpans(WidgetTester t) {
    final rt = t.widget<RichText>(find.byType(RichText).first);
    final out = <(String, TextSpan)>[];
    void walk(InlineSpan s) {
      if (s is TextSpan) {
        if (s.recognizer != null && s.text != null) out.add((s.text!, s));
        s.children?.forEach(walk);
      }
    }

    walk(rt.text);
    return out;
  }

  testWidgets('a dice token becomes a tappable span that fires onDiceTap',
      (tester) async {
    String? rolled;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MentionText('hit it for 2d6+3 now', onDiceTap: (n) => rolled = n),
      ),
    ));
    final dice = recognizerSpans(tester).where((p) => p.$1 == '2d6+3').toList();
    expect(dice, hasLength(1));
    (dice.single.$2.recognizer as TapGestureRecognizer).onTap!();
    expect(rolled, '2d6+3');
  });

  testWidgets('no dice spans under lonelog highlighting', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MentionText('roll 2d6 now', lonelog: true, onDiceTap: (_) {}),
      ),
    ));
    expect(recognizerSpans(tester).any((p) => p.$1 == '2d6'), isFalse);
  });

  testWidgets('a body with a mention AND dice yields both links',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MentionText('@[Mara](char:c1) rolls 2d6',
            onCharacterTap: (_) {}, onDiceTap: (_) {}),
      ),
    ));
    final spans = recognizerSpans(tester);
    expect(spans.any((p) => p.$1 == 'Mara'), isTrue); // mention link
    expect(spans.any((p) => p.$1 == '2d6'), isTrue); // dice link
  });

  testWidgets('no onDiceTap → dice text stays plain', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: MentionText('roll 2d6 now')),
    ));
    expect(recognizerSpans(tester).any((p) => p.$1 == '2d6'), isFalse);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/mention_text_test.dart`
Expected: FAIL — `MentionText` has no `onDiceTap` parameter (compile error).

- [ ] **Step 3: Implement**

In `lib/shared/mention_text.dart`:

(a) Add the import at the top beside the other `../engine/...` imports:

```dart
import '../engine/dice_scan.dart';
```

(b) Add the callback field + constructor param. The current constructor and fields are:

```dart
  const MentionText(
    this.body, {
    super.key,
    this.style,
    this.onCharacterTap,
    this.onThreadTap,
    this.lonelog = false,
  });
  final String body;
  final TextStyle? style;
  final void Function(String id)? onCharacterTap;
  final void Function(String id)? onThreadTap;
  final bool lonelog;
```

Replace it with (adds `onDiceTap` after `onThreadTap` in both the constructor and the fields):

```dart
  const MentionText(
    this.body, {
    super.key,
    this.style,
    this.onCharacterTap,
    this.onThreadTap,
    this.onDiceTap,
    this.lonelog = false,
  });
  final String body;
  final TextStyle? style;
  final void Function(String id)? onCharacterTap;
  final void Function(String id)? onThreadTap;

  /// Called with the dice notation when a player taps an inline dice token
  /// (e.g. `2d6+3`) in non-lonelog prose. Null disables dice detection.
  final void Function(String notation)? onDiceTap;
  final bool lonelog;
```

(c) The current `_textSpans` begins:

```dart
  List<InlineSpan> _textSpans(
      String text, TextStyle? base, ColorScheme scheme) {
    if (!widget.lonelog) return [TextSpan(text: text, style: base)];
```

Replace just that early-return line so non-lonelog runs get dice spans when a handler is wired:

```dart
  List<InlineSpan> _textSpans(
      String text, TextStyle? base, ColorScheme scheme) {
    if (!widget.lonelog) {
      if (widget.onDiceTap == null) return [TextSpan(text: text, style: base)];
      return _diceSpans(text, base, scheme);
    }
```

(d) Add the `_diceSpans` helper method to `_MentionTextState` (place it right after `_textSpans`):

```dart
  /// Splits a plain text run into plain spans + tappable dice-notation spans
  /// (link-styled, like a mention). Recognizers go in [_recognizers], which
  /// build() clears each frame and dispose() tears down.
  List<InlineSpan> _diceSpans(String text, TextStyle? base, ColorScheme scheme) {
    final dice = scanDice(text);
    if (dice.isEmpty) return [TextSpan(text: text, style: base)];
    final linkStyle = (base ?? const TextStyle())
        .copyWith(color: scheme.primary, fontWeight: FontWeight.w600);
    final out = <InlineSpan>[];
    var cursor = 0;
    for (final d in dice) {
      if (d.start > cursor) {
        out.add(TextSpan(text: text.substring(cursor, d.start), style: base));
      }
      final rec = TapGestureRecognizer()..onTap = () => widget.onDiceTap!(d.notation);
      _recognizers.add(rec);
      out.add(TextSpan(
          text: text.substring(d.start, d.end),
          style: linkStyle,
          recognizer: rec));
      cursor = d.end;
    }
    if (cursor < text.length) {
      out.add(TextSpan(text: text.substring(cursor), style: base));
    }
    return out;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/mention_text_test.dart`
Expected: PASS (existing tests + 4 new).

- [ ] **Step 5: Commit**

```bash
git add lib/shared/mention_text.dart test/mention_text_test.dart
git commit -m "feat(dice): tappable inline dice spans in MentionText (non-lonelog)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Wire roll + log in the journal

**Files:**
- Modify: `lib/features/journal_screen.dart`
- Test: `test/journal_inline_dice_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/journal_inline_dice_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';

import 'fake_interpreter.dart';

void main() {
  testWidgets('tapping an inline dice token logs a rerollable dice entry',
      (tester) async {
    // One result entry whose body is exactly a dice token.
    const journalJson =
        '[{"id":"1","timestamp":"2026-06-11T10:00:00.000","title":"Note",'
        '"body":"2d6+3","kind":"result"}]';
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': journalJson,
    });
    final data = OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>);
    final fake = FakeInterpreterService();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        interpreterServiceProvider.overrideWithValue(fake),
        oracleProvider.overrideWith((ref) async => Oracle(data)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: JournalScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));

    // Find the inline dice span and fire its tap recognizer.
    TapGestureRecognizer? diceTap;
    for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
      void walk(InlineSpan s) {
        if (s is TextSpan) {
          if (s.text == '2d6+3' && s.recognizer is TapGestureRecognizer) {
            diceTap = s.recognizer as TapGestureRecognizer;
          }
          s.children?.forEach(walk);
        }
      }

      walk(rt.text);
    }
    expect(diceTap, isNotNull, reason: 'dice token should be tappable');
    diceTap!.onTap!();
    await tester.pumpAndSettle();

    final entries = container.read(journalProvider).valueOrNull ?? const [];
    expect(entries, hasLength(2)); // original + the rolled entry
    final rolled = entries.first; // newest-first
    expect(rolled.sourceTool, 'dice');
    expect(rolled.payload?['expression'], '2d6+3'); // rerollable
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/journal_inline_dice_test.dart`
Expected: FAIL — the dice token isn't tappable yet (`diceTap` is null), because `onDiceTap` isn't wired in the journal.

- [ ] **Step 3: Implement**

In `lib/features/journal_screen.dart`:

(a) Confirm these imports exist (they do — used by the existing reroll path): `parseDice`/`diceRollGenResult`/`DiceRollResult` from `../engine/dice_notation.dart`. No new import needed.

(b) Add the `_rollDice` handler method to `_JournalScreenState`. Place it right after the existing `_openThread` method (around line 1541, `void _openThread(String id) => setState(() => _filterThreadId = id);`):

```dart
  /// Rolls an inline dice token tapped in journal prose and logs it as a
  /// rerollable `dice` entry (same pipeline as the dice-roller reroll).
  void _rollDice(String notation) {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final DiceRollResult r;
    try {
      r = parseDice(notation).roll(oracle.dice);
    } on FormatException {
      return; // scanDice already validated; stay defensive
    }
    final g = diceRollGenResult(r);
    ref.read(journalProvider.notifier).addResult(
          g.title,
          g.asText,
          sourceTool: 'dice',
          payload: {...g.toPayload(), 'expression': r.expression},
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${r.expression} = ${r.total}')),
    );
  }
```

(c) Wire `onDiceTap: _rollDice` into every `MentionText` that already passes `onCharacterTap: _openCharacter`. Find them:

Run: `grep -n "onCharacterTap: _openCharacter" lib/features/journal_screen.dart`

For EACH match (there are three, clustered around L718/738/748 — all entry-render `MentionText`s), add an `onDiceTap: _rollDice,` line immediately after the `onThreadTap: _openThread,` line in that same `MentionText(...)` constructor. Example — change:

```dart
            title: MentionText(e.body,
                onCharacterTap: _openCharacter,
                onThreadTap: _openThread,
```

to:

```dart
            title: MentionText(e.body,
                onCharacterTap: _openCharacter,
                onThreadTap: _openThread,
                onDiceTap: _rollDice,
```

Apply the same addition to all three sites.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/journal_inline_dice_test.dart`
Expected: PASS.

- [ ] **Step 5: Run analyze + full suite**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test` → expect All tests passed.

- [ ] **Step 6: Commit**

```bash
git add lib/features/journal_screen.dart test/journal_inline_dice_test.dart
git commit -m "feat(dice): roll+log inline dice taps from journal prose

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 `dice_scan.dart` (`DiceSpan`, `scanDice`, regex + parseDice validation) → Task 1. ✓
- §2 `mention_text.dart` `onDiceTap` + dice spans in non-lonelog runs → Task 2. ✓
- §3 `journal_screen.dart` `_rollDice` (reuses `diceRollGenResult` + `expression` payload) + wiring → Task 3. ✓
- Testing: pure `scanDice` false-positives (Task 1), `mention_text` render/tap/lonelog-skip (Task 2), journal tap → `dice` entry (Task 3). ✓
- "plain text runs only / skip when lonelog" → Task 2 Step 3(c) keeps the lonelog branch unchanged; the dice branch is under `if (!widget.lonelog)`. ✓
- "no system/AI gate" → `_rollDice` only needs the oracle (always available); no gate. ✓
- Out-of-scope items (multi-term, composer, insert-vs-roll) absent. ✓

**Type consistency:**
- `DiceSpan(start, end, notation)` defined Task 1, consumed Task 2 (`d.start`/`d.end`/`d.notation`). ✓
- `onDiceTap` is `void Function(String notation)?` in Task 2 def and Task 3 wiring (`_rollDice(String notation)`). ✓
- `scanDice(String) -> List<DiceSpan>` consistent across Tasks 1-2. ✓
- Roll pipeline mirrors the existing reroll path exactly: `parseDice(...).roll(oracle.dice)` → `diceRollGenResult` → `addResult(sourceTool:'dice', payload:{...toPayload(), 'expression': r.expression})`. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code. The "~L717/746/2026" line numbers are guidance; Task 3(c) gives a grep to locate them deterministically. ✓

**Risk note:** Task 1 Step 4 calls out the Dart-regex-lookbehind assumption explicitly — if it misbehaves, the false-positive test fails loudly rather than silently shipping bad detection.
