# UI polish bundle — drawer regrouping, chip explainer, chaos check

**Date:** 2026-07-12
**Source:** tool-evaluation audit item #7 (drawer clutter) + stranger-test
S9 (chaos visibility) and S10b (unexplained tracking chips).

## Changes

1. **Campaigns-drawer regrouping.** The 8 secondary rows (Lonelog export/
   import, table packs, oracle packs, loop kits) fold under one
   `menu-more-io` ExpansionTile ("More import / export…"); the drawer's
   primary actions (New / Export / Import campaign) stay top-level.
   Handlers and per-row keys unchanged inside the group.
2. **Tracking-chip explainer (S10b).** A one-time caption above the journal's
   "Track \<name\>?" chips: *"Names you write become suggestions — tap a chip
   to track it as a character or thread; ✕ just hides it."* Dismissed via
   `chip-help-got-it` → app-global `chipHelpSeenProvider`
   (`juice.chip_help_seen.v1`, same posture as `trackHelpSeenProvider`).
   Laid out as a Row above the chip Wrap (never inside it — the repo's
   Expanded-in-Wrap infinite-width gotcha).
3. **Chaos visibility (S9) — verified already fixed.** The `hdr-chaos` chip
   renders on the HUD's always-visible tier-1 row for Mythic campaigns
   (`play_context_hud.dart`); the steppers live in tier 2. No change needed —
   S9 can be closed.

## Tests

`suggestion_chips_test.dart` gains the explainer show/dismiss/persist test;
`lonelog_campaign_ui_test.dart` updated to expand the group first.
