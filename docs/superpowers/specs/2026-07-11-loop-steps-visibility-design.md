# Loop Steps Visibility — design

**Date:** 2026-07-11
**Source:** tool-evaluation audit F2
(`docs/superpowers/audits/2026-07-11-tool-evaluation-audit.md`) — the S3
("Steps panel clips") residue from the stranger-test audit.

## Problem

Two compounding layout defects hide the loop's teaching surface:

1. **No scroll affordance.** `PlayScreen` caps the expanded loop bar at 45%
   of the play area inside a bare `SingleChildScrollView`
   (`lib/features/loop_bar.dart` host). When Steps expands past the cap the
   content clips dead — no scrollbar, no fade — so steps 2–5 read as
   nonexistent (desktop) and step 1's card cuts mid-button (mobile).
2. **Centered intrinsic-width cards.** The Steps `ExpansionTile` uses the
   default `expandedCrossAxisAlignment` (center), so each `_step` Card
   shrinks to its content width and floats centered in dead gutters instead
   of reading as a list.

## Design

- **Visible scrollbar on the capped region:** `PlayScreen` owns a
  `ScrollController` and wraps the loop-bar `SingleChildScrollView` in
  `Scrollbar(thumbVisibility: true)` — the standard "there is more below"
  affordance, always on while the bar is expanded (the bar only scrolls
  when content exceeds the cap; with less content the thumb fills the
  track, which is honest).
- **Stretch the step cards:** the Steps `ExpansionTile` gets
  `expandedCrossAxisAlignment: CrossAxisAlignment.stretch` and horizontal
  `childrenPadding` so cards fill the row like every other full-width
  element of the bar.

No behavioral change to the steps themselves; layout only.

## Success criteria

- Expanding Steps on a desktop-sized viewport shows full-width step cards
  and a visible scrollbar thumb; dragging reaches step 5 (Capture).
- Step cards' width tracks the viewport (no centered floating card).
- Existing loop-bar + play-screen layout tests stay green; a new test
  asserts the stretch + scrollbar wiring.
