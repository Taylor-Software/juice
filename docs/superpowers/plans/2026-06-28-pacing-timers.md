# Pacing Timers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or executing-plans. Steps use `- [ ]`.

**Goal:** Real-time turn + session stopwatches on the Run-screen, auto-resetting the turn timer each Next-turn.

**Architecture:** A pure `formatDuration` + a widget-local `_TimersPanel` (`Timer.periodic`) in `run_screen.dart`. Ephemeral; no model/persistence change.

**Tech Stack:** Flutter, flutter_riverpod. Prefix flutter with `export PATH="$HOME/development/flutter/bin:$PATH"`.

---

## Anchors

- `run_screen.dart`: `RunScreen` `LayoutBuilder` builds `const initiative/party/scene/dice/capture` then a wide 2-col / narrow ListView. `_Panel({k, title, child})` is the shared card. `encounterProvider` → `EncounterState {combatants, turnIndex, round}`.
- Test harness `test/run_screen_test.dart`: `_pump(tester, data, _prefs(encounterJson:))`, `_prefs`, `data`.
- `import 'dart:async';` needed for `Timer`.

---

## Task 1: `formatDuration` + `_TimersPanel`

**Files:** Modify `lib/features/run_screen.dart`; Test `test/run_screen_test.dart`.

- [ ] **Step 1: Failing tests** in `test/run_screen_test.dart` (add `import 'package:juice_oracle/features/run_screen.dart';` already present):

```dart
  test('formatDuration', () {
    expect(formatDuration(0), '0:00');
    expect(formatDuration(5), '0:05');
    expect(formatDuration(65), '1:05');
    expect(formatDuration(600), '10:00');
    expect(formatDuration(3661), '1:01:01');
    expect(formatDuration(-5), '0:00');
  });

  testWidgets('timers: idle with no encounter, ticks + resets on turn change',
      (tester) async {
    // no encounter -> idle
    await _pump(tester, data, _prefs());
    expect(find.byKey(const Key('run-timers-idle')), findsOneWidget);

    // with an encounter -> readout that advances and resets the turn portion
    const enc =
        '{"combatants":[{"id":"a","name":"A","initiative":15,"track":{"current":5,"max":5},"tags":[],"defeated":false},{"id":"b","name":"B","initiative":10,"track":{"current":5,"max":5},"tags":[],"defeated":false}],"turnIndex":0,"round":1}';
    final c = await _pump(tester, data, _prefs(encounterJson: enc));
    expect(find.byKey(const Key('run-timers-readout')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('Turn 0:02'), findsOneWidget);
    // advance the turn -> turn portion resets, session keeps climbing
    await c.read(encounterProvider.notifier).nextTurn();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Turn 0:01'), findsOneWidget);
    expect(find.textContaining('Session 0:03'), findsOneWidget);
  });
```

Note: the test pumps discrete seconds so the periodic timer fires deterministically; `_TimersPanel.dispose` cancels the timer so teardown leaves none pending.

- [ ] **Step 2: Run** `export PATH="$HOME/development/flutter/bin:$PATH" && flutter test test/run_screen_test.dart -n "timers\|formatDuration"` — FAIL.

- [ ] **Step 3: Implement** in `lib/features/run_screen.dart`. Add `import 'dart:async';` at the top. Add the pure formatter (top-level, after `kRunWideBreakpoint`):

```dart
/// Formats a duration in seconds as `M:SS` (or `H:MM:SS` past an hour).
/// Negative clamps to `0:00`.
String formatDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}
```

Add the panel widget (after `RunScreen`, before `_Panel` or after it):

```dart
class _TimersPanel extends ConsumerStatefulWidget {
  const _TimersPanel();
  @override
  ConsumerState<_TimersPanel> createState() => _TimersPanelState();
}

class _TimersPanelState extends ConsumerState<_TimersPanel> {
  Timer? _timer;
  int _session = 0;
  int _turn = 0;
  int? _lastRound;
  int? _lastTurnIndex;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _ensureTicking() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _session++;
        _turn++;
      });
    });
  }

  void _stopTicking() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    final enc =
        ref.watch(encounterProvider).valueOrNull ?? const EncounterState();
    final active = enc.combatants.isNotEmpty;

    if (!active) {
      _stopTicking();
      _session = 0;
      _turn = 0;
      _lastRound = null;
      _lastTurnIndex = null;
      return const _Panel(
        k: Key('run-panel-timers'),
        title: 'Timers',
        child: Text('—', key: Key('run-timers-idle')),
      );
    }

    // Reset the turn stopwatch when the turn pointer / round changes.
    if (_lastRound != enc.round || _lastTurnIndex != enc.turnIndex) {
      _turn = 0;
      _lastRound = enc.round;
      _lastTurnIndex = enc.turnIndex;
    }
    // Start ticking after this frame (can't setState during build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureTicking();
    });

    return _Panel(
      k: const Key('run-panel-timers'),
      title: 'Timers',
      child: Text(
        'Turn ${formatDuration(_turn)} · Session ${formatDuration(_session)}',
        key: const Key('run-timers-readout'),
      ),
    );
  }
}
```

Wire it into `RunScreen.build` as the FIRST panel. Change the `const` panel locals to include it and place first in both layouts:
```dart
        const timers = _TimersPanel();
        const initiative = _InitiativePanel();
```
Wide left column children: `[timers, SizedBox(height:12), initiative, SizedBox(height:12), party]`. Narrow ListView children: `[timers, SizedBox(height:12), initiative, ...]` (prepend timers + a spacer).

- [ ] **Step 4: Run** the whole `flutter test test/run_screen_test.dart` — PASS. `flutter analyze lib/features/run_screen.dart` — clean. If a "pending timer" error appears in the no-encounter test, confirm `_stopTicking` ran (no timer started when inactive) — the idle path never starts one.

- [ ] **Step 5: Commit**
```bash
git add lib/features/run_screen.dart test/run_screen_test.dart
git commit -m "feat(run): real-time turn + session pacing stopwatches"
```

---

## Task 2: Full verify + docs

- [ ] **Step 1:** `export PATH="$HOME/development/flutter/bin:$PATH" && flutter analyze && flutter test` — clean + all pass; report count.

- [ ] **Step 2: CLAUDE.md** — append to the Run-screen bullet:
```markdown
  A **pacing-timers** panel (`run-panel-timers`, `_TimersPanel`) shows a real-time
  turn stopwatch (resets each Next-turn) + a session stopwatch via a widget-local
  `Timer.periodic`; active only while an encounter has combatants; ephemeral (no
  persistence). Pure `formatDuration` is unit-tested; the tick is device-verified.
  See `docs/superpowers/specs/2026-06-28-pacing-timers-design.md`.
```

- [ ] **Step 3: Commit**
```bash
git add CLAUDE.md
git commit -m "docs(run): note pacing timers"
```

---

## Self-review notes

- **Spec coverage:** formatter + panel + placement (T1), verify + docs (T2).
- **Naming:** `formatDuration`; `_TimersPanel`; keys `run-panel-timers` / `run-timers-readout` / `run-timers-idle`.
- **No model/persistence change.** Widget-local ephemeral state; `dispose` cancels the timer (no pending-timer leak in tests). Idle path never starts a timer.
- **Loose-constraints:** the panel renders a single `Text` in `_Panel` — no buttons, no Wrap; safe.
