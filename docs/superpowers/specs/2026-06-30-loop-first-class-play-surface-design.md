# Loop as a First-Class "Play" Surface — Design

_Dated 2026-06-30. Phase 1 of the cut-to-the-wedge roadmap
(`docs/superpowers/plans/2026-06-30-wedge-roadmap.md`). Makes the guided
solo-play loop the app's spine: a first-class destination with a one-tap
"Next beat" flow and inline oracle interpretation._

## Problem

The Solo Loop is buried as a subtab under the Track verb
(`track_home_pane.dart:75`, `lib/features/loop_pane.dart`). The wedge is the
loop, yet it takes two taps to reach and reads as one tool among many. Playing a
beat means walking a 5-step checklist and, for interpretation, opening a modal
sheet. The loop should be where a solo campaign lands and where a whole session
can be played without leaving the screen.

## Decisions (from brainstorming)

1. **Merge Journal + Loop into one "Play" destination** — stay at 6 verbs.
2. **"Next beat" = a context menu** of 2–3 state-relevant actions, not a fully
   automatic single action. The 5 step-cards remain as the full palette.
3. **Inline interpretation** — after an Ask, the AI reading renders in-place with
   **Keep / Discard** (no modal navigation, quality gate retained).

## Architecture

### The Play destination

Repurpose the existing `Destination.journal` slot rather than add a 7th verb.

- **Keep the enum identifier `journal`** (surgical — avoids rewriting every
  `Destination.journal` reference across the assistant rail, campaign-search nav
  mapping, `toolLocation`, and `shellRouteProvider.build()`). Only the
  user-facing label + icon change: `destinationMeta[Destination.journal]` becomes
  `DestinationMeta('Play', Icons.auto_stories_outlined)` (final icon chosen at
  implementation). **Known drift:** the enum reads `journal` but presents as
  "Play" — documented here; a later rename is a mechanical follow-up, out of
  scope now.
- **Mount point:** the shell body's `case Destination.journal` (home_shell.dart
  ~line 490) returns a `Column[ LoopBar, Expanded(JournalScreen) ]` instead of a
  bare `JournalScreen`. The split-view path (~line 575) is left on `JournalScreen`
  only (the LoopBar is the primary-pane affordance; not duplicated into split).
- **Remove the Loop subtab** from `track_home_pane.dart`. Its logic moves into
  the LoopBar; the standalone **Tasks** pane and the loop-aware rail chips stay.

### Landing

`landingDestination(CampaignMode.party)` changes from `Destination.sheet` to
`Destination.journal` (Play). GM still lands on Run. `landFor`'s hasEncounter
override (Track→Encounter) is unchanged. This is a deliberate wedge shift: a
solo/party campaign now opens on the loop. Supersedes the party→Sheet landing
from the GM/Party-mode spec.

## Components

### `LoopBar` (new — `lib/features/loop_bar.dart`)

A `ConsumerStatefulWidget` mounted atop the journal feed on the Play verb. It
absorbs the play logic currently in `_LoopPaneState` (`_ask`, `_newScene`,
`_newTask`, `_tallyRoll`, `_captureNote`, `_interpret`) and adds:

- A prominent **Next beat** control that expands a row of 2–3 `BeatAction`
  buttons computed by the pure `nextBeatActions(...)` (below).
- An inline **result line** (the last yes/no, key `loop-ask-result`) and the new
  inline **`_InterpretCard`** (below).
- A collapsible **"Steps"** `ExpansionTile` holding the existing 5 step-cards
  (Scene / Ask / Inspire / Tasks / Capture) with their current keys
  (`loop-new-scene`, `loop-ask`, `loop-inspire`, `loop-task-*`,
  `loop-capture-*`) preserved, so existing loop tests keep working after the
  move. Collapsed by default (playing uses Next-beat; the steps are the learning
  palette).

`loop_pane.dart` is refactored into `loop_bar.dart`; the file-private
nav-surviving providers (`_loopOddsProvider`, `_loopLastProvider`,
`_loopCaptureProvider`, `_loopTallyRollProvider`) move with it, plus two new
ones: `_loopInterpretProvider` (`StateProvider<OracleSeed?>`, the pending
inline-card seed — non-null means the card is showing) and
`_loopInterpretedProvider` (`StateProvider<bool>`, feeds `interpretDone`). Each
new **Ask** resets `_loopInterpretedProvider` to false; both **Keep** and
**Discard** set it true (the recent ask is resolved either way). `hasRecentAsk`
is `_loopLastProvider != null`.

### `nextBeatActions` (new pure engine — `lib/engine/next_beat.dart`)

No Flutter import. Deterministic, unit-testable.

```
enum BeatAction { nameScene, ask, askAgain, interpret, inspire, capture }

List<BeatAction> nextBeatActions({
  required bool hasScene,
  required bool hasRecentAsk,   // a yes/no roll exists this session
  required bool interpretDone,  // the recent ask already interpreted
  required bool aiReady,
}) { ... }
```

Rules (capped at 3, priority-ordered):

| State | Actions |
|---|---|
| `!hasScene` | `[nameScene]` |
| `hasScene && !hasRecentAsk` | `[ask, inspire, capture]` |
| `hasScene && hasRecentAsk && aiReady && !interpretDone` | `[interpret, capture, askAgain]` |
| `hasScene && hasRecentAsk && (interpretDone || !aiReady)` | `[askAgain, capture, inspire]` |

Each `BeatAction` maps in the widget to a label + icon + handler. The widget owns
the presentation; the engine owns the choice.

### `_InterpretCard` (new — private to `loop_bar.dart`)

A small `ConsumerStatefulWidget` given an `OracleSeed`. On build it calls
`ref.read(interpreterServiceProvider).interpret(seed)`
(`InterpreterService.interpret → Future<List<OracleInterpretation>>`) and renders:

- loading → a spinner;
- error → a short "reading failed" line with a Retry;
- success → the reading text + **Keep** / **Discard**.
  - **Keep** → `journalProvider.addResult('Oracle reading', '(<lens>):
    <reading>', sourceTool: 'interpret')` (same entry shape as today's
    `_interpret`) and marks `interpretDone`.
  - **Discard** → clears the pending state; nothing logged.

This replaces the modal path **only in the loop**. `OracleInterpretationSheet`
is retained unchanged for its other callers (Run screen, journal per-entry
Interpret).

## Data flow

1. Campaign entered (party) → `landFor(party)` → Play verb.
2. LoopBar reads the PlayContext spine (`activeSceneEntry`), the last yes/no
   (`_loopLastProvider`), `aiReadyProvider`, and tallies → `nextBeatActions`.
3. Tap **Next beat** → shows the action buttons → tap one:
   - `nameScene` → existing `_newScene` dialog → `addScene` + `setActiveScene`.
   - `ask`/`askAgain` → existing `_ask` (`soloYesNo` → journal `solo-loop`
     entry) → sets `_loopLastProvider`.
   - `interpret` → seeds `OracleSeed` (as today's `_interpret`) → sets
     `_loopInterpretProvider` → `_InterpretCard` renders inline.
   - `inspire` → `showGenerateSheet`. `capture` → focuses the capture field.
4. Journal feed below updates live (it already watches `journalProvider`).

## Error handling

- Interpret failure renders inline (no crash, Retry offered); AI-off hides the
  interpret action entirely (gated on `aiReady`, same as today).
- Cancelling the scene dialog creates nothing (existing behavior).
- The inline card's pending state is nav-surviving via `_loopInterpretProvider`,
  consistent with the other loop providers.

## Testing

- **Unit** (`test/next_beat_test.dart`): `nextBeatActions` across every state
  row above, incl. the aiReady/interpretDone matrix and the 3-action cap.
- **Widget** (`test/loop_bar_test.dart`): LoopBar renders on the Play verb;
  Next-beat expands the correct actions per state; Ask → `loop-ask-result`
  shows; Interpret (fake interpreter ready) → inline reading → **Keep** logs
  exactly one `interpret` entry, **Discard** logs none; the "Steps" expander
  still exposes the legacy step keys.
- **Migration:** update tests asserting the Track→Loop subtab (now gone) and
  party landing (Sheet → Play). Reuse the existing fake interpreter pattern
  (never construct `GemmaInterpreterService`); enable AI via mocked
  `juice.ai_enabled.v1`.
- Full `flutter analyze` + `flutter test` green.

## Non-goals (this phase)

- Cloud / BYO-key LLM (Phase 2).
- Shareable loop kits (Phase 3).
- Any change to Run / GM panels, the assistant rail (frozen — minor ask-chip
  redundancy with Next-beat is accepted and noted), or the journal composer.
- A clean `Destination.journal` → `play` rename (mechanical follow-up).

## Files

- New: `lib/features/loop_bar.dart`, `lib/engine/next_beat.dart`,
  `test/next_beat_test.dart`, `test/loop_bar_test.dart`.
- Changed: `lib/shared/destination.dart` (label/icon + landing),
  `lib/shared/home_shell.dart` (Play case mounts `Column[LoopBar, feed]`),
  `lib/features/track_home_pane.dart` (drop Loop subtab), migration edits in
  existing tests.
- Removed: `lib/features/loop_pane.dart` (content moves to `loop_bar.dart`).
