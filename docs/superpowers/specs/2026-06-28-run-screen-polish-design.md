# Run-screen polish: threads/rumors glance + party-effect bulk (Tier-2)

**Date:** 2026-06-28
**Status:** Design approved (batch consent), pending plan
**Part of:** GM-tool epic, Tier-2 (item 3 of 4). Builds on the Run-screen (#195).
**Note:** the originally-bundled "inline AI interpret" is split into its own
follow-up PR (it needs the OracleSeed/interpretation-sheet plumbing) — this slice
is the two clean run-screen wins.

## Summary

Two additions to the Run-screen:
1. A **Threads/Rumors glance panel** — read-only open threads (+ unresolved
   rumors in GM mode) so the GM sees the live plot while running; tap → the Track
   subtab.
2. A **party-effect bulk button** on the Party panel — apply ±HP and/or
   condition(s) to a selected set of party members in one gesture (reuses
   `CharacterNotifier.applyPartyEffect`).

## Components (`lib/features/run_screen.dart`)

### `_ThreadsRumorsPanel` (ConsumerWidget)

- Reads `threadsProvider` (open threads), `rumorsProvider` (unresolved), and
  `modeProvider` (rumors shown only in `CampaignMode.gm`, matching role_tags).
- Renders `_Panel(key: run-panel-threads, title: 'Threads')`:
  - open threads (up to a few) as tappable rows showing `title` + `progress/
    progressMax`; tap → `shellRouteProvider.goTo(Destination.track, subtab:
    'threads')`. Key `run-thread-<id>`.
  - GM mode + unresolved rumors: a "Rumors" subsection, each tappable → Track
    `rumors`. Key `run-rumor-<id>`.
  - empty (no open threads, and no rumors/not-GM) → `Text('No open threads.',
    key: run-threads-empty)`.
- Placement: right column, after Scene.

### Party-effect bulk button (`_PartyPanel`)

- When the party is non-empty, append an `Effect…` button (key
  `run-party-effect`) below the member rows → `_RunEffectDialog`.
- `_RunEffectDialog` (StatefulWidget): a checkbox list of the party members
  (key `run-effect-target-<id>`), an HP-delta int field (`run-effect-hp`,
  negative = damage), and a conditions text field (`run-effect-conditions`,
  comma-split). Apply (`run-effect-apply`) → pops `({Set<String> ids, int
  hpDelta, List<String> conditions})`; the panel calls
  `applyPartyEffect(ids, hpDelta: …, addConditions: …)`. Empty selection → no-op.
- A minimal inline dialog (NOT the tracker's private `_PartyEffectDialog`); the
  shared logic is the already-public `applyPartyEffect`. DRYing the two dialogs
  is a deferred cleanup.

## Testing (`test/run_screen_test.dart`)

- Threads panel: seed an open thread → `run-thread-<id>` shows its title; tapping
  routes to Track/threads. In party mode, a seeded rumor does NOT show; in GM
  mode it does (`run-rumor-<id>`). Empty → `run-threads-empty`.
- Party effect: seed two PCs with HP tracks; tap `run-party-effect`, check both
  `run-effect-target-<id>`, set `run-effect-hp` to `-3`, Apply → both characters'
  HP dropped by 3 (via `withHpDelta` through `applyPartyEffect`).

## Out of scope (this PR)

- Inline AI interpret on the dice panel (own follow-up PR).
- Extracting/sharing the party-effect dialog with the tracker (DRY cleanup later).
- Editing threads/rumors from the run-screen (read-only glance; edit on Track).
