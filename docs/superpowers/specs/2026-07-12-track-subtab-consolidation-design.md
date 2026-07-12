# Track subtab consolidation — design

**Date:** 2026-07-12
**Source:** QoL/UI assessment — the Track verb carried up to ~11 same-weight
subtabs in one scrolling bar with no hierarchy.

## Design

Two merges cut the bar by two tabs; every legacy route keeps working:

1. **Tasks → Threads.** A task IS a `Thread` with a `Tally`; the standalone
   `TasksPane` duplicated the thread cards' own tally rows. The pane is
   deleted; its name → tally-preset creation flow ports to `ThreadsPane` as a
   `task-new` header button (finite `minimumSize` — the theme's full-width
   FilledButton gotcha). The Loop pane's step-4 task creator is untouched.
2. **People + Places → World.** New `WorldPane`
   (`lib/features/world_pane.dart`): a SegmentedButton over an IndexedStack
   of the existing `PeoplePane`/`PlacesPane` (both stay keep-alive).

**Route compatibility:** `SubtabDef` gains `aliases` — `SubtabHost` resolves
`route.subtab` against key OR aliases. `threads` carries `['tasks']`, `world`
carries `['people', 'places']`, so every existing
`goTo(track, subtab: 'people'/'places'/'tasks')` call site (campaign search,
NPC↔place chips, map "places here", mention taps) lands correctly with zero
call-site changes. `WorldPane` additionally reads/listens to
`shellRouteProvider` to pick the matching segment (mount + live).

## Tests

`test/track_consolidation_test.dart`: new-task flow on ThreadsPane, World
segment toggle + legacy-route segment selection (live and at mount).
`tasks_pane_test.dart` deleted with the pane.
