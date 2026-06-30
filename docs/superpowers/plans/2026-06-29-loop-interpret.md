# Solo Loop One-Tap AI Interpret — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an aiReady-gated `loop-interpret` button to the Solo Loop Ask step that interprets the yes/no roll via the shared `OracleInterpretationSheet`, logging an `'interpret'` entry.

**Architecture:** Port `run_screen.dart`'s `_interpret` into `loop_pane.dart` (the only diff: `_last` is a `SoloYesNo`, so seed from `last.toGenResult()`). No engine/seam/persistence changes.

**Tech Stack:** Flutter, Riverpod, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-29-loop-interpret-design.md`

**Environment:** `flutter` at `$HOME/development/flutter/bin` — `export PATH="$HOME/development/flutter/bin:$PATH"`. Package `juice_oracle`.

---

## Task 1: loop-interpret button + handler (TDD)

**Files:**
- Modify: `lib/features/loop_pane.dart`
- Test: `test/loop_pane_test.dart`

**Reference (read, don't change):** `lib/features/run_screen.dart:664-697` (`_interpret`, the verbatim template).

- [ ] **Step 1: Write the failing tests**

In `test/loop_pane_test.dart`, replace the `pump` helper so it accepts overrides, and add
two gating tests. New top of file (add the riverpod import already present):

```dart
  Future<void> pump(WidgetTester tester,
      {List<Override> overrides = const []}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: Scaffold(body: LoopPane())),
    ));
    await tester.pumpAndSettle();
  }
```

(Existing `pump(tester)` calls keep working — the param is optional. The previous helper
was `const ProviderScope(...)`; the new one drops `const` because `overrides` is runtime.)

Add these tests in `main()`:

```dart
  testWidgets('no Interpret button when AI is not ready', (tester) async {
    await pump(tester); // default: aiReady false
    await tester.tap(find.byKey(const Key('loop-ask')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-ask-result')), findsOneWidget);
    expect(find.byKey(const Key('loop-interpret')), findsNothing);
  });

  testWidgets('Interpret button shows after a roll when AI is ready',
      (tester) async {
    await pump(tester, overrides: [aiReadyProvider.overrideWithValue(true)]);
    // Absent before any roll (no _last yet).
    expect(find.byKey(const Key('loop-interpret')), findsNothing);
    await tester.tap(find.byKey(const Key('loop-ask')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-interpret')), findsOneWidget);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/loop_pane_test.dart`
Expected: the two new tests FAIL (`loop-interpret` never found); the AI-ready one also
needs `aiReadyProvider` importable — it comes from `providers.dart` (already imported in
the test).

- [ ] **Step 3: Add the imports to `lib/features/loop_pane.dart`**

After the existing imports, add:

```dart
import '../engine/models.dart';
import '../engine/oracle_interpreter.dart';
import 'oracle_interpretation_sheet.dart';
```

- [ ] **Step 4: Watch `aiReadyProvider` in `build`**

In `_LoopPaneState.build`, after the existing `final tallied = ...` line (the last of the
`ref.watch` reads near the top of build), add:

```dart
    final aiReady = ref.watch(aiReadyProvider);
```

- [ ] **Step 5: Add the gated button in the Ask step**

In the `'2 · Ask a question'` step's children list, immediately after the
`if (_last != null) Padding(... key: Key('loop-ask-result') ...)` block, add:

```dart
          if (aiReady && _last != null)
            OutlinedButton(
              key: const Key('loop-interpret'),
              onPressed: _interpret,
              child: const Text('Interpret'),
            ),
```

- [ ] **Step 6: Add the `_interpret` method**

Add this method to `_LoopPaneState` (e.g. after `_ask`):

```dart
  Future<void> _interpret() async {
    final last = _last;
    if (last == null) return;
    final g = last.toGenResult();
    final journal =
        ref.read(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final ctx = ref.read(playContextProvider).valueOrNull;
    final scene = activeSceneEntry(journal, ctx?.activeSceneId);
    final settings =
        ref.read(settingsProvider).valueOrNull ?? const CampaignSettings();
    final seed = OracleSeed(
      resultText: g.asText,
      genre: settings.genre,
      tone: settings.tone,
      sceneContext: scene == null ? '' : '${scene.title}\n${scene.body}'.trim(),
      activeCharacter: ref.read(activeCharacterLineProvider),
      systemPrimer: ref.read(systemPrimerProvider),
    );
    final accepted = await showModalBottomSheet<OracleInterpretation>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => OracleInterpretationSheet(
        seed: seed,
        onAccept: (card) => Navigator.pop(sheetCtx, card),
      ),
    );
    if (accepted == null || !mounted) return;
    await ref.read(journalProvider.notifier).addResult(
          'Oracle reading',
          '(${accepted.lens}): ${accepted.reading}',
          sourceTool: 'interpret',
        );
  }
```

Verify the symbols resolve: `OracleSeed`/`OracleInterpretation` (oracle_interpreter.dart),
`OracleInterpretationSheet` (oracle_interpretation_sheet.dart), `CampaignSettings`/
`JournalEntry` (models.dart), `activeCharacterLineProvider`/`activeSceneEntry`/
`playContextProvider` (play_context.dart, already imported), `settingsProvider`/
`systemPrimerProvider`/`journalProvider` (providers.dart, already imported). If
`CampaignSettings` is exported from a different file than models.dart, add that import
instead — confirm by checking `run_screen.dart`'s imports (it constructs
`const CampaignSettings()`).

- [ ] **Step 7: Run the tests**

Run: `flutter test test/loop_pane_test.dart`
Expected: all PASS (existing 2 + new 2).

- [ ] **Step 8: Analyze**

Run: `flutter analyze lib/features/loop_pane.dart test/loop_pane_test.dart`
Expected: No new issues.

- [ ] **Step 9: Commit**

```bash
git add lib/features/loop_pane.dart test/loop_pane_test.dart
git commit -m "feat(loop): one-tap AI interpret on the yes/no roll"
```

---

## Task 2: Full verification + bookkeeping + PR

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze` → no new errors.
Run: `flutter test` → all pass (suite was 1698; +2 here).

- [ ] **Step 2: Update CLAUDE.md**

In the Solo Loop bullet (the `2026-06-29-solo-loop-success-tally` notes), add a sentence:
the Loop Ask step has an aiReady-gated `loop-interpret` button that seeds an `OracleSeed`
from the yes/no roll + active scene + PC + primer, runs the shared
`OracleInterpretationSheet`, and logs an `'interpret'` entry (a port of the Run screen's
`run-dice-interpret`). Reference the spec.

- [ ] **Step 3: Commit + push + PR**

```bash
git add CLAUDE.md
git commit -m "docs: note Loop one-tap AI interpret"
git push -u origin feat/loop-interpret
gh pr create --title "feat(loop): one-tap AI interpret on the yes/no roll" \
  --body "Implements docs/superpowers/specs/2026-06-29-loop-interpret-design.md"
```

---

## Self-Review notes

- **Spec coverage:** `_interpret` port (T1 Step 6) ✓; aiReady-gated button (T1 Step 5) ✓;
  3 imports (T1 Step 3) ✓; gating tests both directions (T1 Step 1) ✓. No auto-open, no
  dock interpret, no helper extraction — all honored.
- **Watch-out:** `_interpret` runs `await` then touches `context`/`ref` — the `if (accepted
  == null || !mounted) return;` guard (verbatim from run_screen) covers the post-await
  unmount. Keep it.
- **Type consistency:** `_last` is `SoloYesNo` → `last.toGenResult()` → `OracleSeed`;
  button key `loop-interpret`; `sourceTool 'interpret'`; `aiReadyProvider` bool.
