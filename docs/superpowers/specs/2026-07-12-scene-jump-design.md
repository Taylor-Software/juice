# Journal scene jump — design

**Date:** 2026-07-12
**Source:** QoL assessment #7 — after 200+ entries, scrolling is the only way
back to old material; the data (scene dividers) already exists.

## Design

- **Entry point:** the HUD's always-visible scene line is now tappable
  (`hdr-scene-jump`) and opens `showSceneJumpSheet`
  (`lib/features/scene_jump_sheet.dart`) — every scene divider, newest first,
  title + one-line description snippet.
- **Jump:** tapping a row sets the one-shot `journalRevealProvider` (entry id)
  and routes to the Journal. The journal consumes it post-frame and runs
  `_revealEntry`: clears filters/search (the target must be in `visible`),
  tags the target tile with a GlobalKey, then **scroll-hunts** the lazy
  reverse ListView — stepping the viewport ~90% per frame toward
  maxScrollExtent until the key mounts — and finishes with
  `Scrollable.ensureVisible` centring it. A guard caps the walk; plain
  `ListView` has no scroll-to-index and the lean-stack rule rules out
  `scrollable_positioned_list`.

## Tests

`test/scene_jump_test.dart`: a scene buried under 40 filler entries is not
built initially, becomes visible after setting the reveal provider, and the
one-shot request is consumed (scene dividers render uppercased in Text.rich —
asserted via `findRichText`).
