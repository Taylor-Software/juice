# Loop as a First-Class "Play" Surface — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the guided solo-play loop the app's spine — merge the Journal + Loop verbs into one "Play" destination with a context-aware "Next beat" launcher and inline oracle interpretation.

**Architecture:** Repurpose the existing `Destination.journal` slot (keep the enum id, relabel "Play"); mount `Column[LoopBar, JournalScreen]` on that verb. `LoopBar` absorbs today's `loop_pane.dart` logic and adds a Next-beat menu driven by a pure `nextBeatActions` engine plus an inline interpret card with Keep/Discard. Party campaigns land on Play.

**Tech Stack:** Flutter, flutter_riverpod, `package:flutter_test`. On-device LLM via the existing `InterpreterService` seam (tests use `FakeInterpreterService`).

**Spec:** `docs/superpowers/specs/2026-06-30-loop-first-class-play-surface-design.md`

**Branch:** `feat/wedge-phase1-play-surface` (already created; the spec commit lives here).

**Run tests with:** `export PATH="$PATH:/Users/johntaylor/development/flutter/bin"` first (flutter is not on PATH by default in this environment).

---

## File Structure

- **New** `lib/engine/next_beat.dart` — pure `BeatAction` enum + `nextBeatActions(...)`. No Flutter import.
- **New** `test/next_beat_test.dart` — unit tests for the state machine.
- **New** `lib/features/loop_bar.dart` — `LoopBar` (was `LoopPane`) + `PlayScreen` wrapper + private `_InterpretCard`. Absorbs `loop_pane.dart`.
- **Renamed** `test/loop_pane_test.dart` → `test/loop_bar_test.dart` — pumps `LoopBar`.
- **Deleted** `lib/features/loop_pane.dart` — content moves to `loop_bar.dart`.
- **Modified** `lib/shared/destination.dart` — Play label/icon + `landingDestination(party)`.
- **Modified** `lib/shared/home_shell.dart` — `_root(Destination.journal)` returns `PlayScreen`.
- **Modified** `lib/features/tracking_tab.dart` — drop the `loop` subtab.
- **Modified** `lib/features/track_home_pane.dart` — drop the Loop help line.
- **Modified** landing/subtab tests (Task 5).

---

## Task 1: Pure `nextBeatActions` engine

**Files:**
- Create: `lib/engine/next_beat.dart`
- Test: `test/next_beat_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/next_beat_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/next_beat.dart';

void main() {
  test('no scene -> only name the scene', () {
    expect(
      nextBeatActions(
          hasScene: false, hasRecentAsk: false, interpretDone: false, aiReady: false),
      [BeatAction.nameScene],
    );
  });

  test('scene, no ask -> ask/inspire/capture', () {
    expect(
      nextBeatActions(
          hasScene: true, hasRecentAsk: false, interpretDone: false, aiReady: true),
      [BeatAction.ask, BeatAction.inspire, BeatAction.capture],
    );
  });

  test('scene + ask, ai ready, not yet interpreted -> interpret leads', () {
    expect(
      nextBeatActions(
          hasScene: true, hasRecentAsk: true, interpretDone: false, aiReady: true),
      [BeatAction.interpret, BeatAction.capture, BeatAction.askAgain],
    );
  });

  test('scene + ask, already interpreted -> no interpret', () {
    final a = nextBeatActions(
        hasScene: true, hasRecentAsk: true, interpretDone: true, aiReady: true);
    expect(a.contains(BeatAction.interpret), isFalse);
    expect(a, [BeatAction.askAgain, BeatAction.capture, BeatAction.inspire]);
  });

  test('scene + ask, ai off -> no interpret even if not done', () {
    final a = nextBeatActions(
        hasScene: true, hasRecentAsk: true, interpretDone: false, aiReady: false);
    expect(a.contains(BeatAction.interpret), isFalse);
    expect(a, [BeatAction.askAgain, BeatAction.capture, BeatAction.inspire]);
  });

  test('never returns more than 3 actions', () {
    for (final scene in [true, false]) {
      for (final ask in [true, false]) {
        for (final done in [true, false]) {
          for (final ai in [true, false]) {
            expect(
                nextBeatActions(
                        hasScene: scene,
                        hasRecentAsk: ask,
                        interpretDone: done,
                        aiReady: ai)
                    .length,
                lessThanOrEqualTo(3));
          }
        }
      }
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/next_beat_test.dart`
Expected: FAIL — `next_beat.dart` / `nextBeatActions` not defined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/engine/next_beat.dart

/// The distinct beats the loop's "Next beat" launcher can offer. Pure — no
/// Flutter. The widget maps each to a label + icon + handler.
enum BeatAction { nameScene, ask, askAgain, interpret, inspire, capture }

/// Chooses the 2-3 most relevant beats for the current play state, priority
/// ordered, capped at 3. Deterministic; see the spec's state table.
List<BeatAction> nextBeatActions({
  required bool hasScene,
  required bool hasRecentAsk,
  required bool interpretDone,
  required bool aiReady,
}) {
  if (!hasScene) return const [BeatAction.nameScene];
  if (!hasRecentAsk) {
    return const [BeatAction.ask, BeatAction.inspire, BeatAction.capture];
  }
  if (aiReady && !interpretDone) {
    return const [BeatAction.interpret, BeatAction.capture, BeatAction.askAgain];
  }
  return const [BeatAction.askAgain, BeatAction.capture, BeatAction.inspire];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/next_beat_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/next_beat.dart test/next_beat_test.dart
git commit -m "feat(loop): pure nextBeatActions state machine"
```

---

## Task 2: Move Loop → `LoopBar` + `PlayScreen`, mount on the Play verb

This is the structural swap. `LoopBar` is a drop-in of today's `LoopPane` (same 5 cards, same keys, same handlers) — the Next-beat launcher and inline interpret arrive in Tasks 3-4. It renders as a `Column` (not `ListView`) so it can sit above the journal feed.

**Files:**
- Create: `lib/features/loop_bar.dart`
- Delete: `lib/features/loop_pane.dart`
- Modify: `lib/shared/destination.dart`, `lib/shared/home_shell.dart:490-491`, `lib/features/tracking_tab.dart:9,36,51`, `lib/features/track_home_pane.dart:75`
- Rename test: `test/loop_pane_test.dart` → `test/loop_bar_test.dart`

- [ ] **Step 1: Create `loop_bar.dart` from `loop_pane.dart`**

Copy `lib/features/loop_pane.dart` to `lib/features/loop_bar.dart`. Then in the new file make exactly these changes:
- Rename class `LoopPane` → `LoopBar`, `_LoopPaneState` → `_LoopBarState`.
- Change the top-level widget's outer `ListView(...)` in `build` to `Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [...])` with the SAME children (a Column, because a `ListView` inside the Play `Column` would be unbounded).
- Wrap the 5 step-cards' Column in a `SingleChildScrollView` is NOT needed here (LoopBar is a compact header; the journal feed below scrolls). Keep the children list; the `_step` Cards stay.
- Add the `PlayScreen` wrapper widget at the bottom of the file:

```dart
/// The "Play" destination body: the loop controls above the live journal feed.
class PlayScreen extends StatelessWidget {
  const PlayScreen({super.key});
  @override
  Widget build(BuildContext context) => const Column(
        children: [
          LoopBar(),
          Expanded(child: JournalScreen()),
        ],
      );
}
```

- Add the import at the top of `loop_bar.dart`: `import 'journal_screen.dart';`

- [ ] **Step 2: Delete the old file**

```bash
git rm lib/features/loop_pane.dart
```

- [ ] **Step 3: Repoint the Play verb in the shell**

In `lib/shared/home_shell.dart`, add the import near the other feature imports:

```dart
import '../features/loop_bar.dart';
```

Change `_root`'s journal case (currently lines 490-491):

```dart
      case Destination.journal:
        return const PlayScreen();
```

Leave the split-view right pane (`const JournalScreen()`, ~line 575) and the `leftDest` journal exclusion unchanged — split view keeps the bare journal by design.

- [ ] **Step 4: Relabel the destination + shift party landing**

In `lib/shared/destination.dart`:

```dart
  Destination.journal: DestinationMeta('Play', Icons.auto_stories_outlined),
```

and

```dart
Destination landingDestination(CampaignMode mode) =>
    mode == CampaignMode.gm ? Destination.run : Destination.journal;
```

Add a comment above `landingDestination` noting party now lands on Play (the loop), superseding the party→Sheet landing.

- [ ] **Step 5: Drop the Track `loop` subtab**

In `lib/features/tracking_tab.dart`: remove the `import 'loop_pane.dart';` (line 9), remove `const SubtabDef('loop', 'Loop'),` (line 36), and remove the `const LoopPane(),` entry (line 51) — delete the matching subtab body entry so the `SubtabDef` list and the body list stay index-aligned. Verify the two lists have equal length after the edit.

In `lib/features/track_home_pane.dart`: remove the `('Loop', 'guided solo play'),` help line (line 75).

- [ ] **Step 6: Rename + repoint the loop test**

```bash
git mv test/loop_pane_test.dart test/loop_bar_test.dart
```

In `test/loop_bar_test.dart`: change the import to `import 'package:juice_oracle/features/loop_bar.dart';` and replace every `LoopPane()` with `LoopBar()`. The pump helper wraps it in `Scaffold(body: LoopBar())` — that stays valid (LoopBar is now a `Column` with `mainAxisSize.min`, so wrap it in a `SingleChildScrollView` in the test harness if a render-overflow occurs: `Scaffold(body: SingleChildScrollView(child: LoopBar()))`).

- [ ] **Step 7: Run the moved + shell tests**

Run: `flutter test test/loop_bar_test.dart test/tracking_tab_test.dart test/track_home_pane_test.dart test/home_shell_test.dart test/destination_test.dart`
Expected: loop_bar + tracking + track_home + home_shell PASS. `destination_test` may FAIL on the party-landing assertion — that's expected and fixed in Task 5. If any OTHER failure appears (e.g. a test that asserted a "Loop" subtab exists), note it for Task 5.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(loop): move Loop into a first-class Play surface (LoopBar + PlayScreen)"
```

---

## Task 3: Next-beat launcher in `LoopBar`

Add a prominent "Next beat" control above the step-cards, wired to `nextBeatActions`, and collapse the 5 step-cards under a "Steps" `ExpansionTile`.

**Files:**
- Modify: `lib/features/loop_bar.dart`
- Test: `test/loop_bar_test.dart`

- [ ] **Step 1: Write the failing widget test**

Add to `test/loop_bar_test.dart` (reuse the file's existing pump helper + provider overrides; if the helper lacks them, mirror `test/tracking_tab_test.dart`'s override list — journal/playContext/threads/ai providers):

```dart
  testWidgets('next-beat shows Name-the-scene when no scene', (tester) async {
    await tester.pumpWidget(app(const LoopBar())); // no active scene seeded
    await tester.tap(find.byKey(const Key('loop-next-beat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('beat-nameScene')), findsOneWidget);
    expect(find.byKey(const Key('beat-ask')), findsNothing);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/loop_bar_test.dart -n "next-beat shows"`
Expected: FAIL — no `loop-next-beat` key.

- [ ] **Step 3: Implement the launcher**

In `loop_bar.dart`, add `import '../engine/next_beat.dart';`. Add a file-private state provider next to the others:

```dart
final _loopBeatOpenProvider = StateProvider<bool>((_) => false);
final _loopInterpretedProvider = StateProvider<bool>((_) => false);
```

In `build`, compute the actions (using values already read in build — `scene`, `last`, `aiReady`):

```dart
    final interpreted = ref.watch(_loopInterpretedProvider);
    final beatOpen = ref.watch(_loopBeatOpenProvider);
    final actions = nextBeatActions(
      hasScene: scene != null,
      hasRecentAsk: last != null,
      interpretDone: interpreted,
      aiReady: aiReady,
    );
```

Insert at the TOP of the `Column` children (above the step cards), a "Next beat" button + the expanded action row:

```dart
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            FilledButton.icon(
              key: const Key('loop-next-beat'),
              icon: const Icon(Icons.bolt),
              label: const Text('Next beat'),
              onPressed: () => ref
                  .read(_loopBeatOpenProvider.notifier)
                  .update((v) => !v),
            ),
          ]),
        ),
        if (beatOpen)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              for (final a in actions)
                OutlinedButton.icon(
                  key: Key('beat-${a.name}'),
                  icon: Icon(_beatIcon(a)),
                  label: Text(_beatLabel(a)),
                  onPressed: () => _runBeat(a),
                ),
            ]),
          ),
```

Wrap the existing 5 step-cards (the current `_step(...)` calls + credit) in an `ExpansionTile`:

```dart
        ExpansionTile(
          key: const Key('loop-steps'),
          title: const Text('Steps'),
          initiallyExpanded: false,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            // ... the existing _step(...) cards + the loop-credit Text ...
          ],
        ),
```

Add the mapping + dispatch helpers:

```dart
  IconData _beatIcon(BeatAction a) => switch (a) {
        BeatAction.nameScene => Icons.add,
        BeatAction.ask || BeatAction.askAgain => Icons.help_outline,
        BeatAction.interpret => Icons.auto_awesome,
        BeatAction.inspire => Icons.lightbulb_outline,
        BeatAction.capture => Icons.edit_note,
      };

  String _beatLabel(BeatAction a) => switch (a) {
        BeatAction.nameScene => 'Name the scene',
        BeatAction.ask => 'Ask oracle',
        BeatAction.askAgain => 'Ask again',
        BeatAction.interpret => 'Interpret',
        BeatAction.inspire => 'Inspire',
        BeatAction.capture => 'Capture',
      };

  Future<void> _runBeat(BeatAction a) async {
    switch (a) {
      case BeatAction.nameScene:
        await _newScene();
      case BeatAction.ask:
      case BeatAction.askAgain:
        ref.read(_loopInterpretedProvider.notifier).state = false;
        await _ask();
      case BeatAction.interpret:
        await _interpret(); // becomes inline in Task 4
      case BeatAction.inspire:
        showGenerateSheet(context);
      case BeatAction.capture:
        FocusScope.of(context).requestFocus(_captureFocus);
    }
  }
```

Add `final _captureFocus = FocusNode();` as a field, dispose it in `dispose()`, and attach it to the capture `TextField` (`focusNode: _captureFocus`).

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/loop_bar_test.dart`
Expected: PASS (existing + the new next-beat test).

- [ ] **Step 5: Add a scene-present test, run, commit**

Add a test that seeds an active scene (mirror the seeding used elsewhere in the file — an `addScene` + `setActiveScene`, or a journal override with a scene entry) then asserts:

```dart
    await tester.tap(find.byKey(const Key('loop-next-beat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('beat-ask')), findsOneWidget);
    expect(find.byKey(const Key('beat-nameScene')), findsNothing);
```

Run: `flutter test test/loop_bar_test.dart` → PASS.

```bash
git add lib/features/loop_bar.dart test/loop_bar_test.dart
git commit -m "feat(loop): context-aware Next-beat launcher over collapsible steps"
```

---

## Task 4: Inline interpret card with Keep / Discard

Replace the loop's modal `_interpret` with an inline `_InterpretCard` rendered in the LoopBar. The card runs the interpreter directly and offers Keep (logs) / Discard (drops).

**Files:**
- Modify: `lib/features/loop_bar.dart`
- Test: `test/loop_bar_test.dart`

- [ ] **Step 1: Write the failing test**

Uses `FakeInterpreterService` (see `test/fake_interpreter.dart` + the override pattern in `test/oracle_interpretation_sheet_test.dart`). Enable AI via `SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': true})` and override `interpreterServiceProvider` with a ready fake. Seed an active scene and a prior ask (set `_loopLastProvider` by tapping `loop-ask`, or seed directly).

```dart
  testWidgets('interpret renders inline; Keep logs one entry', (tester) async {
    // ... pump LoopBar with AI-ready fake + active scene + a prior ask ...
    await tester.tap(find.byKey(const Key('loop-next-beat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('beat-interpret')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-interpret-card')), findsOneWidget);
    await tester.tap(find.byKey(const Key('loop-interpret-keep')));
    await tester.pumpAndSettle();
    // one 'interpret' journal entry now exists
    final journal = container.read(journalProvider).valueOrNull ?? const [];
    expect(journal.where((e) => e.sourceTool == 'interpret').length, 1);
  });
```

(Adapt `container`/seeding to the file's existing harness. If the harness has no `ProviderContainer` handle, assert via a visible journal entry in the feed instead — but the LoopBar test pumps `LoopBar` alone without the feed, so prefer a container read; add one to the harness if absent.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/loop_bar_test.dart -n "interpret renders inline"`
Expected: FAIL — no `loop-interpret-card`.

- [ ] **Step 3: Implement the inline card**

Add a file-private provider for the pending seed:

```dart
final _loopInterpretSeedProvider = StateProvider<OracleSeed?>((_) => null);
```

Change `_interpret` to seed the provider instead of opening the modal:

```dart
  void _interpret() {
    final last = ref.read(_loopLastProvider);
    if (last == null) return;
    final g = last.toGenResult();
    final journal =
        ref.read(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final ctx = ref.read(playContextProvider).valueOrNull;
    final scene = activeSceneEntry(journal, ctx?.activeSceneId);
    final settings =
        ref.read(settingsProvider).valueOrNull ?? const CampaignSettings();
    ref.read(_loopInterpretSeedProvider.notifier).state = OracleSeed(
      resultText: g.asText,
      genre: settings.genre,
      tone: settings.tone,
      sceneContext: scene == null ? '' : '${scene.title}\n${scene.body}'.trim(),
      activeCharacter: ref.read(activeCharacterLineProvider),
      systemPrimer: ref.read(systemPrimerProvider),
    );
  }
```

In `build`, render the card when a seed is pending — place it right below the beat-action row:

```dart
        if (ref.watch(_loopInterpretSeedProvider) case final seed?)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _InterpretCard(
              key: const Key('loop-interpret-card'),
              seed: seed,
              onDone: () {
                ref.read(_loopInterpretSeedProvider.notifier).state = null;
                ref.read(_loopInterpretedProvider.notifier).state = true;
              },
            ),
          ),
```

Add the widget (remove the old modal imports if now unused — keep `oracle_interpreter.dart`, drop `oracle_interpretation_sheet.dart`):

```dart
class _InterpretCard extends ConsumerStatefulWidget {
  const _InterpretCard({super.key, required this.seed, required this.onDone});
  final OracleSeed seed;
  final VoidCallback onDone;
  @override
  ConsumerState<_InterpretCard> createState() => _InterpretCardState();
}

class _InterpretCardState extends ConsumerState<_InterpretCard> {
  late Future<List<OracleInterpretation>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(interpreterServiceProvider).interpret(widget.seed);
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FutureBuilder<List<OracleInterpretation>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(
                    height: 48,
                    child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError || (snap.data?.isEmpty ?? true)) {
                return Row(children: [
                  const Expanded(child: Text('Reading failed.')),
                  TextButton(
                    key: const Key('loop-interpret-retry'),
                    onPressed: () => setState(() => _future = ref
                        .read(interpreterServiceProvider)
                        .interpret(widget.seed)),
                    child: const Text('Retry'),
                  ),
                  TextButton(
                    onPressed: widget.onDone,
                    child: const Text('Dismiss'),
                  ),
                ]);
              }
              final card = snap.data!.first;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('(${card.lens}): ${card.reading}'),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                      key: const Key('loop-interpret-discard'),
                      onPressed: widget.onDone,
                      child: const Text('Discard'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('loop-interpret-keep'),
                      onPressed: () async {
                        await ref.read(journalProvider.notifier).addResult(
                              'Oracle reading',
                              '(${card.lens}): ${card.reading}',
                              sourceTool: 'interpret',
                            );
                        widget.onDone();
                      },
                      child: const Text('Keep'),
                    ),
                  ]),
                ],
              );
            },
          ),
        ),
      );
}
```

Remove the now-unused `loop-interpret` OutlinedButton in step-2's card (the interpret path is the beat action + inline card now); keep `loop-ask-result`. Delete the old `_interpret` modal body you replaced.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/loop_bar_test.dart`
Expected: PASS.

- [ ] **Step 5: Add the Discard test, run, commit**

Add a sibling test: same setup, tap `loop-interpret-discard`, assert zero `interpret` entries and the card is gone (`find.byKey(const Key('loop-interpret-card'))` → `findsNothing`).

Run: `flutter test test/loop_bar_test.dart` → PASS.

```bash
git add lib/features/loop_bar.dart test/loop_bar_test.dart
git commit -m "feat(loop): inline oracle interpretation with Keep/Discard"
```

---

## Task 5: Landing/subtab test migration + full-suite verification

**Files:**
- Modify: `test/destination_test.dart`, `test/enter_campaign_test.dart`, `test/shell_route_test.dart`, and any test flagged in Task 2 Step 7 that asserted a Track "Loop" subtab or a party→Sheet landing.

- [ ] **Step 1: Update the party-landing assertions**

In `test/destination_test.dart` (and any sibling asserting the same), change the expected party landing:

```dart
    expect(landingDestination(CampaignMode.party), Destination.journal);
```

Search the test suite for `Destination.sheet` used as the *party landing* expectation and update those specific assertions (do NOT change unrelated `Destination.sheet` navigation tests). Grep:

Run: `grep -rn "landingDestination(CampaignMode.party)\|landFor" test/`

Update each party-landing expectation to `Destination.journal`.

- [ ] **Step 2: Remove any Track "Loop" subtab assertions**

Run: `grep -rn "'Loop'\|\"Loop\"\|SubtabDef('loop'" test/`

For any test asserting a Track subtab named "Loop" (e.g. in `test/tracking_tab_test.dart` / `test/track_home_pane_test.dart`), delete or update that assertion — the subtab is gone. Leave the LoopBar tests untouched.

- [ ] **Step 3: Run the full suite**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and `All tests passed!`. If a test fails, fix it in place (it is almost certainly a stale Loop-subtab or party-landing assertion, or a render-overflow in a harness that pumped `LoopBar` without a scroll parent — wrap in `SingleChildScrollView`).

- [ ] **Step 4: Device smoke check (macOS)**

Run: `flutter run -d macos` (or the project's usual launch). Manually verify: a party campaign opens on **Play**; the LoopBar shows **Next beat**; tapping it with no scene offers **Name the scene**; after a scene + Ask, **Interpret** (AI on) renders an inline card with **Keep/Discard**; the journal feed sits below and updates. Note any issues; fix and re-run the suite.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "test(loop): migrate landing + subtab assertions to the Play surface"
```

---

## Self-Review Notes

- **Spec coverage:** Play verb (T2), pure `nextBeatActions` (T1), Next-beat menu (T3), inline interpret + Keep/Discard (T4), party landing (T2/T5), Loop subtab removal (T2), nav-surviving providers incl. `_loopInterpretedProvider`/`_loopInterpretSeedProvider` (T3/T4), testing (all). Covered.
- **Retained:** `OracleInterpretationSheet` unchanged for Run + journal callers (only the loop path goes inline).
- **Naming:** `nextBeatActions`, `BeatAction`, `PlayScreen`, `LoopBar`, keys `loop-next-beat`/`beat-<action>`/`loop-interpret-card`/`loop-interpret-keep`/`loop-interpret-discard`/`loop-steps` used consistently across tasks.
- **Known drift (per spec):** enum id stays `Destination.journal` while presenting as "Play" — deliberate, documented, mechanical rename deferred.
