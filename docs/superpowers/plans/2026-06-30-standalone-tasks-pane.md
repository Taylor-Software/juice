# Standalone Tasks pane

Closes the "Standalone Tasks pane" deferred item from the Solo Loop + Success
Tally work (`docs/superpowers/specs/2026-06-29-solo-loop-success-tally-design.md`,
deferred lines). A **task** = a `Thread` with `tally != null` (no new model). The
pane is a first-class, always-available Track subtab that consolidates tally-task
management — currently split between thread cards (`_ThreadTallyRow` in
`tracker_screen.dart`) and the Loop pane's read-only step 4.

Facts-only, no new persistence (reuses `threadsProvider` + `Tally`). The Loop
pane's task step stays — complementary.

## Task 1 — Make the tally row reusable
In `lib/features/tracker_screen.dart`: rename the private `_ThreadTallyRow` to a
public `ThreadTallyRow` (and its constructor). Update its single use site in the
same file. No behavior change. (`_pickPreset` stays private inside the class.)

## Task 2 — `TasksPane` + subtab registration
New file `lib/features/tasks_pane.dart`:
- `TasksPane extends ConsumerWidget`. Watch `threadsProvider`; `tasks = threads
  where tally != null`.
- Header row: "Tasks" title + a "New task" button (key `task-new`).
- Empty state (no tasks): a short EmptyState-style message
  ("No tasks yet. Track a major undertaking with a success tally.") + the same
  New-task action.
- Each task → a `Card` (key `task-<id>`) with the thread title (`ListTile`) and,
  below it, `ThreadTallyRow(thread)` for the current(target)/Success/Failed chip +
  dec/inc/roll/remove controls (reused verbatim).
- A tap affordance on the card (`task-open-<id>`) navigates to the Threads subtab
  via `ref.read(shellRouteProvider.notifier).goTo(Destination.track, subtab: 'threads')`
  so the user can edit the underlying thread. (Confirm the goTo signature against
  `campaign_search_sheet.dart`/`track_home_pane.dart` usage before wiring.)
- New-task flow (`_newTask`): an `AlertDialog` with a name field (key
  `task-name`) → on Save, show the `kTallyPresets` bottom sheet (rows keyed
  `task-preset-<label>`), then `final id = await
  threadsProvider.notifier.addReturningId(name); await setTally(id, Tally(start:
  p.$2, current: p.$2, target: p.$3));`. Cancel at either step aborts.

Register in `lib/features/tracking_tab.dart`: add `const SubtabDef('tasks',
'Tasks')` immediately AFTER `'loop'` in `tabs`, and `const TasksPane()` at the
matching position in `children` (keep tabs/children index-aligned). Import the new
file. (SubtabHost resolves by id, but the two lists must stay positionally
aligned — verify against the existing ordering.)

## Task 3 — Tests
`test/tasks_pane_test.dart` (lightweight — TasksPane only reads `threadsProvider`,
so mock prefs + a plain `ProviderScope`/`UncontrolledProviderScope` suffice; do
NOT pump the whole shell or load oracle/ruleset assets — see the rootBundle-hang
memory). Seed `juice.threads.v1` with one tally thread + one plain thread:
- only the tally thread renders (`task-<id>` present for it, absent for the plain
  one).
- `task-new` → enter name → pick a preset → a new task appears with the preset's
  `current(target)`.
- `thread-tally-inc-<id>` (from the reused row) increments the tally.
- empty state shows when no thread has a tally.

## Task 4 — Docs + verify
- In `CLAUDE.md`, update the Solo Loop bullet: note the shipped Tasks pane (Track
  subtab after Loop, lists tally threads, New-task via `kTallyPresets`) and remove
  "Standalone Tasks pane" from its Deferred list.
- `flutter analyze` clean; full `flutter test` suite green.

## Out of scope
- Tasks in their own scope/persistence (still ride on threads).
- A task↔scene/PC link, due dates, ordering/sort. Keep it a thin management view.
