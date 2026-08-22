# Combat Merge — One Encounter Widget, Two Mounts

**Date:** 2026-08-22
**Status:** Approved design, pre-implementation
**Sub-project:** 2 of 7 in the tool-consolidation epic (roadmap in
`docs/superpowers/specs/2026-08-22-tracking-merge-design.md`)
**Branch note:** stacked on `feat/tracking-merge` (PR #333) because both touch
`lib/features/run_screen.dart`; rebase onto main after #333 lands.

## Problem

Two implementations render the same fight:

- **EncounterScreen** (`lib/features/encounter_screen.dart`, ~1620 lines,
  Track → Encounter): the full combat manager — combatant rows with HP
  steppers, conditions, tags, attack chips, stat-block edit, initiative edit,
  add flows (ad-hoc / characters / bestiary / foes / reference / generator),
  QuickRef, end-encounter with thread-clock advance.
- **`_InitiativePanel`** (`lib/features/run_screen.dart:169-273`, Run
  dashboard): a ~100-line read-only re-implementation — initiative rows,
  current-turn highlight, defeated strike-through, HP readout, tap-row
  stat-block dialog, Next-turn and Roll-all buttons.

Every change to combat rendering must be made twice. The Run panel drifts.

## Decisions already made (user-confirmed)

1. **One widget, two mounts** — extract the encounter body into one reusable
   pane with a compact mode; Track keeps the full manager, Run mounts the
   same widget compact. No verb-semantics change.
2. **Lonelog `BattlePane` stays out** — it serves lonelog's own notation and
   model; not part of this merge.
3. **Approach A** — a single `EncounterPane({bool compact})`, not a
   shared-row-only extraction and not per-section feature flags.

## Design

### 1. Component extraction (`lib/features/encounter_screen.dart`)

- New public widget `EncounterPane extends ConsumerWidget` with constructor
  `const EncounterPane({super.key, this.compact = false})`. Full mode owns
  EVERYTHING `EncounterScreen.build` renders today — the whole
  `Column[_header, list, _addButtons]` body including the Round header,
  `next-turn`, `enc-rules`, `end-encounter`, and the add-combatant button
  rows (`add-character`/`add-adhoc`/`generate-monster`/`add-bestiary`/
  `add-foes`/`add-from-reference`). There is no separate screen chrome.
- `EncounterScreen` remains the Track mount name and becomes a trivial
  wrapper returning `const EncounterPane()`. All existing `enc-*` and add
  keys, dialogs, and helper methods move to the pane unchanged — full mode
  is a pure extraction, zero behavior change.
- The pane brings no `Card`/`Scaffold` surface of its own in compact mode —
  the Run `_Panel` supplies the chrome (repo rule: detail widgets bring their
  own surface only where the host adds none; here the host adds one).

### 2. Compact mode contract

Compact mode renders, from `encounterProvider` state:

- One row per combatant: initiative `CircleAvatar` (current-turn highlighted),
  name (defeated = strike-through, current = primary color), HP readout
  `cur/max` when a track exists. Row key: `run-init-row-<id>`.
- Tap on a row with a non-empty stat block opens the read-only
  `StatBlockView` dialog (existing `_showStatBlock` behavior moves into the
  pane).
- Action row: `run-init-next` ("Next turn") and `run-init-roll-all`
  ("Roll all init") — same `EncounterNotifier.nextTurn()` /
  `rollInitiativeForAll()` calls as today, disabled when no combatants.
- An `run-init-open-full` `ActionChip`/TextButton ("Open encounter") that
  navigates via `shellRouteProvider.notifier.goTo(Destination.track,
  subtab: 'encounter')`.
- Empty state: the existing "No encounter yet." text, key `run-init-empty`.
- Compact mode shows NONE of the manager affordances: no HP steppers, no
  condition/tag editing, no attack chips, no stat-block/initiative editors,
  no add flows, no end-encounter.
- Key policy: compact mode emits the `run-init-*` keys above (existing Run
  tests and muscle memory unchanged); full mode keeps the `enc-*` keys.
  Colors in both modes come from existing token usage; no new
  `ColorScheme` references (design ratchet).

### 3. Run wiring (`lib/features/run_screen.dart`)

- Delete `_InitiativePanel` (lines 169-273) entirely.
- The dashboard slot becomes
  `_Panel(k: Key('run-panel-initiative'), title: 'Initiative · Round N', child: EncounterPane(compact: true))`
  — a small private wrapper (`_InitiativeSlot` or inline in `build`) may
  compute the round title from `encounterProvider`, since `_Panel` titles are
  Run-side chrome.
- `run_screen.dart` imports `encounter_screen.dart` for the pane. No other
  panel changes.

### 4. Testing + success criteria

Tests:

- Existing encounter tests (`encounter_attack_test.dart` and friends) stay
  green untouched — full mode is a pure extraction.
- Existing `run_screen_test.dart` initiative cases keep passing against the
  shared pane (same `run-init-*` keys).
- New widget test: compact mode renders rows + actions but NOT manager
  affordances (asserts absence of `enc-attack-<id>`, `enc-minus-0`,
  `enc-statblock-<id>`); `run-init-open-full` navigates to Track/encounter.

Success criteria:

- `flutter analyze` clean; full suite green.
- `_InitiativePanel` no longer exists; `run_screen.dart` renders combat
  through `EncounterPane(compact: true)`.
- Track → Encounter is behaviorally unchanged.
- No model or persistence change anywhere in the diff.
