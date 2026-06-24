# Animated Dice Roll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A brief "tumble" animation on the dice roller's result — each die flashes random faces then settles on its rolled value, the total reveals after — pure Flutter, no new deps, honoring reduced-motion.

**Architecture:** A new `DiceRollAnimation` widget (`AnimationController` ~700ms + a periodic face-flash `Timer` cancelled on settle) renders a `DiceRollResult` as animated die-face boxes; the roller's result card hosts it, keyed by a `_rollCount` that bumps per roll.

**Tech Stack:** Dart, Flutter (`AnimationController`, `Timer`), flutter_test.

---

## File Structure

- **Create** `lib/features/dice_roll_animation.dart` — `DiceRollAnimation` + `_DieFace`.
- **Modify** `lib/features/dice_roller_screen.dart` — `_rollCount`; host the animation in the result card.
- **Test** `test/dice_roll_animation_test.dart` (new).
- **Modify** `CLAUDE.md` — note the animation.

---

## Task 1: DiceRollAnimation widget

**Files:**
- Create: `lib/features/dice_roll_animation.dart`
- Test: `test/dice_roll_animation_test.dart`

- [ ] **Step 1: Write the failing test** — create `test/dice_roll_animation_test.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/dice_notation.dart';
import 'package:juice_oracle/features/dice_roll_animation.dart';

void main() {
  final result = parseDice('2d6+1').roll(Dice(Random(1)));

  testWidgets('settles to the final total + group label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DiceRollAnimation(result: result, rollId: 1)),
    ));
    await tester.pumpAndSettle(); // past the tumble (timer cancels on settle)
    expect(tester.widget<Text>(find.byKey(const Key('dice-total'))).data,
        '${result.total}');
    expect(find.textContaining('2d6'), findsOneWidget); // the group label
  });

  testWidgets('reduced-motion renders immediately, no pending timer',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: DiceRollAnimation(result: result, rollId: 1),
          );
        }),
      ),
    ));
    await tester.pump(); // one frame — no tumble to settle
    expect(tester.widget<Text>(find.byKey(const Key('dice-total'))).data,
        '${result.total}');
    // No pending-timer error on test teardown proves _flash never started.
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/dice_roll_animation_test.dart`
Expected: FAIL — `DiceRollAnimation` undefined.

- [ ] **Step 3: Implement** — create `lib/features/dice_roll_animation.dart`:

```dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../engine/dice_notation.dart';

/// A brief "tumble" over a [DiceRollResult]: each die flashes random faces, then
/// settles on its rolled value with a scale-bounce; the total reveals after.
/// Honors reduced-motion. No deps (AnimationController + Timer). [rollId] bumps
/// per roll — a change replays the tumble.
class DiceRollAnimation extends StatefulWidget {
  const DiceRollAnimation(
      {super.key, required this.result, required this.rollId});
  final DiceRollResult result;
  final int rollId;

  @override
  State<DiceRollAnimation> createState() => _DiceRollAnimationState();
}

class _DiceRollAnimationState extends State<DiceRollAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        _flash?.cancel();
        _flash = null;
        setState(() => _tumbling = false);
      }
    });
  Timer? _flash;
  bool _tumbling = false;
  bool _started = false;
  final _rng = Random();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _start(); // initial — MediaQuery is readable here (not in initState)
    }
  }

  @override
  void didUpdateWidget(covariant DiceRollAnimation old) {
    super.didUpdateWidget(old);
    if (widget.rollId != old.rollId) _start();
  }

  void _start() {
    _flash?.cancel();
    if (MediaQuery.of(context).disableAnimations) {
      setState(() => _tumbling = false);
      return;
    }
    setState(() => _tumbling = true);
    _ctrl.forward(from: 0);
    // Re-randomize faces each tick (empty setState rebuilds → new _faceFor).
    _flash = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _flash?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  /// A plausible random face for [g] during the tumble (size parsed from label).
  String _faceFor(RolledGroup g) {
    final m = RegExp(r'd(F|%|\d+)', caseSensitive: false).firstMatch(g.label);
    final spec = m?.group(1)?.toLowerCase();
    if (spec == 'f') return const ['+', '−', '0'][_rng.nextInt(3)];
    final sides = spec == '%' ? 100 : (int.tryParse(spec ?? '') ?? 6);
    return '${_rng.nextInt(sides) + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedScale(
          scale: _tumbling ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.centerLeft,
          child: Text(
            '${r.total}',
            key: const Key('dice-total'),
            style: theme.textTheme.displaySmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        for (final g in r.groups)
          if (g.dice.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${g.label}: ', style: theme.textTheme.bodyMedium),
                  for (final d in g.dice)
                    _DieFace(
                      face: _tumbling ? _faceFor(g) : d.display,
                      kept: d.kept,
                      settled: !_tumbling,
                    ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Chip(
                  label: Text(g.label), visualDensity: VisualDensity.compact),
            ),
      ],
    );
  }
}

class _DieFace extends StatelessWidget {
  const _DieFace(
      {required this.face, required this.kept, required this.settled});
  final String face;
  final bool kept;
  final bool settled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedScale(
      scale: settled ? 1.0 : 0.92,
      duration: const Duration(milliseconds: 120),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kept
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: kept
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          face,
          style: theme.textTheme.titleMedium?.copyWith(
            decoration: kept ? null : TextDecoration.lineThrough,
            color: kept ? null : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/dice_roll_animation_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/dice_roll_animation.dart test/dice_roll_animation_test.dart
git commit -m "feat(dice): DiceRollAnimation — tumble-then-settle die faces (no deps)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Wire into the dice roller screen

**Files:**
- Modify: `lib/features/dice_roller_screen.dart`

- [ ] **Step 1: Add the roll counter** — in `_DiceRollerScreenState` (or the state class), add a field beside `_last`/`_history`:

```dart
  int _rollCount = 0;
```

and increment it in `_record` (the method that records every roll). Change:

```dart
  void _record(DiceRollResult result) {
    _last = result;
    _history.insert(0, result);
```
to:
```dart
  void _record(DiceRollResult result) {
    _last = result;
    _rollCount++;
    _history.insert(0, result);
```

- [ ] **Step 2: Host the animation** — in `build`, in the result `Card`'s
`Column`, REPLACE the static total + per-group block (the `Text('${last.total}',
key: const Key('dice-total'), …)` and the following `for (final g in
last.groups) …` Text.rich/Text loop) with:

```dart
                  DiceRollAnimation(result: last, rollId: _rollCount),
```

Keep the `Row` above it (the `expression` title + the "Roll again" / "Add to
journal" `IconButton`s) intact. Add the import:

```dart
import 'dice_roll_animation.dart';
```

- [ ] **Step 3: Run to verify nothing broke**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test test/dice_roller_screen_test.dart` → expect PASS. (The
existing test rolls `2d6+3`, `pumpAndSettle`s past the animation, then asserts
`dice-total` is present and `textContaining('2d6')` — both preserved: the
animation keeps the `dice-total` key and renders `'${g.label}: '` containing
`2d6`. `pumpAndSettle` resolves once the ~700ms controller completes and cancels
the flash timer.)
Run: `flutter test` → expect All tests passed.

- [ ] **Step 4: Commit**

```bash
git add lib/features/dice_roller_screen.dart
git commit -m "feat(dice): animate the roller result card (rollId-triggered tumble)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Doc sync — CLAUDE.md

**Files:** Modify `CLAUDE.md`

- [ ] **Step 1: Note the animation** — in `CLAUDE.md`, find the dice/oracle or
the `dice-reroll-card` area (search for `dice_notation` / `parseDice` / `dice
roller`). Append a sentence near the dice notation mention (or, if none, in the
stack bullet):

```
  The dice roller's result card animates each roll via `DiceRollAnimation`
  (`lib/features/dice_roll_animation.dart`) — a no-deps tumble (AnimationController
  + a face-flash Timer cancelled on settle) that flashes random faces then
  settles on the rolled `display`s, total revealing after; honors
  `MediaQuery.disableAnimations` (reduced-motion → instant). Roller screen only;
  the inline journal-dice + HUD quick-roll stay instant. The settled/reduced-motion
  states are widget-tested, the tumble feel device-verified. See
  `docs/superpowers/specs/2026-06-24-animated-dice-design.md`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note the dice roll animation in CLAUDE.md

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 `DiceRollAnimation` widget (controller + flash timer + reduced-motion + `_DieFace`) → Task 1. ✓
- §2 wiring (`_rollCount`, host in the result card) → Task 2. ✓
- Reduced-motion + timer-cancel-on-settle → Task 1 (lifecycle + the test). ✓
- Testing (settle + reduced-motion) → Task 1; existing-test compat → Task 2. ✓
- Doc → Task 3. ✓

**Type consistency:**
- `DiceRollAnimation({result: DiceRollResult, rollId: int})` (Task 1) hosted with `result: last, rollId: _rollCount` (Task 2). ✓
- `_DieFace({face, kept, settled})` defined + used within Task 1. ✓
- `RolledGroup.label`/`.dice`, `RolledDie.display`/`.kept`, `DiceRollResult.total`/`.groups` — match the engine (`dice_notation.dart`). ✓
- `dice-total` key preserved (Task 1) so the existing screen test (Task 2) passes. ✓

**Placeholder scan:** No TBD/TODO; complete code per step.

**Risk notes:**
- **Timer leak:** `_flash` is cancelled on `_ctrl` completion AND in `dispose` — without this `pumpAndSettle` hangs / "A Timer is still pending." Covered by the lifecycle + the settle test.
- **MediaQuery in initState:** the initial `_start()` runs from `didChangeDependencies` (guarded by `_started`), not `initState`, so `MediaQuery.of(context)` is legal.
- The reduced-motion test overrides `disableAnimations` via an inner `MediaQuery` (`copyWith` from a `Builder` context) so it wins for the subtree.
