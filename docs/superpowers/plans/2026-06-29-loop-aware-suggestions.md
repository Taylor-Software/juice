# Loop-Aware Suggestion Chips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the solo loop's signature moves as one-tap suggestion chips — `ask-yes-no` (inline d10 yes/no, in the InlineRollDock) and `roll-tally` (navigate to threads, in the assistant rail, tally-gated).

**Architecture:** Pure additions to `suggestionsFor` (a new `hasTally` input + two `Suggestion`s), a new `ask-yes-no` case in `rollInlineSuggestion`, an explicit dock chip, and a rail navigate case. The AI ranking seam is unaffected (tolerant of new ids).

**Tech Stack:** Dart/Flutter, Riverpod, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-29-loop-aware-suggestions-design.md`

**Environment:** `flutter` at `$HOME/development/flutter/bin` — `export PATH="$HOME/development/flutter/bin:$PATH"`. Package `juice_oracle`.

---

## File Structure

**Changed**
- `lib/engine/suggestions.dart` — `hasTally` param + `ask-yes-no`/`roll-tally` chips.
- `lib/state/suggestions_provider.dart` — `hasTally` wiring + `ask-yes-no` inline case.
- `lib/features/inline_roll_dock.dart` — Ask yes/no dock chip.
- `lib/features/assistant_rail.dart` — `roll-tally` navigate case (`_onTap`).
- `test/suggestions_test.dart` — add `hasTally:` to all calls + new presence/gating tests.

**New**
- `test/dock_ask_yes_no_test.dart` — dock chip renders + logs a `solo-loop` entry.

**Reference (read, don't change)**
- `lib/engine/suggestions.dart:17` — current `suggestionsFor` signature (5 bool params).
- `lib/state/suggestions_provider.dart:29` — the single production call site; `:44` `rollInlineSuggestion`.
- `lib/engine/solo_oracle.dart` — `soloYesNo(SoloLikelihood, Dice)`, `SoloLikelihood.even`, `SoloYesNo.toGenResult()`.
- `lib/engine/oracle.dart:82` — `Oracle` exposes `final Dice dice` (public).
- `lib/features/inline_roll_dock.dart:38-101` — `byId` + `chip(...)` pattern (the `scene-event` conditional chip is the model to copy).
- `lib/features/assistant_rail.dart:88-111` — `_onTap` switch (navigate cases → `route.goTo`).
- `test/suggestion_chips_test.dart` — the JournalScreen pump harness to copy for the dock test.

---

## Task 1: Engine + provider + inline runner (TDD)

**Files:**
- Modify: `lib/engine/suggestions.dart`, `lib/state/suggestions_provider.dart`
- Test: `test/suggestions_test.dart`

- [ ] **Step 1: Update existing tests to the new signature + add new cases (write failing test)**

In `test/suggestions_test.dart`, add `hasTally: false,` to EACH of the existing
`suggestionsFor(...)` calls (there are calls at lines ~12, 24, 36, 50, 61, the `run`
helper at ~72, and ~85 — every invocation must include the new required param). Then add
these two tests inside the `group('suggestionsFor', ...)`:

```dart
    test('ask-yes-no is always present, inline, right after roll-oracle', () {
      final s = suggestionsFor(
        hasScenes: false,
        hasOpenThreads: false,
        encounterActive: false,
        ironswornFamily: false,
        hasFocusCharacter: false,
        hasTally: false,
      );
      expect(ids(s).sublist(0, 2), ['roll-oracle', 'ask-yes-no']);
      expect(s[1].action, SuggestionAction.inline);
    });

    test('roll-tally (navigate) only when hasTally', () {
      List<String> run(bool hasTally) => ids(suggestionsFor(
            hasScenes: true,
            hasOpenThreads: false,
            encounterActive: false,
            ironswornFamily: false,
            hasFocusCharacter: false,
            hasTally: hasTally,
          ));
      expect(run(true), contains('roll-tally'));
      expect(run(false), isNot(contains('roll-tally')));
      final s = suggestionsFor(
        hasScenes: true,
        hasOpenThreads: false,
        encounterActive: false,
        ironswornFamily: false,
        hasFocusCharacter: false,
        hasTally: true,
      );
      expect(s.firstWhere((e) => e.id == 'roll-tally').action,
          SuggestionAction.navigate);
    });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/suggestions_test.dart`
Expected: FAIL to compile — `suggestionsFor` has no `hasTally` parameter.

- [ ] **Step 3: Add `hasTally` + the two chips in `lib/engine/suggestions.dart`**

Replace the `suggestionsFor` function body with:

```dart
List<Suggestion> suggestionsFor({
  required bool hasScenes,
  required bool hasOpenThreads,
  required bool encounterActive,
  required bool ironswornFamily,
  required bool hasFocusCharacter,
  required bool hasTally,
}) {
  return [
    const Suggestion('roll-oracle', 'Roll the oracle', SuggestionAction.inline),
    const Suggestion('ask-yes-no', 'Ask yes/no', SuggestionAction.inline),
    if (hasScenes)
      const Suggestion('scene-event', 'Scene event', SuggestionAction.inline)
    else
      const Suggestion(
          'start-scene', 'Start a scene', SuggestionAction.navigate),
    if (hasOpenThreads)
      const Suggestion(
          'advance-thread', 'Advance a thread', SuggestionAction.navigate),
    if (hasTally)
      const Suggestion('roll-tally', 'Roll a task', SuggestionAction.navigate),
    if (encounterActive)
      const Suggestion('combat-turn', 'Take a turn', SuggestionAction.navigate),
    if (ironswornFamily && hasFocusCharacter)
      const Suggestion('make-move', 'Make a move', SuggestionAction.navigate),
    const Suggestion(
        'develop-rumor', 'Develop a rumor', SuggestionAction.navigate),
    const Suggestion('seed-npc', 'Add an NPC', SuggestionAction.navigate),
  ];
}
```

- [ ] **Step 4: Wire `hasTally` + the inline case in `lib/state/suggestions_provider.dart`**

Add the import near the top (with the other engine imports):

```dart
import '../engine/solo_oracle.dart';
```

In the `suggestionsProvider` body, add the `hasTally` argument to the `suggestionsFor`
call (after `hasFocusCharacter:`):

```dart
    hasTally: threads.any((t) => t.tally != null),
```

In `rollInlineSuggestion`, add a case before the `default:`:

```dart
    case 'ask-yes-no':
      final g = soloYesNo(SoloLikelihood.even, oracle.dice).toGenResult();
      return ref.read(journalProvider.notifier).addResult(g.title, g.asText,
          sourceTool: 'solo-loop', payload: g.toPayload());
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/suggestions_test.dart`
Expected: PASS (all existing + 2 new).

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/engine/suggestions.dart lib/state/suggestions_provider.dart test/suggestions_test.dart`
Expected: No new issues.

- [ ] **Step 7: Commit**

```bash
git add lib/engine/suggestions.dart lib/state/suggestions_provider.dart test/suggestions_test.dart
git commit -m "feat(suggestions): ask-yes-no + roll-tally loop chips + hasTally"
```

---

## Task 2: Dock chip + rail navigate case + dock test

**Files:**
- Modify: `lib/features/inline_roll_dock.dart`, `lib/features/assistant_rail.dart`
- Test: `test/dock_ask_yes_no_test.dart`

- [ ] **Step 1: Write the failing dock test**

```dart
// test/dock_ask_yes_no_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

OracleData _loadData() =>
    OracleData(jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>);

const _session = {
  'juice.sessions.v1':
      '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
};

void main() {
  testWidgets('dock Ask yes/no chip logs a solo-loop journal entry',
      (tester) async {
    SharedPreferences.setMockInitialValues(_session);
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.unsupported));
    final oracle = Oracle(_loadData(), Dice(Random(1)));
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        oracleProvider.overrideWith((ref) async => oracle),
        interpreterServiceProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: JournalScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    final chip = find.byKey(const Key('dock-ask-yes-no'));
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final journal = await container.read(journalProvider.future);
    expect(journal.where((e) => e.sourceTool == 'solo-loop'), hasLength(1));
    expect(journal.first.title, contains('Yes/No'));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/dock_ask_yes_no_test.dart`
Expected: FAIL — `dock-ask-yes-no` chip not found.

- [ ] **Step 3: Add the dock chip in `lib/features/inline_roll_dock.dart`**

After `final sceneEvent = byId('scene-event');` add:

```dart
    final askYesNo = byId('ask-yes-no');
```

In the `Row`'s `children`, insert this chip immediately after the `scene-event` chip
block (the `if (sceneEvent != null) chip(...)`), before the Inspire chip:

```dart
            // Ask yes/no — direct one-tap d10 solo oracle (even odds).
            if (askYesNo != null)
              chip(
                key: const Key('dock-ask-yes-no'),
                label: '? Yes/No',
                bg: tk.selected,
                fg: tk.terracottaDeep,
                onTap: () => _roll(ref, askYesNo),
              ),
```

(`_roll` already runs `rollInlineSuggestion` + the optional scroll callback. `suggestionsFor`
always emits `ask-yes-no`, so the chip is effectively always shown; the `!= null` guard
mirrors the `scene-event` defensive pattern for the loading frame.)

- [ ] **Step 4: Add the rail navigate case in `lib/features/assistant_rail.dart`**

In the `_onTap` switch (after the `advance-thread` case ~line 103), add:

```dart
      case 'roll-tally':
        route.goTo(Destination.track, subtab: 'threads');
```

- [ ] **Step 5: Run the dock test**

Run: `flutter test test/dock_ask_yes_no_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/features/inline_roll_dock.dart lib/features/assistant_rail.dart test/dock_ask_yes_no_test.dart`
Expected: No new issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/inline_roll_dock.dart lib/features/assistant_rail.dart test/dock_ask_yes_no_test.dart
git commit -m "feat(rail): Ask yes/no dock chip + roll-tally navigate case"
```

---

## Task 3: Full verification + bookkeeping + PR

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze` → no new errors.
Run: `flutter test` → all pass (suite was 1695; +~3 here).

- [ ] **Step 2: Update CLAUDE.md**

Add a sentence to the assistant-rail bullet (the `lib/features/assistant_rail.dart` notes):
the rule-based `SuggestionEngine` now also emits `ask-yes-no` (inline d10 solo yes/no,
even odds → `solo-loop` entry, rendered as the `dock-ask-yes-no` InlineRollDock chip) and
`roll-tally` (navigate → Track/Threads, gated on any thread having a `Tally`). Reference
the spec.

- [ ] **Step 3: Commit + push + PR**

```bash
git add CLAUDE.md
git commit -m "docs: note loop-aware suggestion chips"
git push -u origin feat/loop-aware-suggestions
gh pr create --title "feat(suggestions): loop-aware chips (ask yes/no + roll a task)" \
  --body "Implements docs/superpowers/specs/2026-06-29-loop-aware-suggestions-design.md"
```

---

## Self-Review notes

- **Spec coverage:** `hasTally` + `ask-yes-no`/`roll-tally` chips (T1) ✓; provider wiring +
  inline `ask-yes-no` runner (T1) ✓; dock chip (T2) ✓; rail navigate case (T2) ✓; tests
  for presence/gating + dock logging (T1, T2) ✓. No word-oracle chip (redundant), no AI
  auto-interpret, no reordering — all honored.
- **Required-param break:** `hasTally` is required, so EVERY existing `suggestionsFor`
  call must add it — the only production caller is the provider (T1 Step 4); all 7 test
  calls are updated in T1 Step 1. A missed call site is a compile error, caught at T1 Step 5.
- **Type consistency:** `hasTally` bool, ids `ask-yes-no`/`roll-tally`, `sourceTool
  'solo-loop'`, `SoloLikelihood.even`, `oracle.dice`, dock key `dock-ask-yes-no`, rail
  target `goTo(track, 'threads')` — consistent across tasks.
