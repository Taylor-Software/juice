# Lonelog Cards addon (P4c) — Design

**Date:** 2026-06-14
**Status:** Approved (autonomous, goal: continue to completion)
**Depends on:** P1 (documents the Cards addon in the legend)

## Goal

Provide the Lonelog Cards addon's notation as a usable engine: expand a compact card token
(`Qs`, `M16r`, `ACu`) to a human-readable name.

## Rationale / scope

The Cards addon is **pure recording vocabulary** — the player supplies a physical deck; the
notation only standardizes how a drawn card is written. So the faithful, complete
implementation is a token→name parser, not a tool or a rollable asset. No randomization (the
addon defines none), no new tool, no UI in this slice — `cardName()` is ready for a future
journal/reference render or a draw tool.

## Design

`lib/engine/card_notation.dart` (pure, Dart constants — the data is tiny, universal, stable,
so no `build_*.py` asset rail is warranted):
- `cardName(String token) -> String?` — standard `{rank}{suit}` (suits h/d/c/s; the `10`
  two-char rank handled), jokers/colours (`Jkr`/`RJkr`/`BJkr`/`R`/`B`), tarot major `M0..M21`
  (`kMajorArcana`, RWS), tarot minor `{rank}{suit}` (Wa/Cu/Sw/Pe; Pg/Kn ranks), and a trailing
  `r` = reversed (unambiguous — no card suit ends in `r`).

## Testing
`card_notation_test.dart`: standard cards incl. `10`; jokers/colours; major upright+reversed +
out-of-range; minor upright+reversed + the `KnCu`-is-upright edge; unrecognized → null.

## Files
**New:** `lib/engine/card_notation.dart`, `test/card_notation_test.dart`.
