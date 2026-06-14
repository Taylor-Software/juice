# Home Tabbed Shell — Design

Date: 2026-06-13
Status: Draft (awaiting review)

## Problem

The app's home is a single journal screen with every tool hidden behind a
slide-over launcher overlay (`lib/shared/tool_host.dart`). With 18 tools the
overlay is a flat, searchable list — tools are discoverable only by opening the
panel and hunting. There is no spatial grouping by activity, no persistent
home for related tools, and the two most common actions (write an entry, roll
the dice) are not both on the composer.

Goal: replace the overlay launcher with a persistent **tabbed shell** — five
activity-grouped sections, each with subtabs — so tools live where the player
expects them, and promote the dice roller onto the journal entry line.

## Decisions (locked with the user)

- **Tabs replace the launcher.** The slide-over overlay is retired. Every tool
  gets a home under a tab/subtab. A global **search/jump sheet** in the AppBar
  preserves fast access across all tools.
- **Adaptive shell (approach A).** `NavigationBar` on narrow (mobile),
  `NavigationRail` on wide (web/tablet) for the five sections. Subtabs use
  `TabBar` + `IndexedStack` — never `TabBarView` (see Freeze-safety).
- **Tracking tab mixes regroup + new.** Existing surfaces (Scenes, NPCs,
  Threads, Encounter) regrouped under one tab; **Rumors** and **Tracks** are
  genuinely new features.
- **Split journal|map deferred.** The side-by-side homescreen split and **City
  maps** are out of scope for this design — they are the only pieces that
  reintroduce the unbounded-width freeze class and are isolated to a later
  phase.

## Information architecture

Five top-level destinations. `*` marks a net-new feature; `(later)` is deferred.

1. **Journal** — the existing stream + composer; the home tab. Entry line
   carries the two common actions: **write entry** and **roll dice**. Scene
   creation moves off the composer (see Entry line).
2. **Maps** — subtabs: **World** (existing hex map) · **Dungeon** (existing) ·
   **Journey** (existing Verdant Journey, folded in). *City (later)*.
3. **Party** — subtabs: **Emulator** · **Sidekick** · **Behavior** (the three
   existing party tools).
4. **Tracking** — subtabs: **Scenes** · **NPCs** (existing Characters) ·
   **Threads** (existing) · **Rumors\*** · **Tracks\*** · **Encounter**
   (existing live combat tracker).
5. **Oracles & Tables** — subtabs: **Oracle** (Fate Check / Roll High / Mythic)
   · **Generators** (the five `GeneratorsScreen` sections in one surface) ·
   **Tables** (Table Browser) · **Moves** (Ironsworn/Starforged, only when the
   family is enabled).

AppBar actions (unchanged in spirit): **Search** (global jump sheet, new),
**Help**, **Rulesets** (when Ironsworn enabled), **Campaigns**.

Subtab visibility follows the campaign's enabled systems exactly as the launcher
filtering does today (e.g. Journey hidden without `verdant`, Moves without
`ironsworn`, Party subtabs without `party`). A destination with no visible
subtabs is itself hidden.

## Architecture

### Shell

`HomeShell` (Scaffold) hosts:

- An adaptive nav widget: `NavigationBar` below ~840px width, `NavigationRail`
  at/above it (the same breakpoint `tool_host.dart` already uses for its
  wide/narrow split). The five destinations come from a declarative list.
- A body that is a **keep-alive `IndexedStack`** of the five tab roots, indexed
  by the selected destination. Tab roots stay mounted so their state (and the
  journal's scroll position, composer text, tool state) survives switching —
  preserving the current keep-alive guarantee of `ToolHost`.

Each tab root that has subtabs is a small widget wrapping
`DefaultTabController` + a `TabBar` + an **`IndexedStack`** body keyed to the
controller index. This is the byte-for-byte pattern already in
`map_screen.dart` and `tracker_screen.dart`; those screens slot in directly.
Tracking has six subtabs, so its `TabBar` is `isScrollable: true`; the others
fit fixed-width.

### Tool placement registry

`tool_registry.dart` keeps `ToolDef` and the `builder` functions (the shell
instantiates the same screens). The launcher `group` strings and `toolGroups`
list are replaced by a **destination/subtab mapping**:

```
toolLocation: id -> (Destination destination, String subtab)
```

`Destination` is an enum: `journal, maps, party, tracking, oracles`. The shell
builds each subtab body by looking up the tools whose location matches and
calling their `builder`. System filtering (`toolSystem` + enabled systems) is
unchanged.

### Deep-link navigation (replaces `ToolHost.openToolIfKnown`)

Seven call sites in `journal_screen.dart` open tools today via the overlay
(`open in tool`, `/help`, character/thread taps, header crawl/thread/char
chips). They retarget to a **shell navigator**: a small controller exposed via
Riverpod (or an `InheritedWidget` ancestor) with:

```
void openTool(String id);   // resolves id -> (destination, subtab), selects both
```

`openTool` looks up `toolLocation[id]`, selects the destination on the shell,
and sets the subtab's `TabController` index. Unknown ids are a no-op (matching
today's `openToolIfKnown` contract). Character/thread taps navigate to
Tracking → NPCs / Threads. The journal's `_openThread` in-place filter stays as
is (it filters the journal, not a tool).

### Global search sheet

The AppBar search icon opens a modal bottom sheet reusing the launcher's
existing list logic from `tool_host.dart` (search field + MRU "Recent" row +
grouped results), but tapping a result calls the shell navigator's `openTool`
instead of mounting an overlay. The MRU provider (`toolMruProvider`) is
retained. This is the one piece of `tool_host.dart` that survives — extracted
into a `ToolSearchSheet`; the rest of `tool_host.dart` (the Stack/Offstage
overlay, `PopScope`, keep-alive IndexedStack) is deleted.

### Entry line

The journal composer's `movie_outlined` "New scene" `IconButton`
(`journal_screen.dart:908`) is replaced by a **dice** action that opens the
**Dice Roller as a modal bottom sheet** — instant access without leaving the
journal. The Dice Roller has **no tab home** (its home is the entry line); the
global search "Dice" entry opens the same sheet. Scene creation remains
reachable via the `/scene` slash command (already implemented) and a "New
scene" action in Tracking → Scenes. No scene functionality is lost.

## New features

### Rumors (Tracking → Rumors)

A lightweight per-campaign list of leads/rumors the player has heard but not
resolved. Minimal model: `id`, `text`, `resolved` (bool), optional `note`.
- State: `RumorsNotifier` + `rumorsProvider`, session-scoped key
  `juice.rumors.v1.<sessionId>`.
- UI: list with add/edit/delete, toggle resolved, swipe or menu to remove.
  Mirrors the existing Threads pane's shape for consistency.
- Optional (nice-to-have, can defer within the feature): "Track this rumor?"
  suggestion chips like the journal's entity suggestions — **out of scope for
  v1 of this feature** unless trivially cheap.

### Tracks (Tracking → Tracks)

System-agnostic **progress tracks / clocks** for solo play (Ironsworn-style but
not Ironsworn-gated). Minimal model: `id`, `name`, `filled` (int ticks),
`max` (int, default 10), optional `note`.
- State: `TracksNotifier` + `tracksProvider`, session-scoped key
  `juice.tracks.v1.<sessionId>`.
- UI: list of named tracks; each shows progress (filled/max) with +/- controls;
  add/rename/delete. Reuses the chaos-stepper / counter idioms already in the
  app.
- Deliberately simple: no Ironsworn rank-to-tick tables, no momentum. Just a
  named counter with a cap. (YAGNI — extend only if asked.)

### Scenes (Tracking → Scenes)

Derived, **no new storage**: reads journal entries where
`kind == JournalKind.scene`, lists them newest-first; tapping a row selects the
Journal tab (precise scroll-to-scene is a nice-to-have, not required for v1).
Hosts the "New scene" action that today lives on the composer.

## Persistence & campaign export

Rumors and Tracks add two session-scoped SharedPreferences keys
(`juice.rumors.v1`, `juice.tracks.v1`). Campaign files bump to **schema v3**
(v2 + the two new collections); v2 and v1 still import (new collections default
empty). Round-trip export/import is covered by tests. Nav state (selected
tab/subtab) is **not** persisted — the shell always opens on Journal.

## Freeze-safety

This restructure is mostly freeze-*reducing*: tools move from the loose
`IndexedStack(StackFit.loose)` host into bounded tab bodies under the Scaffold,
which gives tight constraints and **retires the loose-constraint hazard for the
relocated tools**. The standing rule still holds inside the shell:

- Subtab bodies use `TabBar` + `IndexedStack`, never `TabBarView`.
- The deferred **split journal|map** is the only place the unbounded-width trap
  can return (two side-by-side panes); it must be re-audited when built.

See `juice-toolhost-loose-constraints` memory for the full discriminator.

## Phasing (each phase shippable)

- **P1 — Shell scaffold.** Adaptive `NavigationBar`/`NavigationRail` + five
  empty tab roots in a keep-alive `IndexedStack`; Journal is tab 1 (existing
  screen unchanged). AppBar actions preserved. Overlay still present but unused
  by the new nav. Tests: shell renders, tab switching keeps state.
- **P2 — Relocate tools + retire launcher.** Populate Maps/Party/Oracles &
  Tables and Tracking's existing subtabs (Scenes/NPCs/Threads/Encounter) from
  the `toolLocation` map. Add the shell navigator; rewire the 7 deep-link call
  sites. Add the global search sheet (extract from `tool_host.dart`). Delete the
  overlay. Migrate the 3 affected test files. Tests: deep-links navigate; every
  tool reachable by tab and by search.
- **P3 — Entry line.** Swap composer scene button → dice; wire scene creation to
  `/scene` + Tracking → Scenes. Tests: dice reachable from composer; scene flow
  intact.
- **P4 — Rumors.** Model + notifier + persistence + UI + export schema v3.
- **P5 — Tracks.** Model + notifier + persistence + UI + export.
- **Later (out of this design):** split journal|map homescreen; City maps.

## Testing

- Shell widget tests: each destination selects, renders its first visible
  subtab, keeps state across switches; system filtering hides the right
  subtabs/destinations.
- Deep-link tests: `openTool(id)` lands on the correct (destination, subtab) for
  every mapped id; unknown id is a no-op.
- Search sheet: query filters, MRU shows, tap navigates.
- New features: unit tests for Rumors/Tracks notifiers (add/edit/toggle/delete,
  persistence round-trip) + widget tests for their panes.
- Campaign export: v3 round-trip; v2/v1 import with empty new collections.
- `flutter analyze` clean; full suite green. Headless tests cannot reproduce the
  release-web freeze class — freeze-safety rides on the IndexedStack-by-
  construction rule plus the existing on-device verification recipe.

## Non-goals

- Split journal|map view; City maps (deferred).
- New Ironsworn track mechanics (momentum, rank ticks) — Tracks stays a simple
  capped counter.
- Persisting selected tab across launches.
- Re-theming or restyling tools beyond what relocation requires.
