# First-Run Start Flow — design

**Date:** 2026-07-11
**Source:** tool-evaluation audit F1
(`docs/superpowers/audits/2026-07-11-tool-evaluation-audit.md`).

## Problem

`SessionsNotifier.build()` fabricates a `Campaign 1` session on first run
(needed: every provider assumes an active session; legacy data migrates into
it). But the launcher then presents **Continue · Campaign 1** as the primary
CTA — so a brand-new user is routed past the creation wizard, the ruleset
pick, and the kit path, into a legacy-shaped campaign (null `enabledSystems`
→ `kAllSystems`). All the wedge onboarding (Phases 0–3) is only reachable via
the low-key "New campaign" row.

## Design

Detect the **pristine first-run state** in the launcher and swap the primary
path to the wizard. No change to `SessionsNotifier.build()` — the default
session keeps satisfying the active-session invariant; we re-route around it
in UI and clean it up once a real campaign exists.

- **Pristine predicate** (launcher-local): exactly one session AND
  `active == 'default'` AND `activeMeta.name == 'Campaign 1'` AND the journal
  is empty. Legacy migration fills the journal → not pristine. A rename or
  any played entry → not pristine (normal launcher).
- **Pristine launcher UI:**
  - Primary CTA `launcher-start-first`: **"Start your first adventure"** →
    opens the existing `NewCampaignDialog` (same `_new` path, kit step
    included).
  - The "Continue · Campaign 1" button, the Campaigns list, and the
    duplicate "New campaign" row are hidden.
  - Escape hatch `launcher-skip-blank`: a low-key "Skip — open a blank
    campaign" text button → the normal `_resume` path into Campaign 1.
  - "Import from file" stays.
- **Cleanup on first create:** `_new` captures `wasPristine` before showing
  the wizard; after a successful `create(...)` it calls
  `sessions.remove('default')` so the placeholder never pollutes the
  campaign list. (`remove` already handles non-active ids, purges scoped
  keys, and refuses when only one session exists.) The funnel/kit/roster
  branches all get the cleanup.
- Import path: after a successful import from pristine state the same
  cleanup applies (import creates its own session).

## Not doing

- No zero-session `SessionsState` (too many active-session invariants).
- No changes to the shell drawer's New-campaign path — pristine state is
  only reachable through the launcher.
- No welcome-card copy change (already states the premise).

## Success criteria

- Fresh install: launcher shows Start-first CTA, no Continue, no campaign
  list; wizard create lands in the new campaign and `Campaign 1` is gone.
- Skip path: taps into blank Campaign 1; on next launch (journal empty,
  still pristine) Start-first still shows.
- Played/renamed/legacy states: launcher unchanged from today.
- All existing launcher/backup-nudge/welcome tests pass (updated where they
  assumed the Continue button in a pristine state).
