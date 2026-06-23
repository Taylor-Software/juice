# `/spread` Slash Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/spread` composer slash command that draws + logs a tarot spread, with an optional text argument selecting which spread.

**Architecture:** A pure `resolveSpread(arg)` maps free text to a `TarotSpread`. `DecksNotifier.drawSpreadAndLog` draws (persisting deck state) + logs one `cards` entry via `spreadBody` (mirrors `drawAndLog`). The journal composer dispatches `/spread` to it and shows a `slash-cmd-spread` palette chip. Mirrors the shipped `/card`/`/tarot` path.

**Tech Stack:** Dart, Flutter, flutter_riverpod, flutter_test. Reuses `kTarotSpreads`/`spreadBody` (`tarot_spreads.dart`), `DecksNotifier.drawSpread`, the journal slash machinery.

---

## File Structure

- **Modify** `lib/engine/tarot_spreads.dart` — `resolveSpread(String) -> TarotSpread`. Pure.
- **Modify** `lib/state/providers.dart` — `DecksNotifier.drawSpreadAndLog`.
- **Modify** `lib/features/journal_screen.dart` — `_builtinSpread`, `_drawSpreadCmd`, `_send` dispatch, palette chip + empty-guard.
- **Modify** `test/tarot_spreads_test.dart` — `resolveSpread` cases.
- **Modify** `test/card_oracle_test.dart` — `drawSpreadAndLog` provider test.
- **Modify** `test/slash_palette_test.dart` — palette visibility + chip-logs + `/spread celtic` via send.

---

## Task 1: Pure resolveSpread

**Files:**
- Modify: `lib/engine/tarot_spreads.dart`
- Test: `test/tarot_spreads_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/tarot_spreads_test.dart` inside `void main()` (after the existing tests; the file imports `tarot_spreads.dart`):

```dart
  group('resolveSpread', () {
    test('empty or unknown arg → the default (first) spread', () {
      expect(resolveSpread(''), kTarotSpreads.first);
      expect(resolveSpread('   '), kTarotSpreads.first);
      expect(resolveSpread('zzz'), kTarotSpreads.first);
    });

    test('matches by id prefix and name substring, case-insensitive', () {
      expect(resolveSpread('celtic').id, 'celtic-cross');
      expect(resolveSpread('CELTIC').id, 'celtic-cross');
      expect(resolveSpread('cross').id, 'cross'); // 5-card, before celtic-cross
      expect(resolveSpread('five').id, 'cross'); // name "Five-card Cross"
      expect(resolveSpread('three').id, 'three-card');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tarot_spreads_test.dart`
Expected: FAIL — `resolveSpread` undefined.

- [ ] **Step 3: Implement**

In `lib/engine/tarot_spreads.dart`, add at the end of the file:

```dart
/// Resolves a spread from free-text [arg]: a case-insensitive match against a
/// spread's id (prefix) or name (substring). Empty or no match → the first
/// spread (the 3-card default). Used by the /spread slash command's argument.
TarotSpread resolveSpread(String arg) {
  final q = arg.trim().toLowerCase();
  if (q.isEmpty) return kTarotSpreads.first;
  for (final s in kTarotSpreads) {
    if (s.id.toLowerCase().startsWith(q) || s.name.toLowerCase().contains(q)) {
      return s;
    }
  }
  return kTarotSpreads.first;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/tarot_spreads_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/tarot_spreads.dart test/tarot_spreads_test.dart
git commit -m "feat(cards): resolveSpread — free-text spread selector

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: DecksNotifier.drawSpreadAndLog

**Files:**
- Modify: `lib/state/providers.dart`
- Test: `test/card_oracle_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/card_oracle_test.dart` inside the `group('DecksNotifier', ...)` block (after the `setJokers` test, before the group's closing `});`):

```dart
    test('drawSpreadAndLog logs one cards entry with the spread + positions',
        () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      });
      final oracle = Oracle(data, Dice(Random(6)));
      final c = ProviderContainer(
          overrides: [oracleProvider.overrideWith((ref) async => oracle)]);
      addTearDown(c.dispose);
      await c.read(decksProvider.future);
      await c.read(journalProvider.future);

      final spread = kTarotSpreads.first; // three-card
      await c.read(decksProvider.notifier).drawSpreadAndLog(oracle, spread);

      final entries = c.read(journalProvider).valueOrNull!;
      expect(entries, hasLength(1));
      expect(entries.single.sourceTool, 'cards');
      expect(entries.single.body, contains(spread.name));
      for (final pos in spread.positions) {
        expect(entries.single.body, contains(pos));
      }
      // Tarot deck advanced by the spread size.
      expect(c.read(decksProvider).valueOrNull!.tarot.drawn, spread.count);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/card_oracle_test.dart`
Expected: FAIL — `drawSpreadAndLog` undefined.

- [ ] **Step 3: Implement**

In `lib/state/providers.dart`, `DecksNotifier`, add immediately after the `drawSpread` method (before `reshuffle`):

```dart
  /// Draws a [spread] (persisting deck state) AND logs it as one `cards` journal
  /// entry, folding each position's meaning in via spreadBody. Mirrors
  /// drawAndLog for single cards; used by the /spread slash command. (The Cards
  /// section keeps its own draw → show → manual-log flow.)
  Future<void> drawSpreadAndLog(Oracle oracle, TarotSpread spread) async {
    final out = await drawSpread(oracle, spread);
    await ref.read(journalProvider.notifier).addResult(
          'Tarot Spread',
          spreadBody(spread.name, out.cards),
          sourceTool: 'cards',
        );
  }
```

(`spreadBody` is already imported from `tarot_spreads.dart`; `drawSpread` returns `({cards, result})`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/card_oracle_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/card_oracle_test.dart
git commit -m "feat(cards): DecksNotifier.drawSpreadAndLog (draw + journal log)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Journal `/spread` command + palette

**Files:**
- Modify: `lib/features/journal_screen.dart`
- Test: `test/slash_palette_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `test/slash_palette_test.dart` inside `void main()`. Reuse the file-level `cardsPrefs` const + `pumpPalette` helper (already present):

```dart
  testWidgets('/spread suggestion appears only when cards is on',
      (tester) async {
    await pumpPalette(tester, data); // cards off
    await tester.enterText(find.byKey(const Key('journal-composer')), '/spr');
    await tester.pump();
    expect(find.byKey(const Key('slash-cmd-spread')), findsNothing);

    await pumpPalette(tester, data, prefs: cardsPrefs); // cards on
    await tester.enterText(find.byKey(const Key('journal-composer')), '/spr');
    await tester.pump();
    expect(find.byKey(const Key('slash-cmd-spread')), findsOneWidget);
  });

  testWidgets('tapping the spread chip logs a default 3-card spread entry',
      (tester) async {
    await pumpPalette(tester, data, prefs: cardsPrefs);
    await tester.enterText(find.byKey(const Key('journal-composer')), '/spread');
    await tester.pump();
    await tester.tap(find.byKey(const Key('slash-cmd-spread')));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.where((e) => e.sourceTool == 'cards'), hasLength(1));
    // 3-card default → its position labels are in the body.
    expect(entries.first.body, contains('Past'));
    expect(entries.first.body, contains('Future'));
  });

  testWidgets('/spread celtic via Enter logs the 10-card spread',
      (tester) async {
    await pumpPalette(tester, data, prefs: cardsPrefs);
    await tester.enterText(
        find.byKey(const Key('journal-composer')), '/spread celtic');
    await tester.pump();
    await tester.tap(find.byKey(const Key('journal-send')));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.where((e) => e.sourceTool == 'cards'), hasLength(1));
    // 'Foundation' is a Celtic-Cross-only position label.
    expect(entries.first.body, contains('Foundation'));
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/slash_palette_test.dart`
Expected: FAIL — no `slash-cmd-spread`; `/spread` logs nothing.

- [ ] **Step 3: Implement** — `lib/features/journal_screen.dart`

(a) Add the import for `resolveSpread` if `tarot_spreads.dart` isn't already imported. Check:

Run: `grep -n "tarot_spreads" lib/features/journal_screen.dart`

If absent, add `import '../engine/tarot_spreads.dart';` beside the other `../engine/...` imports.

(b) Add the builtin const beside `_builtinTarot`:

```dart
  static const _builtinSpread = 'spread';
```

(c) Add the command method right after `_drawCardCmd` (the method around line 270):

```dart
  Future<void> _drawSpreadCmd(String arg) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final spread = resolveSpread(arg);
    await ref.read(decksProvider.notifier).drawSpreadAndLog(oracle, spread);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Drew ${spread.name}')),
      );
    }
  }
```

(d) Add the `_send` dispatch right after the `_builtinTarot` block:

```dart
      if (_builtinSpread == tok) {
        _composer.clear();
        await _drawSpreadCmd(parsed.rest);
        return;
      }
```

(e) Add the palette flag beside `showCard`/`showTarot`:

```dart
    final showSpread = _builtinSpread.startsWith(tok) && cardsOn;
```

(f) Add the palette chip right after the `if (showTarot) ListTile(...)` block:

```dart
            if (showSpread)
              ListTile(
                key: const Key('slash-cmd-spread'),
                dense: true,
                leading: const Icon(Icons.dashboard_outlined),
                title: const Text('Draw a tarot spread'),
                onTap: () {
                  _composer.clear();
                  _drawSpreadCmd('');
                },
              ),
```

(g) Add `&& !showSpread` to the "No matching command" empty-state guard (the `if (matches.isEmpty && !showScene && ... && !showTarot)` condition):

```dart
                !showTarot &&
                !showSpread)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/slash_palette_test.dart`
Expected: PASS (existing + 3 new).

- [ ] **Step 5: Run analyze + full suite**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test` → expect All tests passed.

- [ ] **Step 6: Commit**

```bash
git add lib/features/journal_screen.dart test/slash_palette_test.dart
git commit -m "feat(cards): /spread slash command (arg-selected spread draw+log)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Doc sync — CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (the card-oracle bullet's Deferred line + the single-card slash-command parenthetical)

- [ ] **Step 1: Update CLAUDE.md**

The card-oracle bullet currently ends the spreads sentence with a single-card-slash parenthetical and a Deferred line. Two edits:

Change:

```
  (Single-card
  draws also have `/card` + `/tarot` slash commands and a HUD quick-draw, #133.)
  Deferred: a `/spread` slash command (needs a picker). See
```

to:

```
  (Single-card
  draws have `/card` + `/tarot` slash commands and a HUD quick-draw, #133; the
  `/spread` command draws a spread, arg-selected — `/spread celtic` — via the
  pure `resolveSpread` + `DecksNotifier.drawSpreadAndLog`.) See
```

(This removes the now-shipped `/spread` from Deferred and folds it into the
shipped-features parenthetical.)

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note the /spread slash command in CLAUDE.md

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 `resolveSpread` → Task 1. ✓
- §2 `drawSpreadAndLog` → Task 2. ✓
- §3 `_builtinSpread` / `_drawSpreadCmd` / dispatch / palette chip + guard → Task 3. ✓
- Testing: resolver (Task 1), provider (Task 2), palette visibility + chip-log + arg-via-send (Task 3). ✓

**Type consistency:**
- `resolveSpread(String) -> TarotSpread` defined Task 1, used Task 3(c). ✓
- `drawSpreadAndLog(Oracle, TarotSpread) -> Future<void>` defined Task 2, used Task 3(c). ✓
- `drawSpread` returns `({cards, result})`; Task 2 uses `out.cards`. ✓
- Keys `slash-cmd-spread`, existing `journal-composer`/`journal-send` consistent between Task 3 impl + tests. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code. The Task 3(a) import check + 3(b/e/f/g) anchors are described against existing nearby code (`_builtinTarot`, `showTarot`, the empty-guard); `flutter analyze` (Step 5) is the hard gate on a missed brace. ✓

**Risk note:** Task 3(f)/(g) edits the palette's chip list + empty-state guard — the existing `/card`+`/tarot` palette tests regression-cover that those chips still resolve, and analyze catches a malformed guard.
