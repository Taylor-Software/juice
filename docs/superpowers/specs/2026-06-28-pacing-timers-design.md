# Pacing Timers (Tier-2 combat depth)

**Date:** 2026-06-28
**Status:** Design approved (batch consent), pending plan
**Part of:** GM-tool epic, Tier-2 (item 2 of 4). Builds on the Run-screen (#195).

## Summary

A real-time pacing aid on the Run-screen: a **turn stopwatch** (elapsed on the
current turn, auto-resets each Next-turn) and a **session stopwatch** (elapsed
since combat began). Helps a GM keep the table moving. Ephemeral, wall-clock,
no persistence; the only pure/tested piece is a duration formatter — the ticking
is device-verified (the animated-dice precedent).

## Decisions (from brainstorming)

- **Real-time** (not manual counters): a `Timer.periodic(1s)` in a widget.
- **Ephemeral:** widget-local state, no provider/persistence/export. The shell's
  `IndexedStack` keeps the Run verb mounted, so the timers survive verb switches
  (reset only on app restart / encounter end).
- **Active only during combat:** the timers run only while the encounter has
  combatants. With no encounter the panel shows an idle dash and holds 0.
- **Turn reset:** the turn stopwatch resets to 0 whenever `(round, turnIndex)`
  changes (i.e. Next-turn or a round wrap).

## Components

### `formatDuration(int seconds)` — pure, top-level in `run_screen.dart`

`"M:SS"` (e.g. 65 → `"1:05"`, 600 → `"10:00"`); `"H:MM:SS"` when ≥ 3600
(3661 → `"1:01:01"`); negatives clamp to `"0:00"`. Unit-tested directly (no widget).

### `_TimersPanel` — `ConsumerStatefulWidget` in `run_screen.dart`

- State: `int _session`, `int _turn`; a `Timer? _timer`; `int? _lastRound`,
  `int? _lastTurnIndex` (to detect turn changes).
- `build` watches `encounterProvider`. If combatants exist:
  - lazily start `Timer.periodic(const Duration(seconds: 1), …)` (once) that
    `setState`s `_session++`, `_turn++`.
  - if `(round, turnIndex)` differ from `_lastRound/_lastTurnIndex`, reset
    `_turn = 0` and update the last-seen values.
  - render a `_Panel(key: run-panel-timers, title: 'Timers')` with
    `Text('Turn ${formatDuration(_turn)} · Session ${formatDuration(_session)}')`
    (keyed `run-timers-readout`).
  - If no combatants: cancel/null the timer, hold counts at 0, render an idle
    `Text('—', key: run-timers-idle)`.
- `dispose` cancels `_timer` (no pending-timer leak).

### Placement

A new panel placed FIRST in the Run-screen layout (top of the left column when
wide; top of the list when narrow), above Initiative — pacing is the at-a-glance
header of a live fight.

## Testing

- `formatDuration`: 0→`0:00`, 5→`0:05`, 65→`1:05`, 600→`10:00`, 3661→`1:01:01`,
  −5→`0:00`.
- Widget (run_screen_test): with a seeded encounter, the panel shows
  `run-timers-readout`; `pump(2s)` advances it (turn `0:02`); advancing the turn
  (`encounterProvider.notifier.nextTurn`) resets the turn portion to `0:00` while
  the session keeps climbing. With no encounter, `run-timers-idle` shows and no
  timer is pending. (Dispose cancels the timer so teardown leaves none pending.)

## Out of scope (deferred)

- A GM-set per-turn **countdown** with an over-time alert (this slice is a
  count-up stopwatch only).
- Persisting elapsed across app restarts.
- Action-economy tracking (action/bonus/reaction per combatant).
- A session timer outside combat.
