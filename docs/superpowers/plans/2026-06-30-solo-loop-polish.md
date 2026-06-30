# Solo Loop polish pack

Five cheap, cohesive fixes to the signature Solo Loop, all in
`lib/features/loop_pane.dart` (+ a few ephemeral providers). From the 2026-06-30
play-loop audit (`docs/superpowers/audits/2026-06-30-backlog-and-play-loop-audit.md`).
One PR. No new persistence, no model changes.

API facts (verified): `journalProvider.notifier.addScene(String) -> Future<String>`,
`addText(String)`, `addResult(title, text, {sourceTool, payload})`;
`threadsProvider.notifier.addReturningId(String) -> Future<String>`,
`setTally(id, Tally)`, `adjustTally(id, delta)`; `kTallyPresets` =
`List<(String label, int start, int target)>`, `rollVsTally(Tally, Dice) ->
TallyRollOutcome {clean, complication}` (all in `lib/engine/tally.dart`).

## Task 1 — Scene title at creation
`_newScene` currently does `addScene('New scene')`. Replace with: show an
`AlertDialog` with a single text field (key `loop-scene-name`, autofocus,
`onSubmitted` confirms) + Cancel/Create. On confirm, `final title =
input.trim().isEmpty ? 'New scene' : input.trim();` then `addScene(title)` +
`setActiveScene(id)` as today. Cancel aborts (no scene created). Keep the
`if (!mounted) return;` guard after the await.

## Task 2 — Step-4 inline task-create
Step 4 currently dead-ends to "Add one on a thread (Track → Threads)". Add, inside
step 4 (above/below the task list), a compact inline creator row:
- a `TextField` (key `loop-task-name`, `Expanded`/bounded width) for the task name,
- a `DropdownButton<(String,int,int)>` (key `loop-task-preset`) of `kTallyPresets`
  (default `kTallyPresets[1]` = Minor challenge 3(6)), label shows `label start(target)`,
- a "Track it" `FilledButton.tonalIcon` (key `loop-task-new`).
On tap: name blank → no-op; else `final id = await addReturningId(name); await
setTally(id, Tally(start: p.$2, current: p.$2, target: p.$3));` then clear the field.
Keep the existing tallied-task list + dec/inc. The "No tallied tasks…" hint can
stay as the empty body but reworded to "No tasks yet — name one below." (no longer
sends the player away). Mind loose constraints: wrap buttons in `Flexible`, don't
put bare buttons as non-flex Row children beside an `Expanded`.

## Task 3 — Step-5 capture send button
The capture `TextField` only fires on `onSubmitted`. Add a `suffixIcon`
`IconButton(Icons.send)` (key `loop-capture-send`, tooltip "Log") → `_captureNote()`.
(Matches the Run Capture panel.)

## Task 4 — Loop UI state survives tab navigation
`_odds`, `_last`, and the capture text are widget-local and reset on every tab
switch. Move them to ephemeral (NOT autoDispose, NOT persisted) providers declared
at the top of loop_pane.dart:
```dart
final _loopOddsProvider = StateProvider<SoloLikelihood>((_) => SoloLikelihood.even);
final _loopLastProvider = StateProvider<SoloYesNo?>((_) => null);
final _loopCaptureProvider = StateProvider<String>((_) => '');
final _loopTallyRollProvider = StateProvider<String?>((_) => null); // Task 5
```
- Read `_odds` via `ref.watch(_loopOddsProvider)`; the SegmentedButton writes
  `ref.read(_loopOddsProvider.notifier).state = s.first`.
- `_last` via the provider; `_ask`/`_interpret` read/write it.
- Capture: keep a `TextEditingController` but seed it once from
  `_loopCaptureProvider` in `initState`, and on `onChanged` write the text back to
  the provider; `_captureNote` clears both controller + provider. (Controller must
  survive within the State as today; the provider is what survives nav since the
  State is disposed on tab switch — so on `initState` re-seed the controller's text
  from the provider.) Remove the now-redundant local fields. Keep `dispose`.

These are file-private providers (leading `_`), app-global lifetime (reset on app
restart) — fine for ephemeral loop UI.

## Task 5 — Tally roll in the loop
Add a roll button (key `loop-task-roll-${t.id}`, `Icons.casino_outlined`) to each
task row's trailing `Wrap`. On tap: `final outcome = rollVsTally(t.tally!, Dice());`
→ set `_loopTallyRollProvider` to a string like
`'${t.title}: ${outcome == TallyRollOutcome.clean ? 'clean' : 'complication'}'`
AND log a journal entry: `addResult('Tally roll', '<that string>', sourceTool:
'solo-loop')`. Render the most recent tally-roll result inline under the step-4 body
(key `loop-tally-roll-result`) when the provider is non-null. Do NOT auto-adjust the
tally — a tally roll is a complication check (clean/complication), not a ±1 progress
step; the player still uses dec/inc to move progress.

## Task 6 — Tests + docs + verify
- Extend/replace `test/loop_pane_test.dart` (read it first for the harness — it
  pumps `LoopPane` with seeded prefs; mirror it). Cover: new-scene dialog sets a
  custom title (find `loop-scene-name`, enter text, Create → journal has a scene
  with that title); step-4 inline create makes a tallied thread
  (`loop-task-name` + `loop-task-new` → a thread with a tally appears);
  capture send button logs (`loop-capture-send`); odds selection + `_last` survive
  a rebuild via the providers (pump, set odds, roll, dispose+repump the pane in the
  same container, assert the result text persists); tally roll logs an entry +
  shows `loop-tally-roll-result`.
- `CLAUDE.md`: the Solo Loop bullet's Loop-pane description — note the inline
  scene-title dialog, inline task-create, capture send button, nav-surviving state,
  and per-task tally roll.
- `flutter analyze` clean; full `flutter test` suite green.

## Out of scope
- Auto-applying tally roll outcomes to progress.
- Persisting loop UI state to disk / per-campaign.
- Reworking the Tasks pane (#229) — the loop's inline create is complementary.
