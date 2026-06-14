# Lonelog Dice Notation addon (P4e) — Design

**Date:** 2026-06-14
**Status:** Approved (autonomous, goal: continue to completion)

## Goal

Add the most-requested Lonelog Dice-Notation-addon feature — **exploding dice (`!`)** — to
juice's existing dice-notation engine, available everywhere the dice roller / `/roll` command
is used.

## Scope decision

The full rpg-dice-roller superset (compound/penetrate, reroll, unique, success pools, critical
markers, sort, groups, `*` `/` `^` arithmetic, compare points, fixed modifier ordering) is a
large rewrite. This slice adds **exploding** — the single most iconic and common feature —
to the existing engine (`lib/engine/dice_notation.dart`, which already does `NdS`, keep/drop,
adv/dis, `d%`, `dF`, `+`/`-`). The remaining modifiers are noted as future work, not built.

## Design

- `_DiceTerm` gains `bool explode`. The parser accepts `!` either before or after the keep
  suffix (`5d10!kh2` == `5d10kh2!`); `bareLabel`/`normalized` canonicalize to `…!` at the end.
- `_rollDice`: when `explode`, a die showing the max re-rolls and the new die is appended (it
  can itself explode), guarded at 1000 iterations. This runs **before** keep (per the spec's
  fixed modifier order), so keep/drop applies to the expanded pool. Not applicable to `dF`
  (a trailing `!` on a fate die is a parse error).

## Testing
`dice_notation_explode_test.dart`: parse/normalize `!` (leading + trailing) + regressions;
`100d6!` expands the pool and total = sum of all dice; explode-before-keep (`20d6!kh3` keeps 3
of the expanded pool); `4dF!` rejected. Existing `dice_notation_test` (46 cases) unchanged.

## Files
**New:** `test/dice_notation_explode_test.dart`.
**Edit:** `lib/engine/dice_notation.dart`.
