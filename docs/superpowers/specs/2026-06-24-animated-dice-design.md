# Animated dice roll

**Date:** 2026-06-24
**Status:** Design — approved

## Problem

The dice roller (`dice_roller_screen.dart`) shows a roll's result instantly as
static text (total + `label: die, die`). A brief "tumble" animation — dice faces
flashing then settling on the rolled values — adds tactile delight to the core
roll action. Pure polish; no engine change (the dice engine + notation parser
already produce per-die faces).

## Decisions (from brainstorming)

- **2D Flutter animation, no new deps** (`AnimationController` + a `Timer`) —
  fits the lean stack; 3D/physics dice (a heavy dep) is out.
- **Per-die tumble**: each die flashes random faces, eases to its final value,
  settles with a subtle scale-bounce; the total reveals after.
- **Dice roller screen only** — the inline journal-dice + HUD quick-roll stay
  instant (one-off logs, not the interactive roller).
- **Honors reduced-motion** (`MediaQuery.disableAnimations`) → no tumble, the
  final result renders immediately.

## Architecture

### 1. `DiceRollAnimation` widget — `lib/features/dice_roll_animation.dart` (new)

```dart
class DiceRollAnimation extends StatefulWidget {
  const DiceRollAnimation({super.key, required this.result, required this.rollId});
  final DiceRollResult result;
  final int rollId; // bumped per roll; a change replays the tumble
}
```

State (`_DiceRollAnimationState`, `SingleTickerProviderStateMixin`):
- `AnimationController _ctrl` (~700ms, vsync).
- `Timer? _flash` — a periodic ~60ms timer that, while tumbling, sets a random
  face per die.
- `bool _tumbling`.

Lifecycle (note: `MediaQuery.of(context)` is NOT readable in `initState`, so the
initial tumble starts from `didChangeDependencies`, not `initState`):
- `initState` → create `_ctrl` only (no MediaQuery read).
- `didChangeDependencies` → on the FIRST call (guard with a `bool _started`),
  `_start()`. (MediaQuery is readable here.)
- `didUpdateWidget` → if `widget.rollId` changed, `_start()`.
- `_start()`: if `MediaQuery.of(context).disableAnimations` → `setState(_tumbling
  = false)` and render the final immediately (no controller/timer). Else
  `_tumbling = true`, `_ctrl.forward(from: 0)`, and start the periodic `_flash`
  timer.
- On `_ctrl` status `completed` → cancel `_flash`, `setState(_tumbling = false)`.
- `dispose()` → `_flash?.cancel(); _ctrl.dispose();`.

> **Test-safety:** the periodic `_flash` timer MUST be cancelled on completion +
> in `dispose`. A lingering periodic `Timer` makes `pumpAndSettle` hang and fails
> with "A Timer is still pending." The `AnimationController` is finite so
> `pumpAndSettle` resolves once the timer is gone.

Render (`build`):
- For each `RolledGroup` with dice: a `Wrap` of `_DieFace` boxes — one per
  `RolledDie`. While `_tumbling`, each shows a random face (from `_faceFor(group)`);
  when settled, the die's real `display`. Dropped dice (`kept == false`) render
  dimmed + struck-through. A settle scale-bounce via `_ctrl` (e.g. an elastic /
  decelerate curve on the last ~30%).
- Modifier groups (no dice, e.g. `+2`) → a static chip with `group.label`.
- The **total** `Text` keeps `Key('dice-total')` showing `widget.result.total`;
  when tumbling it fades/scales in at the end (still present in the tree, so
  finders work after settle).

`_faceFor(RolledGroup g)` — a plausible random face during the flash: parse the
die size from `g.label` (regex `d(F|%|\d+)`). `F` → random of `{'+','−','0'}`;
`%` → `1..100`; `N` → `1..N`; fallback `1..6`. Approximate is fine — it only
needs to read as "tumbling."

`_DieFace` — a small rounded, bordered square (~36px) showing a value string;
the dimmed/struck style when dropped.

### 2. Wiring — `dice_roller_screen.dart`

- Add `int _rollCount = 0;` to the state; increment it in `_record` (called by
  every roll path — `_rollExpr`, reroll).
- In the result card, replace the static per-group dice rendering + the bare
  total `Text` with `DiceRollAnimation(result: last, rollId: _rollCount)`.
  (Keep the surrounding card, the "add to journal" + "roll again" buttons, and
  the `expression` title.)

## Testing

- `dice_roll_animation_test` (new): pump `DiceRollAnimation` with a known
  `DiceRollResult` (build one via `parseDice('2d6+1').roll(Dice(Random(1)))`),
  `pumpAndSettle`, then assert the final faces render (the die `display`s) and
  `dice-total` shows the real total. A second test wraps it in
  `MediaQuery(data: ...copyWith(disableAnimations: true), …)` and asserts the
  result is present on the first frame (no waiting) + no pending-timer error.
- `dice_roller_screen_test` (existing) must still pass — `dice-total` is
  preserved and `pumpAndSettle` resolves once the animation completes.

The tumble *feel* (timing, bounce) is device-verified, consistent with the
editor/map gesture code (per CLAUDE.md, those routes are device-verified).

## Out of scope (YAGNI)

- 3D / physics dice; a dice-roller pub.dev package; roll sound; animating the
  inline journal-dice or HUD quick-roll; size-accurate flashing (approximate is
  fine); animating the history list.

## Files touched

| File | Change |
|------|--------|
| `lib/features/dice_roll_animation.dart` | NEW — the `DiceRollAnimation` + `_DieFace` widgets |
| `lib/features/dice_roller_screen.dart` | `_rollCount`; render the animation in the result card |
| `test/dice_roll_animation_test.dart` | NEW — settle + reduced-motion tests |
