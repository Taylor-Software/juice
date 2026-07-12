# Favorite dice expressions — design

**Date:** 2026-07-12
**Source:** QoL assessment #11 — pin notations the player rolls constantly.

## Design

`favoriteDiceProvider` (`juice.favorite_dice.v1`, app-global string list —
same posture as `customTablesProvider`; deduped, insertion-ordered, capped
at 12, oldest evicted). Surfaces:

- **Dice roller** (`dice_roller_screen.dart`): a star suffix on the
  expression field (`dice-fav-add`, enabled when the input is valid) pins
  the notation; favorites render as star `InputChip`s after the quick dice —
  tap rolls (`_rollExpr`), ✕ unpins.
- **Run dice panel** (`run_screen.dart`): the same favorites as
  `run-dice-fav-<n>` ActionChips under the notation field — tap fills the
  field and rolls through the existing journal-logging path.

## Tests

`test/favorite_dice_test.dart`: add/dedupe/cap/remove persistence + a roller
widget test (pin → chip → roll).
