# Tracking Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge Threads, Tracks, and Rumors into one `Thread` entity with a `ThreadStage`, rendered by one unified pane; the Rumors and Tracks panes, models, and providers are deleted.

**Architecture:** `Thread` gains a `stage` enum (`rumor`/`active`/`done`) that replaces its `open` bool as source of truth; a derived `bool get open` keeps the ~15 existing readers compiling unchanged. `Rumor` and `Track` are absorbed (rumor text→title, track filled/max→progress/progressMax) and deleted along with their providers, panes, and storage keys. All consumers (Run panel, search, suggestions, lonelog import/export, home/help cards) re-point to `threadsProvider`.

**Tech Stack:** Flutter + flutter_riverpod + shared_preferences. Tests: `flutter test` (widget + unit), `flutter analyze`.

**Spec:** `docs/superpowers/specs/2026-08-22-tracking-merge-design.md`

## Global Constraints

- Prefs keys are `loreseer.*` (the spec's `juice.*` names are the legacy spelling; the code uses `loreseer.threads.v1`, `loreseer.rumors.v1`, `loreseer.tracks.v1`).
- Threads stay under `loreseer.threads.v1`. No new storage key.
- Fresh start: `loreseer.rumors.v1` / `loreseer.tracks.v1` data is NOT migrated. The keys leave `sessionScopedKeys`.
- Existing persisted threads must keep loading: legacy JSON `open:false` reads as stage `done`, otherwise `active`.
- An `active`-stage thread's `toJson` must omit the `stage` key (repo convention: JSON omits defaults).
- Colors come from `JuiceTokens` via `context.lore` — never add `ColorScheme` uses (design ratchet).
- Format only the files you edit (`dart format <file>`), never the whole repo.
- Tests never construct `GemmaInterpreterService`; widget tests pumping providers need `SharedPreferences.setMockInitialValues`.
- Each task ends with `flutter analyze` clean on touched files and its tests green, then a commit.

---

### Task 1: `ThreadStage` on the model

**Files:**
- Modify: `lib/engine/models/journal.dart:190-262` (class `Thread`)
- Test: `test/thread_stage_test.dart` (create)

**Interfaces:**
- Produces: `enum ThreadStage { rumor, active, done }`; `Thread.stage` (`ThreadStage`, default `active`); derived `bool get open => stage != ThreadStage.done;`; `Thread.copyWith({... ThreadStage? stage ...})`. The `open` constructor parameter and stored field are gone.
- Consumers keep using `t.open` (read-only) everywhere; only `lib/engine/lonelog_import.dart:159-163` and `lib/state/providers.dart:400-405` (`toggleOpen`) construct with `open:` — they are fixed in Tasks 2 and 8. To keep the repo compiling after this task, Task 1 also updates those two call sites (see Step 3).

- [ ] **Step 1: Write the failing test**

Create `test/thread_stage_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('stage round-trips through JSON and omits the default', () {
    final rumor = Thread(id: 't1', title: 'Heard a noise', stage: ThreadStage.rumor);
    final json = rumor.toJson();
    expect(json['stage'], 'rumor');
    expect(Thread.fromJson(json).stage, ThreadStage.rumor);

    final active = Thread(id: 't2', title: 'Find the sword');
    expect(active.toJson().containsKey('stage'), isFalse);
    expect(active.toJson().containsKey('open'), isFalse);
    expect(Thread.fromJson(active.toJson()).stage, ThreadStage.active);
  });

  test('legacy open:false reads as done, open:true as active', () {
    expect(
        Thread.fromJson({'id': 'a', 'title': 'x', 'open': false}).stage,
        ThreadStage.done);
    expect(
        Thread.fromJson({'id': 'b', 'title': 'y', 'open': true}).stage,
        ThreadStage.active);
  });

  test('open getter derives from stage', () {
    expect(Thread(id: 'a', title: 'x', stage: ThreadStage.rumor).open, isTrue);
    expect(Thread(id: 'b', title: 'y').open, isTrue);
    expect(Thread(id: 'c', title: 'z', stage: ThreadStage.done).open, isFalse);
  });

  test('copyWith changes stage and keeps everything else', () {
    final t = Thread(id: 'a', title: 'x', note: 'n', pinned: true, progress: 3);
    final done = t.copyWith(stage: ThreadStage.done);
    expect(done.stage, ThreadStage.done);
    expect(done.note, 'n');
    expect(done.pinned, isTrue);
    expect(done.progress, 3);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/thread_stage_test.dart`
Expected: compile FAIL — `ThreadStage` undefined, no `stage` parameter.

- [ ] **Step 3: Implement the model change**

In `lib/engine/models/journal.dart`, immediately above `class Thread`:

```dart
/// Lifecycle stage of a tracked thread. A rumor is an unconfirmed lead
/// (the old Rumor entity); active is a live storyline or clock (the old
/// Thread/Track); done is finished either way.
enum ThreadStage { rumor, active, done }

ThreadStage _threadStageFromJson(Map<String, dynamic> j) {
  switch (j['stage']) {
    case 'rumor':
      return ThreadStage.rumor;
    case 'done':
      return ThreadStage.done;
    case 'active':
      return ThreadStage.active;
  }
  // Legacy shape: an explicit open:false was a closed thread.
  return (j['open'] as bool?) == false ? ThreadStage.done : ThreadStage.active;
}
```

Change `Thread` itself:

- Constructor: remove `this.open = true`, add `this.stage = ThreadStage.active`.
- Fields: remove `final bool open;`, add `final ThreadStage stage;` and the derived getter:

```dart
  final ThreadStage stage;

  /// Derived: true while the thread is not finished (rumor or active).
  bool get open => stage != ThreadStage.done;
```

- `copyWith`: remove `bool? open`, add `ThreadStage? stage`; body maps `stage: stage ?? this.stage` (drop the `open` line).
- `toJson`: remove `'open': open,`; add `if (stage != ThreadStage.active) 'stage': stage.name,`.
- `fromJson`: remove the `open:` line; add `stage: _threadStageFromJson(j),`.

Fix the two `open:`-constructing call sites so the repo compiles:

`lib/state/providers.dart:400-405` — replace `toggleOpen` body:

```dart
  Future<void> toggleOpen(String id) async {
    await _persist([
      for (final t in await _ready)
        if (t.id == id)
          t.copyWith(
              stage: t.stage == ThreadStage.done
                  ? ThreadStage.active
                  : ThreadStage.done)
        else
          t,
    ]);
  }
```

`lib/engine/lonelog_import.dart:159-163` — replace the `open:` argument:

```dart
    threads.add(Thread(
      id: 'll-thread-${threads.length}',
      title: th.group(1)!.trim(),
      stage: th.group(2) == 'Open' ? ThreadStage.active : ThreadStage.done,
    ));
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/thread_stage_test.dart && flutter analyze lib/engine/models/journal.dart lib/state/providers.dart lib/engine/lonelog_import.dart`
Expected: PASS, no analyzer issues.

Also run the neighbors that exercise threads: `flutter test test/thread_tally_test.dart test/thread_backlink_test.dart`
Expected: PASS (the derived `open` getter keeps them green).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models/journal.dart lib/state/providers.dart lib/engine/lonelog_import.dart test/thread_stage_test.dart
git commit -m "feat(track): ThreadStage on Thread; open becomes a derived getter"
```

---

### Task 2: Notifier stage operations

**Files:**
- Modify: `lib/state/providers.dart:372-449` (class `ThreadNotifier`)
- Test: `test/thread_stage_notifier_test.dart` (create)

**Interfaces:**
- Consumes: `ThreadStage`, `Thread.copyWith(stage:)` from Task 1.
- Produces: `ThreadNotifier.add(String title, {ThreadStage stage = ThreadStage.active})`; `ThreadNotifier.addReturningId(String title, {ThreadStage stage = ThreadStage.active})`; `ThreadNotifier.setStage(String id, ThreadStage stage)`. Existing methods (`replace`, `toggleOpen`, `togglePinned`, `setProgress`, tally methods, `remove`, `restoreAt`) unchanged.

- [ ] **Step 1: Write the failing test**

Create `test/thread_stage_notifier_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('add with stage, setStage promotes a rumor', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(threadsProvider.notifier);

    final id = await notifier.addReturningId('Strange lights',
        stage: ThreadStage.rumor);
    var threads = await container.read(threadsProvider.future);
    expect(threads.single.stage, ThreadStage.rumor);

    await notifier.setStage(id, ThreadStage.active);
    threads = await container.read(threadsProvider.future);
    expect(threads.single.stage, ThreadStage.active);
  });

  test('toggleOpen flips active<->done and closes a rumor', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(threadsProvider.notifier);

    final id =
        await notifier.addReturningId('Lead', stage: ThreadStage.rumor);
    await notifier.toggleOpen(id);
    var threads = await container.read(threadsProvider.future);
    expect(threads.single.stage, ThreadStage.done);

    await notifier.toggleOpen(id);
    threads = await container.read(threadsProvider.future);
    expect(threads.single.stage, ThreadStage.active);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/thread_stage_notifier_test.dart`
Expected: compile FAIL — `add`/`addReturningId` take no `stage`, `setStage` undefined.

- [ ] **Step 3: Implement**

In `ThreadNotifier` (`lib/state/providers.dart:380-391`), change the two adders and append `setStage`:

```dart
  Future<void> add(String title,
      {ThreadStage stage = ThreadStage.active}) async {
    await _persist([
      Thread(id: _newId(), title: title, stage: stage),
      ...await _ready,
    ]);
  }

  Future<String> addReturningId(String title,
      {ThreadStage stage = ThreadStage.active}) async {
    final id = _newId();
    await _persist(
        [Thread(id: id, title: title, stage: stage), ...await _ready]);
    return id;
  }

  /// Moves thread [id] to [stage] (rumor confirmation, completion, reopen).
  Future<void> setStage(String id, ThreadStage stage) async {
    final thread = (await _ready).where((t) => t.id == id).firstOrNull;
    if (thread == null) return;
    await replace(thread.copyWith(stage: stage));
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/thread_stage_notifier_test.dart test/thread_tally_test.dart && flutter analyze lib/state/providers.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/thread_stage_notifier_test.dart
git commit -m "feat(track): ThreadNotifier stage ops (add stage, setStage)"
```

---

### Task 3: Unified ThreadsPane

**Files:**
- Modify: `lib/features/tracker_screen.dart:75-395` (class `ThreadsPane`)
- Test: `test/threads_pane_stage_test.dart` (create)

**Interfaces:**
- Consumes: `ThreadStage`, `setStage`, `add(stage:)` from Tasks 1–2; existing `ThreadTallyRow`, `_EditDialog`, `buildFleshOutSeed`, `showUndoSnackbar`.
- Produces: widget keys other tasks/tests rely on — filter chips `thread-stage-all` / `thread-stage-rumor` / `thread-stage-active` / `thread-stage-done`; per-row confirm `thread-confirm-<id>`; header button `rumor-new`. Existing keys (`task-new`, `thread-prog-dec/inc-<id>`, `thread-entries-<id>`, `flesh-out-thread-<id>`, `pin-thread-<id>`) unchanged.

- [ ] **Step 1: Write the failing widget test**

Create `test/threads_pane_stage_test.dart`. Follow the harness style of `test/thread_tally_test.dart` (mock prefs seeded with a threads list, `ProviderScope` + `MaterialApp(home: ThreadsPane())`); seed `loreseer.sessions.v1` the same way that file does (copy its setup block verbatim).

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/tracker_screen.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ThreadsPane()))));
    await tester.pumpAndSettle();
  }

  void seed(List<Thread> threads) {
    SharedPreferences.setMockInitialValues({
      'loreseer.threads.v1.default':
          jsonEncode(threads.map((t) => t.toJson()).toList()),
      'loreseer.sessions.v1': jsonEncode({
        'active': 'default',
        'sessions': [
          {'id': 'default', 'name': 'Campaign 1'}
        ],
      }),
    });
  }

  testWidgets('stage filter chips narrow the list', (tester) async {
    seed([
      Thread(id: 'r1', title: 'Whispered lead', stage: ThreadStage.rumor),
      Thread(id: 'a1', title: 'Main quest'),
      Thread(id: 'd1', title: 'Old business', stage: ThreadStage.done),
    ]);
    await pump(tester);

    expect(find.text('Whispered lead'), findsOneWidget);
    expect(find.text('Main quest'), findsOneWidget);

    await tester.tap(find.byKey(const Key('thread-stage-rumor')));
    await tester.pumpAndSettle();
    expect(find.text('Whispered lead'), findsOneWidget);
    expect(find.text('Main quest'), findsNothing);
    expect(find.text('Old business'), findsNothing);
  });

  testWidgets('confirm promotes a rumor to active', (tester) async {
    seed([Thread(id: 'r1', title: 'Whispered lead', stage: ThreadStage.rumor)]);
    await pump(tester);

    await tester.tap(find.byKey(const Key('thread-confirm-r1')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byType(ThreadsPane)));
    final threads = await container.read(threadsProvider.future);
    expect(threads.single.stage, ThreadStage.active);
    expect(find.byKey(const Key('thread-confirm-r1')), findsNothing);
  });

  testWidgets('New rumor button creates a rumor-stage thread',
      (tester) async {
    seed([]);
    await pump(tester);

    await tester.tap(find.byKey(const Key('rumor-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Heard in the tavern');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byType(ThreadsPane)));
    final threads = await container.read(threadsProvider.future);
    expect(threads.single.stage, ThreadStage.rumor);
    expect(threads.single.title, 'Heard in the tavern');
  });
}
```

Adjust the dialog-save tap (`find.text('Save')`) to the actual `_EditDialog` confirm label after reading it (`lib/features/tracker_screen.dart`, class `_EditDialog`) — use its real button text.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/threads_pane_stage_test.dart`
Expected: FAIL — keys `thread-stage-*`, `thread-confirm-*`, `rumor-new` not found.

- [ ] **Step 3: Implement pane changes**

In `ThreadsPane` (`lib/features/tracker_screen.dart`):

1. Convert to `ConsumerStatefulWidget` holding `ThreadStage? _filter` (null = All). (State is view-only; no persistence.)
2. Header row (currently only `task-new`, lines 96-115): add a `rumor-new` tonal button before `task-new` and a filter `Wrap` of `ChoiceChip`s under the header:

```dart
FilledButton.tonalIcon(
  key: const Key('rumor-new'),
  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
  icon: const Icon(Icons.hearing_outlined),
  label: const Text('New rumor'),
  onPressed: () => _editThread(context, ref, null, stage: ThreadStage.rumor),
),
```

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
  child: Wrap(
    spacing: 8,
    children: [
      for (final (label, stage) in [
        ('All', null),
        ('Rumors', ThreadStage.rumor),
        ('Active', ThreadStage.active),
        ('Done', ThreadStage.done),
      ])
        ChoiceChip(
          key: Key('thread-stage-${stage?.name ?? 'all'}'),
          label: Text(label),
          selected: _filter == stage,
          onSelected: (_) => setState(() => _filter = stage),
        ),
    ],
  ),
),
```

(Selection logic: `_filter == stage` covers the All chip too, because All's `stage` is null.)

3. List filtering: `final shown = _filter == null ? threads : threads.where((t) => t.stage == _filter).toList();` — build rows from `shown`. Keep the empty-list early-return only for `threads.isEmpty`; when the FILTER empties the list, show a centered `Text('Nothing at this stage.')` under the chips instead of the whole-pane empty state (the chips must stay tappable).
4. Row changes:
   - Rumor badge: when `t.stage == ThreadStage.rumor`, prefix the title row with a compact chip-like label `Text('RUMOR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: tk.inkMuted))` (simplest: a `Row` of the label + title).
   - Confirm button in the trailing icon row, first position, only for rumor-stage:

```dart
if (t.stage == ThreadStage.rumor)
  IconButton(
    key: Key('thread-confirm-${t.id}'),
    visualDensity: VisualDensity.compact,
    icon: const Icon(Icons.check_circle_outline),
    tooltip: 'Confirm — promote to active',
    onPressed: () =>
        ref.read(threadsProvider.notifier).setStage(t.id, ThreadStage.active),
  ),
```

   - The leading `Checkbox` keeps working (`value: !t.open`, `toggleOpen`) — no change.
5. `_editThread` gains `{ThreadStage stage = ThreadStage.active}`; the create branch (line 381-389) becomes:

```dart
    if (existing == null) {
      final id = await notifier.addReturningId(result.title.trim(), stage: stage);
      if (result.note.trim().isNotEmpty) {
        final added = (ref.read(threadsProvider).valueOrNull ?? const <Thread>[])
            .where((t) => t.id == id)
            .firstOrNull;
        if (added != null) {
          await notifier.replace(added.copyWith(note: result.note.trim()));
        }
      }
    }
```

   (This also fixes the latent `.first` bug — the old code grabbed the list head instead of the added id. Dialog heading: `stage == ThreadStage.rumor ? 'New rumor' : 'New Thread'` when creating.)
6. `_fleshOutThread` (line 335-338): seed `entityKind: t.stage == ThreadStage.rumor ? 'rumor' : 'story thread'` — the rumor flesh-out affordance now lives here.
7. FAB unchanged (creates an active thread).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/threads_pane_stage_test.dart test/thread_tally_test.dart test/thread_backlink_test.dart test/track_consolidation_test.dart && flutter analyze lib/features/tracker_screen.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/tracker_screen.dart test/threads_pane_stage_test.dart
git commit -m "feat(track): unified ThreadsPane — stage filter, rumor create/confirm"
```

---

### Task 4: Retire the Rumors and Tracks panes

**Files:**
- Modify: `lib/features/tracking_tab.dart`
- Delete: `lib/features/rumors_pane.dart`, `lib/features/tracks_pane.dart`
- Delete: `test/rumors_pane_test.dart`, `test/tracks_pane_test.dart`
- Modify: `test/tracking_tab_test.dart`

**Interfaces:**
- Consumes: unified `ThreadsPane` from Task 3.
- Produces: Track verb subtab set without `rumors`/`tracks`; `threads` subtab aliases `['tasks', 'rumors', 'tracks']`.

- [ ] **Step 1: Update the failing tab test first**

In `test/tracking_tab_test.dart`: remove assertions that a `Rumors`/`Tracks` tab exists; add:

```dart
  testWidgets('legacy rumors/tracks routes land on Threads', (tester) async {
    // Use this file's existing pump harness. Navigate via
    // shellRouteProvider.goTo(Destination.track, subtab: 'rumors') and expect
    // the ThreadsPane to be the visible child; repeat for 'tracks'.
  });
```

Model the navigation assertions on how this test file already drives subtabs (it exercises `SubtabDef.aliases` for `tasks`/`people`/`places`); clone that pattern for `rumors` and `tracks`.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/tracking_tab_test.dart`
Expected: FAIL (aliases not present yet).

- [ ] **Step 3: Implement**

`lib/features/tracking_tab.dart`:

- Delete imports of `rumors_pane.dart` and `tracks_pane.dart`.
- Delete `const rumors = true;` (line 26).
- Tabs list: remove `if (rumors) const SubtabDef('rumors', 'Rumors'),` and `const SubtabDef('tracks', 'Tracks'),`; change the threads entry to:

```dart
        const SubtabDef('threads', 'Threads',
            aliases: ['tasks', 'rumors', 'tracks']),
```

- Children list: remove `if (rumors) const RumorsPane(),` and `const TracksPane(),`.

Delete the four files:

```bash
git rm lib/features/rumors_pane.dart lib/features/tracks_pane.dart test/rumors_pane_test.dart test/tracks_pane_test.dart
```

If anything else still imports the deleted panes, `flutter analyze` names it — those consumers are handled in Tasks 5–7; if one bites now (it should not — grep showed only `tracking_tab.dart` imports them), fix the import in this task.

- [ ] **Step 4: Run tests**

Run: `flutter test test/tracking_tab_test.dart && flutter analyze lib/features/tracking_tab.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A lib/features/tracking_tab.dart test/tracking_tab_test.dart
git commit -m "feat(track): retire Rumors + Tracks panes; legacy routes alias to Threads"
```

---

### Task 5: Campaign search drops rumor/track kinds

**Files:**
- Modify: `lib/engine/campaign_search.dart`
- Modify: `lib/features/campaign_search_sheet.dart`
- Modify: `test/campaign_search_test.dart`, `test/campaign_search_sheet_test.dart`

**Interfaces:**
- Consumes: `Thread.stage` from Task 1.
- Produces: `SearchResultKind` without `rumor`/`track`; `searchCampaign` without the `rumors:`/`tracks:` parameters. Thread hits carry subtab `threads` (unchanged).

- [ ] **Step 1: Update the failing engine test**

In `test/campaign_search_test.dart`: delete cases that pass `rumors:`/`tracks:` lists and assert `SearchResultKind.rumor`/`.track`. Add:

```dart
  test('rumor-stage threads are found as threads', () {
    final results = searchCampaign('whisper', threads: [
      Thread(id: 'r1', title: 'Whispered lead', stage: ThreadStage.rumor),
    ]);
    expect(results.single.kind, SearchResultKind.thread);
    expect(results.single.subtab, 'threads');
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/campaign_search_test.dart`
Expected: FAIL (old cases removed, engine still exposes the kinds — the new test compiles but the file's removed params force the engine change).

- [ ] **Step 3: Implement**

`lib/engine/campaign_search.dart`:

- `SearchResultKind`: remove `rumor,` and `track,` (line 15-16).
- `searchCampaign`: remove the `rumors`/`tracks` parameters (lines 56-57) and both loops (lines 100-124). Update the doc comment (line 51) to "then threads, characters, places, NPCs".

`lib/features/campaign_search_sheet.dart`:

- Remove the `rumorsProvider`/`tracksProvider` watches (lines 56-57) and the `rumors:`/`tracks:` arguments (lines 66-67).
- `_kindLabel` / `_kindIcon` switches: delete the `rumor` and `track` arms (the enum shrank; the analyzer flags leftover arms).
- Update the class doc comment (line 19) and the "five entity lists" comment (line 108).

- [ ] **Step 4: Run tests**

Run: `flutter test test/campaign_search_test.dart test/campaign_search_sheet_test.dart && flutter analyze lib/engine/campaign_search.dart lib/features/campaign_search_sheet.dart`
Expected: PASS after pruning the sheet test's rumor/track rows the same way.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/campaign_search.dart lib/features/campaign_search_sheet.dart test/campaign_search_test.dart test/campaign_search_sheet_test.dart
git commit -m "feat(track): campaign search — staged threads only, rumor/track kinds retired"
```

---

### Task 6: Run screen threads panel

**Files:**
- Modify: `lib/features/run_screen.dart:496-562` (`_ThreadsRumorsPanel`)
- Modify: `test/run_screen_test.dart`

**Interfaces:**
- Consumes: `Thread.stage` from Task 1.
- Produces: `_ThreadsPanel` (renamed) reading only `threadsProvider`; keys `run-thread-<id>` (active) and `run-rumor-<id>` (rumor-stage) kept; both navigate to subtab `threads`.

- [ ] **Step 1: Update the failing test**

In `test/run_screen_test.dart`, find the threads-panel cases. Replace rumor seeding (`loreseer.rumors.v1...`) with rumor-stage threads in `loreseer.threads.v1...`; assert `run-rumor-<id>` rows render under the RUMORS header and tapping one navigates to Track subtab `threads`.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/run_screen_test.dart`
Expected: FAIL — panel still reads `rumorsProvider`, rumor rows navigate to `rumors`.

- [ ] **Step 3: Implement**

In `_ThreadsRumorsPanel.build` (rename class to `_ThreadsPanel`; update the construction site at line 46):

```dart
    final all = ref.watch(threadsProvider).valueOrNull ?? const <Thread>[];
    final threads =
        all.where((t) => t.stage == ThreadStage.active).toList();
    final rumors = all.where((t) => t.stage == ThreadStage.rumor).toList();
```

- Remove the `rumorsProvider` watch.
- The rumor rows keep `key: Key('run-rumor-${r.id}')` but display `r.title` and navigate `subtab: 'threads'`.
- Doc comment (line 496-497): "Read-only glance at the live plot: active threads plus unconfirmed rumors."

- [ ] **Step 4: Run tests**

Run: `flutter test test/run_screen_test.dart && flutter analyze lib/features/run_screen.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/run_screen.dart test/run_screen_test.dart
git commit -m "feat(run): threads panel reads staged threads only"
```

---

### Task 7: Home card, help card, suggestions target

**Files:**
- Modify: `lib/features/track_home_pane.dart`
- Modify: `lib/features/assistant_rail.dart:149-150`
- Modify: `test/track_home_pane_test.dart`, `test/suggestion_chips_test.dart` (only if it asserts the `develop-rumor` target subtab)

**Interfaces:**
- Consumes: `Thread.stage` from Task 1.
- Produces: no tracks card on Track home; `develop-rumor` chip navigates to subtab `threads`.

- [ ] **Step 1: Update the failing tests**

`test/track_home_pane_test.dart`: remove tracks-card assertions (`track-home-tracks`-style keys — read the file for the exact key, it is built by `_tracksCard`); keep threads-card cases. If the help card lines are asserted, update to the new copy below.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/track_home_pane_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

`lib/features/track_home_pane.dart`:

- Remove the `tracksProvider` watch (line 29) and `_tracksCard(context, ref, tracks),` (line 40); delete the `_tracksCard` method.
- Help-card `lines` (lines 74-81) become:

```dart
    const lines = <(String, String)>[
      ('Scenes', 'story beats'),
      ('Threads', 'rumors, storylines, tasks, clocks'),
      ('Encounter', 'combat'),
      ('World', 'people and places'),
    ];
```

- Update the class doc comment (line 12) to drop "tracks".

`lib/features/assistant_rail.dart:149-150`:

```dart
      case 'develop-rumor':
        route.goTo(Destination.track, subtab: 'threads');
```

(The `rumors` alias would still resolve, but pointing at the real subtab keeps grep honest.)

- [ ] **Step 4: Run tests**

Run: `flutter test test/track_home_pane_test.dart test/suggestion_chips_test.dart test/suggestions_test.dart test/suggestions_provider_test.dart && flutter analyze lib/features/track_home_pane.dart lib/features/assistant_rail.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/track_home_pane.dart lib/features/assistant_rail.dart test/track_home_pane_test.dart test/suggestion_chips_test.dart
git commit -m "feat(track): home + suggestions point at unified Threads"
```

---

### Task 8: Lonelog notation maps to staged threads

**Files:**
- Modify: `lib/engine/lonelog_export.dart`
- Modify: `lib/engine/lonelog_import.dart`
- Modify: `lib/state/providers.dart:2873+` (`exportActiveAsLonelog`), `:2970-2995` (lonelog import writer)
- Modify: `lib/shared/home_shell.dart` (lonelog export/import call sites — grep `campaignToLonelog` / `LonelogDoc`)
- Modify: `test/lonelog_export_test.dart`, `test/lonelog_import_test.dart`

**Interfaces:**
- Consumes: `ThreadStage` from Task 1.
- Produces: `campaignToLonelog` without the `tracks:` parameter — `[Track:title n/m]` lines are emitted from threads with `progress > 0`; `LonelogDoc` without the `tracks` field — an imported `[Track:name n/m]` becomes a clock thread, merged by title onto an already-parsed `[Thread:]` when titles match.

The `[Thread:]` / `[Track:]` notation itself is EXTERNAL and unchanged — only the mapping to the model changes.

- [ ] **Step 1: Update the failing tests**

`test/lonelog_export_test.dart`: drop the `tracks:` argument; add a thread with `progress: 3, progressMax: 6` and expect BOTH lines for it:

```dart
    expect(out, contains('[Thread:Main quest|Open]'));
    expect(out, contains('[Track:Main quest 3/6]'));
```

And a plain thread (progress 0) emits only its `[Thread:]` line.

`test/lonelog_import_test.dart`: remove `doc.tracks` expectations. `[Track:Supplies 2/6]` alone imports as a thread with `progress 2 / progressMax 6`; a doc containing both `[Thread:Main quest|Open]` and `[Track:Main quest 3/6]` imports as ONE thread with the clock set.

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/lonelog_export_test.dart test/lonelog_import_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

`lib/engine/lonelog_export.dart`:

- Remove `required List<Track> tracks,` from `campaignToLonelog`.
- Replace the tracks loop (lines 40-42) with:

```dart
  for (final t in threads.where((t) => t.progress > 0)) {
    buf.writeln('[Track:${_tag(t.title)} ${t.progress}/${t.progressMax}]');
  }
```

`lib/engine/lonelog_import.dart`:

- `LonelogDoc`: remove the `tracks` field and constructor param.
- `_parseTag`: drop the `List<Track> tracks` parameter. The `[Track:]` branch becomes:

```dart
  final tr = _trackRe.firstMatch(line);
  if (tr != null) {
    final name = tr.group(1)!.trim();
    final filled = int.parse(tr.group(2)!);
    final max = int.parse(tr.group(3)!);
    final i = threads.indexWhere((t) => t.title == name);
    if (i >= 0) {
      threads[i] =
          threads[i].copyWith(progress: filled, progressMax: max);
    } else {
      threads.add(Thread(
        id: 'll-track-${threads.length}',
        title: name,
        progress: filled,
        progressMax: max,
      ));
    }
    return;
  }
```

  (`copyWith` order matters: `Thread`'s constructor clamps progress against `progressMax`, and `copyWith` passes both together — setting them in one call is safe.)
- Remove the now-unused `tracks` locals and argument threading in the parse loop.

`lib/state/providers.dart`:

- `exportActiveAsLonelog` (line 2873+): delete the `tracksProvider` read (line 2878) and the `tracks:` argument.
- Lonelog import writer (lines 2981-2989): delete the `'loreseer.tracks.v1'` entry.

`lib/shared/home_shell.dart`: fix any call sites the analyzer flags for the changed signatures.

- [ ] **Step 4: Run tests**

Run: `flutter test test/lonelog_export_test.dart test/lonelog_import_test.dart test/lonelog_campaign_ui_test.dart && flutter analyze lib/engine/lonelog_export.dart lib/engine/lonelog_import.dart lib/state/providers.dart lib/shared/home_shell.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/lonelog_export.dart lib/engine/lonelog_import.dart lib/state/providers.dart lib/shared/home_shell.dart test/lonelog_export_test.dart test/lonelog_import_test.dart
git commit -m "feat(lonelog): [Track:] notation maps to clock threads"
```

---

### Task 9: Delete Rumor/Track models + providers; final sweep

**Files:**
- Modify: `lib/engine/models/world.dart` (delete class `Rumor`, lines 84-118; delete class `Track`, lines 294+)
- Modify: `lib/state/providers.dart` (delete `RumorNotifier` at 677+, `TrackNotifier` at 863+, `rumorsProvider`, `tracksProvider`; remove `loreseer.rumors.v1` and `loreseer.tracks.v1` from `sessionScopedKeys` at 2650/2653)
- Delete: `test/models_rumor_track_test.dart`, `test/rumors_provider_test.dart`, `test/tracks_provider_test.dart`
- Modify: `CLAUDE.md` (project notes)

**Interfaces:**
- Consumes: Tasks 4–8 having removed every reader. This task is pure deletion; nothing new is produced.

- [ ] **Step 1: Delete models and providers**

- `lib/engine/models/world.dart`: remove class `Rumor` (with its doc comment) and class `Track`.
- `lib/state/providers.dart`: remove `RumorNotifier` + `rumorsProvider`, `TrackNotifier` + `tracksProvider`, and the two keys from `sessionScopedKeys`. (Leaving the keys out of `sessionScopedKeys` means campaign delete/export no longer touches them — fresh-start posture; stale per-session blobs are inert.)

```bash
git rm test/models_rumor_track_test.dart test/rumors_provider_test.dart test/tracks_provider_test.dart
```

- [ ] **Step 2: Prove zero references**

Run: `grep -rn "Rumor\b\|rumorsProvider\|\bTrack(\|tracksProvider\|RumorsPane\|TracksPane" lib test --include="*.dart" | grep -v "ProgressTrack\|CharTrack\|track_home\|TrackingTab\|Destination.track\|SubtabDef\|subtab\|thread"`
Expected: no hits in `lib/` (eyeball any residue — comments mentioning the old panes are fine to update, code references are not). Then:

Run: `flutter analyze`
Expected: clean.

- [ ] **Step 3: Full suite**

Run: `flutter test`
Expected: green. If a test fails, read the final "Failing tests:" block (never the `+P -F:` progress lines) to attribute it; any failure here is caused by this work until a worktree baseline proves otherwise.

- [ ] **Step 4: Update CLAUDE.md**

In `CLAUDE.md` Project notes, add one bullet at the top (normal prose, follow the existing bullet style):

> **Tracking merge (2026-08-22, consolidation epic sub-project 1)** — Threads, Tracks, and Rumors are ONE entity: `Thread` carries `ThreadStage {rumor, active, done}` (JSON `stage`, omitted at active; legacy `open:false` reads as done; `open` is now a derived getter). `Rumor`/`Track` models, `rumorsProvider`/`tracksProvider`, `RumorsPane`/`TracksPane`, and the `loreseer.rumors.v1`/`loreseer.tracks.v1` keys are DELETED (fresh start, no data migration). Unified `ThreadsPane`: stage filter chips, `rumor-new`, `thread-confirm-<id>` promotion; legacy `rumors`/`tracks` subtab routes alias to `threads`. Lonelog `[Track:name n/m]` now maps to clock threads (export emits it from `progress > 0`, import merges by title). See `docs/superpowers/specs/2026-08-22-tracking-merge-design.md`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(track): delete Rumor/Track models + providers — merge complete"
```

---

## Post-plan verification (before PR)

- `flutter analyze` clean, `flutter test` green (Task 9 already proves this).
- Manual smoke on macOS (`flutter run -d macos`): create a rumor, confirm it, step its clock, mark done, filter chips, search finds it, Run panel shows both sections, campaign export/import round-trips.
- Ship via the repo's `/ship-pr` flow as one PR titled `feat(track): unified threads — tracking merge (consolidation epic 1/7)`.
