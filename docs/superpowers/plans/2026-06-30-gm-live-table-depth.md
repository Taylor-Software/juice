# GM live-table depth

Two real wins from the 2026-06-30 audit for the GM live loop. One PR.

**Dropped with cause:** the audit's "combat conditions sync back to Character"
(#B3) is a non-issue — the encounter screen already shows a linked combatant's
conditions **read-through live from the `Character`** (`encounter_screen.dart`
~line 235, "edit on the sheet"); there is no combatant-only conditions editor, and
`EncounterNotifier.setConditions` isn't wired to any UI. Nothing to fix.

## Task 1 — Run dice panel: ad-hoc dice + likelihood (`lib/features/run_screen.dart`, `_DiceOraclePanel`)
Today the panel has only one fixed-odds "Roll <default oracle>" button. Add two
inline affordances without leaving the Run dashboard:

(a) **Ad-hoc dice notation.** A small `TextField` (key `run-dice-notation`,
bounded width, hint "d20, 2d6+1") + a roll `IconButton`/button
(key `run-dice-custom-roll`). On roll: mirror the journal's inline dice path —
`final r = parseDice(text).roll(oracle.dice);` then
`addResult(r.title or 'Dice', r.asText, sourceTool: 'dice', payload: r.toPayload())`
(READ `lib/features/journal_screen.dart` ~line 2156 / 367 for the exact parseDice
result shape + how it logs; reuse identically). Guard against an empty/invalid
notation (parseDice may throw or return a sentinel — handle like journal_screen).
Import `parseDice` (from `../engine/dice.dart` or wherever journal_screen imports it).

(b) **Likelihood selector.** A `SegmentedButton<Likelihood>` (key
`run-dice-likelihood`, segments Unlikely/Even/Likely) whose state feeds the
fate-check branch of `_roll`: change `oracle.fateCheck(Likelihood.normal)` to
`oracle.fateCheck(_likelihood)` where `_likelihood` is panel state (default
`Likelihood.normal`). (Only affects the `juice`/fate-check default-oracle branch;
mythic/roll-high unaffected — leave those.) Confirm the `Likelihood` enum values
(likely/normal/unlikely or similar — check `lib/engine/oracle.dart`).

Loose-constraint safety: the panel already uses `Row` + `Flexible` (not `Wrap`)
deliberately (see its comment). Keep that — wrap any new button in `Flexible`,
give the dice `TextField` a bounded width (e.g. `SizedBox(width: …)` or `Expanded`),
never a bare Material button as a non-flex Row child.

## Task 2 — End-Encounter → advance a thread clock (`lib/features/encounter_screen.dart`)
`_EndEncounterDialog` returns `({String note})` and `_endEncounter` writes a journal
summary. Let the GM close the fight→goal→log arc in one gesture:

- Convert `_EndEncounterDialog` to a `ConsumerStatefulWidget` so it can read
  `threadsProvider`. Add (below the note field):
  - an optional thread `DropdownButton<String?>` (key `end-encounter-thread`) of
    OPEN threads (`threads.where((t) => t.open)`), first item "No thread" (null).
  - a progress stepper (key `end-encounter-progress`, −/value/+) for an int
    `progressDelta` (default 0; allow 0..thread.progressMax-ish or a simple
    0..10 — keep it a plain stepper, clamp ≥0). Only show the stepper when a
    thread is selected.
  - Return `({String note, String? threadId, int progressDelta})` from both the
    `onSubmitted` and the End button.
- In `_endEncounter`: after writing the summary, if `result.threadId != null &&
  result.progressDelta != 0`, look up the thread's current `progress` and call
  `ref.read(threadsProvider.notifier).setProgress(result.threadId!,
  thread.progress + result.progressDelta)` (setProgress clamps to 0..progressMax).
  Then reset as today. Keep the existing summary/lonelog/snackbar behavior intact.
- READ `Thread` (`lib/engine/models.dart` ~184: `open`, `progress`, `progressMax`)
  + `ThreadNotifier.setProgress` (providers.dart:261) for exact signatures.

## Task 3 — Tests + docs + verify
- `test/run_screen_test.dart` (if it exists — READ it for harness; run_screen pumps
  may be heavy per the rootBundle-hang memory, so check what it overrides): test
  `run-dice-custom-roll` with a notation logs a `dice` journal entry; the
  `run-dice-likelihood` selector changes which likelihood the fate roll uses (assert
  via the logged entry or just that selection + roll logs without error). If the
  run_screen harness is too heavy to add these cheaply, add a narrower test and note
  the skip.
- `test/encounter_screen_test.dart` (READ for harness): ending an encounter with a
  selected thread + positive delta advances that thread's `progress`
  (`setProgress`); ending with no thread leaves threads untouched; the journal
  summary is still written.
- `CLAUDE.md`: update the GM Run-screen bullet (ad-hoc dice + likelihood on the dice
  panel) and the encounter/combat bullet (End-Encounter can advance a thread clock).
- `flutter analyze` clean; full `flutter test` suite green.

## Out of scope
- Resolving/closing the thread from the dialog (only progress tick).
- Linking the encounter to a thread persistently (this is a one-shot at end).
- Per-combatant action economy, panel reorder/collapse (separate deferred items).
