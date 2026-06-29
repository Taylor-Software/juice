# Solo Loop + Success Tally — Design

**Date:** 2026-06-29
**Status:** Approved (brainstorming)
**Source inspiration:** *Cairn Solo* by Andrew Cavanagh (EpicEmpires.org), text licensed
CC-BY-SA 4.0. Only non-copyrightable **mechanics/procedures** are adopted (no creative
content vendored), so the ShareAlike term imposes no obligation on this app. A courtesy
credit is shown anyway.

## Summary

Two related, system-agnostic solo-play features:

1. **Success Tally** — a bidirectional "major task" tracker (`current(target)`, floor at 0 =
   fail, hit target = win), attached as an **optional** field on the existing `Thread`
   model. Distinct from `Thread`'s existing one-way `progress/progressMax` clock; the two
   coexist and a player picks per thread.
2. **Solo Loop** — an active, wired **checklist** panel (new Track-verb subtab "Loop") that
   threads existing pieces — active scene, a d10 yes/no oracle, the inspire generators,
   tally tasks, and journal logging — into the proven Cairn-Solo loop: *set scene → ask a
   question → interpret → update tally → log.*

The loop's "ask" step ships a clean **d10 Yes/No oracle** (likelihood 3/5/7 with
boon/complication twists). No Word Oracle (cut — redundant with the existing generator
registry and its word list is SA-encumbered creative content).

## Goals / Non-goals

**Goals**
- Give solo players a single guided procedure surface that wires the app's existing
  oracle / scene / thread / journal pieces together.
- Add the one genuinely missing mechanic — a bidirectional success/failure tally with
  stakes — without a new persistence key or breaking the existing thread clock.

**Non-goals**
- No Word Oracle (deferred; would need an authored list to avoid ShareAlike).
- No new AI seam — the existing per-entry **Interpret** already works on logged loop rolls.
- No standalone Tasks pane — the tally rides on threads (Track → Threads).
- No migration concerns beyond tolerant JSON (pre-release).

## Section 1 — Engine + data model (pure)

### `lib/engine/tally.dart` (new, pure — no Flutter, no models.dart import)

`models.dart` imports this file (same direction as `custom_sheet.dart`), so it must not
import `models.dart`.

```dart
class Tally {
  final int start;
  final int current;   // clamped 0..target
  final int target;    // > 0
  const Tally({required this.start, required this.current, required this.target});

  bool get failed => current <= 0;
  bool get won     => current >= target;
  String get label => '$current($target)';   // e.g. "4(8)"

  Tally adjust(int delta);        // returns copy, current clamped to 0..target
  Tally copyWith({int? start, int? current, int? target});

  Map<String, dynamic> toJson();
  static Tally? maybeFromJson(Map<String, dynamic>? json);  // tolerant; null on bad input
}
```

Authored presets (facts, *Cairn Solo* p.28):

```dart
// label, start, target
const kTallyPresets = [
  ('Modest task',        2, 4),
  ('Minor challenge',    3, 6),
  ('Difficult task',     4, 8),
  ('Long/dangerous task',5, 10),
];
```

`rollVsTally` — the "is it really done?" complication check (p.28): roll `d{target}`; rolling
`<= current` is a clean success, otherwise a complication (success-with-hitch if you were
winning, hope-remaining if failing). Lives in `tally.dart` (or `solo_oracle.dart`); takes the
shared `Dice` abstraction so it's deterministic in tests.

```dart
enum TallyRollOutcome { clean, complication }
TallyRollOutcome rollVsTally(Tally t, Dice dice);   // d{target} <= current ? clean : complication
```

### `lib/engine/solo_oracle.dart` (new, pure)

```dart
enum SoloLikelihood { unlikely, even, likely }      // d10 target = 3 / 5 / 7
extension on SoloLikelihood { int get target; String get label; }

enum SoloTwist { none, boon, complication }

class SoloYesNo {
  final bool yes;
  final SoloTwist twist;
  final int roll;            // the d10 face
  final SoloLikelihood odds;
  GenResult toGenResult();   // so it logs through the existing addResult pipeline
}

SoloYesNo soloYesNo(SoloLikelihood odds, Dice dice);
```

Resolution (d10, *Cairn Solo* p.27 — facts):

| Roll | Result |
|------|--------|
| `1` | Yes, **and a boon** |
| `< target` | Yes |
| `== target` | Yes, **with a complication** |
| `10` | No, **with a complication** |
| else (`> target`, `!= 10`) | No |

`toGenResult()` produces a `GenResult` titled e.g. `"Yes/No — likely"` with a body like
`"Yes, and a boon (rolled 1)"`, sourceTool `'solo-loop'`, so the existing
`JournalNotifier.addResult` logs it and the per-entry Interpret affordance applies.

### `Thread` model change (`lib/engine/models.dart`)

- Add `final Tally? tally;` to `Thread` (lines ~183–243).
- Thread through `copyWith` (add a `clearTally` flag, mirroring patterns like
  `EncounterState.clearLocationRef`, so an attached tally can be removed).
- `toJson` emits `tally` when non-null; `fromJson` uses `Tally.maybeFromJson` (tolerant).
- **No new persistence key** — rides the existing `juice.threads.v1`.

`ThreadNotifier` (in `lib/state/`) gains:
- `setTally(String threadId, Tally tally)`
- `clearTally(String threadId)`
- `adjustTally(String threadId, int delta)`

## Section 2 — UI

### `lib/features/loop_pane.dart` (new) — Track subtab "Loop", ungated

A vertical list of step Cards. **Checklist, not a wizard** — every step is always available
(matches *Cairn Solo*: "there are no rules here"). Widget-local state only (selected
likelihood, last roll result) — no new provider, no persistence.

1. **Scene** — shows `activeSceneEntry(journal, activeSceneId)` title (reuse the spine).
   Button → new/set scene (`JournalNotifier.addScene` + `setActiveScene`). Empty state:
   "Start a scene."
2. **Ask** — a likelihood segmented control (Unlikely / Even / Likely) + `loop-ask` button →
   `soloYesNo(odds, dice)` → result shown inline ("Yes, and a boon — rolled 1") → logs a
   `result` entry via `addResult(result.toGenResult())`.
3. **Inspire** — `loop-inspire` button opens the existing `GenerateSheet`. No new generator.
4. **Tasks** — lists threads where `tally != null`. Per row: `current(target)`, fail/win
   indicator, `+/-`, and `loop-tally-roll-<id>` (roll-vs-tally → snackbar clean/complication).
   A "New task" action creates a thread with a tally via the `kTallyPresets` picker.
5. **Capture** (minimal, cuttable) — a thin note field → `JournalNotifier.addText`.

Footer: courtesy credit line (see Licensing).

**Mount:** add `const SubtabDef('loop', 'Loop')` to the `tabs` list in
`lib/features/tracking_tab.dart` (after `Home`), and the matching `const LoopPane()` to the
`children` list in the same order. Ungated (generic solo aid, like Home/Scenes/Rumors).

### `ThreadsPane` tally row (`lib/features/tracker_screen.dart`)

Rendered on a thread card **only when `t.tally != null`** (reusing the existing progress-clock
stepper visual pattern at lines ~67–286):

- `current(target)` badge + fail/win indicator (e.g. colored chip).
- `thread-tally-dec-<id>` / `thread-tally-inc-<id>` steppers → `adjustTally`.
- `thread-tally-roll-<id>` → `rollVsTally` → snackbar (clean / complication).
- `thread-tally-add-<id>` (attach a tally via the preset picker) / remove (→ `clearTally`).

The existing one-way `progress/progressMax` clock UI is unchanged; tally is additive and
optional.

## Section 3 — Licensing, testing, scope

### Licensing

No creative content from *Cairn Solo* is vendored — only mechanics (tally arithmetic, the
3/5/7 yes/no thresholds, roll-vs-tally). These are non-copyrightable facts, so CC-BY-SA's
ShareAlike term imposes no obligation. A **courtesy** credit (not legally required) appears:

- in Settings sources (`settings-sources`), and
- as a `loop-pane` footer line:

> Solo loop inspired by *Cairn Solo* (CC-BY-SA 4.0, Andrew Cavanagh, EpicEmpires.org).

This is distinct from `kContentAttributions` (which is for *vendored* content). It is a
goodwill credit, not an attribution obligation.

### Testing

- `test/tally_test.dart` — clamp to 0..target, `failed`/`won`, `adjust`, `copyWith` with
  `clearTally`, JSON round-trip, `maybeFromJson` tolerance, presets, `rollVsTally` bands.
- `test/solo_oracle_test.dart` — `soloYesNo` boundary rolls (`1`, `<target`, `==target`,
  `>target`, `10`) for each `SoloLikelihood`, asserting `yes` + `twist`; `toGenResult` shape.
- `test/loop_pane_test.dart` — pump `LoopPane` with overridden data providers + mock prefs +
  fake interpreter (per the rootBundle-hang testing rule — override oracle/verdant/emulator/
  ruleset providers with fixtures, mock SharedPreferences, never call `*.load()`); verify all
  steps render, likelihood selection, `loop-ask` logs one journal entry, tally stepper +
  roll work.
- `test/threads_pane_tally_test.dart` (or extend an existing tracker test) — tally row renders
  only when present; inc/dec/roll/add/remove keys fire.

### Scope / YAGNI — explicitly cut

- **Word Oracle** — redundant with the 28-generator registry; its word list is SA-encumbered.
- **New persistence key** — tally rides `juice.threads.v1`; loop pane is stateless.
- **New AI seam** — existing per-entry Interpret already handles logged loop rolls.
- **Standalone Tasks pane** — tally lives on threads.
- **Step 5 Capture** — optional/minimal; may lean on the journal composer instead.

### Deferred (future follow-ups)

- Tally surfaced on a dedicated Tasks pane / its own scope.
- Word Oracle as an authored (non-SA) generic table.
- Loop-aware assistant-rail prompts ("you have a scene — ask a question or roll").
- AI auto-interpret of loop rolls (one-tap, beyond the existing manual Interpret).

## Files touched

**New**
- `lib/engine/tally.dart`
- `lib/engine/solo_oracle.dart`
- `lib/features/loop_pane.dart`
- `test/tally_test.dart`, `test/solo_oracle_test.dart`, `test/loop_pane_test.dart`,
  `test/threads_pane_tally_test.dart`

**Changed**
- `lib/engine/models.dart` — `Thread.tally`, copyWith/JSON.
- `lib/state/` thread notifier — `setTally`/`clearTally`/`adjustTally`.
- `lib/features/tracker_screen.dart` — tally row on thread cards.
- `lib/features/tracking_tab.dart` — register the "Loop" subtab.
- Settings sources — courtesy credit line.
