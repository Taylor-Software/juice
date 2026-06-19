# GM / Party Mode — Design

**Status:** Approved

## Problem

A solo player is often both the GM and the party, but at any moment they're
*focused* on one role: running the world (GM) or playing their character(s)
(Party). The 5-verb shell shows everything for both roles at once, which is more
than the current focus needs. This thread adds a per-campaign **mode** that
declutters each verb's sub-options to the active role, with a quick toggle to
switch. (Deferred from the verb-nav foundation.)

## Scope

**In:**
- A `CampaignMode { gm, party }` stored per campaign (default chosen at
  creation; defaults to `party`).
- A quick **GM/Party toggle** in the shell app bar that flips the active
  campaign's mode (persisted).
- Role-based filtering of *sub-options* (not whole verbs): the active mode shows
  `both`-tagged options + its own role's, and hides the other role's. Applies to
  the Track subtabs and the Sheet `Moves` subtab.
- A light landing default: on opening a campaign, GM lands on Journal, Party on
  Sheet.

**Out (later / v2):**
- Re-aiming the assistant rail's suggestions per mode (a separate, assistant
  thread).
- Per-mode Ask default tab (Ask stays system-driven).
- Hiding whole verbs, or a third "both/auto" mode.
- Per-mode generator/affordance filtering.

## Role tags (the filter)

Each filterable sub-option carries a role affinity: `gm` | `party` | `both`.
`visibleForMode(role, mode)` = `role == both || role == mode`.

| Surface | both (always) | gm-only | party-only |
|---|---|---|---|
| **Track** subtabs | Scenes · Threads · Tracks · Encounter · Resources · Battle | Rumors | Emulator · Sidekick · Behavior |
| **Sheet** subtabs | Characters | — | Moves |

Notes:
- Party subtabs (Emulator/Sidekick/Behavior) are already gated by the `party`
  *system*; mode filtering layers on top (both must pass to show).
- `Resources`/`Battle` are lonelog-gated and role-neutral (`both`).
- Ask (Oracle/Tables) and Map/Journal are unaffected by mode.

## Components

### Model — `lib/engine/models.dart`

Add `enum CampaignMode { gm, party }` with a JSON-safe name, and a
`CampaignMode mode` field on the campaign metadata. Store it on `SessionMeta`
(it's campaign-level config alongside `systems`, persisted in the sessions
registry `juice.sessions.v1`), defaulting to `CampaignMode.party` when absent
(legacy campaigns). Update `SessionMeta.toJson`/`fromJson` (omit when default,
parse by name with a `party` fallback).

### Notifier — `lib/state/providers.dart`

- `modeProvider` (a `Provider<CampaignMode>`) reads the active
  `SessionMeta.mode` (fallback `party`).
- `SessionsNotifier.setMode(String sessionId, CampaignMode)` updates the active
  campaign's meta + persists (mirrors the existing `editSystems`).

### Role filter — `lib/engine/role_tags.dart` (new, pure)

A small pure module: a `SubtabRole { gm, party, both }` map for the role-tagged
subtab keys (`rumors → gm`; `emulator/sidekick/behavior → party`; everything
else `both`) and `moves → party` for Sheet; plus
`bool visibleForMode(SubtabRole role, CampaignMode mode)`. Pure + unit-testable;
no Flutter import. The Track/Sheet tabs consult it.

### Track / Sheet wiring

- `lib/features/tracking_tab.dart`: when building the subtab list, additionally
  drop any subtab whose role tag is hidden for the active `mode` (read from
  `modeProvider`). The existing `party`/`lonelog` system gates stay; mode is an
  additional filter.
- `lib/features/sheet_tab.dart`: in the family-non-empty branch, include the
  `moves` subtab only when `mode == party` (AND family non-empty, as today).
  When Moves is filtered out and family is non-empty, render just
  `CharactersPane` (the bare-pane branch), so Sheet never shows a one-tab host.

### Toggle — `lib/shared/home_shell.dart`

Add a segmented GM/Party control (or an `IconButton` that flips) to the app-bar
actions, keyed `mode-toggle`, calling `setMode`. Reflects the active mode.

### Landing default — `lib/shared/home_shell.dart`

When a campaign is opened/activated, set the initial shell destination from
mode: GM → `Destination.journal`, Party → `Destination.sheet`. Apply once on
activation (don't override the user's subsequent navigation). Keep it minimal —
if this proves fiddly with `shellRouteProvider` persistence, the filtering is the
core deliverable and the landing default can be dropped without affecting it.

## Data flow

`SessionMeta.mode → modeProvider → Track/Sheet subtab filter (via role_tags) +
app-bar toggle`. Toggle → `SessionsNotifier.setMode` → persisted →
providers rebuild → subtabs re-filter.

## Error handling

- Legacy campaigns (no `mode` in JSON) → `party` default; no migration.
- Active subtab filtered out by a mode switch: the SubtabHost clamps its index
  (existing behavior) so it falls back to the first visible tab — no crash.
- Mode toggle while data loading: reads `valueOrNull` with `party` fallback.

## Extension: tool-discovery surfaces (shipped)

The tab-bar filtering above declutters the visible subtabs, but the parallel
discovery/navigation surfaces were not mode-aware: in GM mode the party-only
tools (party-emulator/sidekick/behavior + moves) and in Party mode the GM-only
Rumors stayed discoverable yet navigated to a now-hidden subtab (SubtabHost
clamps → silent mis-land on the wrong/first tab). Closed by reusing
`visibleForMode` keyed on each tool's `toolLocation` subtab:

- `buildToolRegistry({..., CampaignMode mode = party})` drops a tool when its
  `toolLocation` subtab is role-hidden in `mode` (tab-homeless dice/help are
  mode-neutral). Threaded from the `home_shell` search-sheet call site.
- `ShellRouteNotifier.openTool(id, {CampaignMode? mode})` returns false when the
  resolved subtab is hidden for `mode`, so the caller's "Tool not available"
  snackbar fires instead of mis-landing. Wired at `journal_screen._openTool`
  (covers the journal source-chip re-open of an off-mode tool) and
  `tool_search_sheet._open`.
- `suggestionsFor({..., required bool partyMode})` gates the `make-move`
  suggestion (targets sheet/moves, party-only); `suggestionsProvider` passes
  `mode == party`. (Partially resolves the per-mode assistant-suggestions
  deferral.)

## Testing

- `role_tags_test.dart` — `visibleForMode` truth table; the tag map has the
  expected gm/party/both assignments.
- `models` test — `SessionMeta.mode` round-trips (absent → party; gm persists).
- `mode_provider_test.dart` — `modeProvider` reads the active campaign's mode;
  `setMode` persists and flips it.
- `tracking_tab` widget test — GM mode shows Rumors and hides Emulator/Sidekick/
  Behavior; Party mode the inverse (with `party` system on). Pump the pane with
  `modeProvider`/sessions seeded; never the full shell.
- `sheet_tab` widget test — Moves subtab present only in Party mode (family
  non-empty); GM mode (family non-empty) shows the bare roster.
- `home_shell` test — the `mode-toggle` flips mode + persists; (landing default
  if kept) opening a GM campaign lands on Journal.
- `tool_registry_test` — GM drops party tools + moves; Party keeps them; mode
  defaults to party.
- `shell_route_test` — `openTool` returns false (no nav) for a mode-hidden
  subtab, true when visible, ignores gating when no mode is passed.
- `suggestions_test` / `suggestions_provider_test` — `make-move` needs
  family + focus character + party mode; absent in GM.
- Full suite green; `dart format` + `flutter analyze` clean.

## Docs

- `CLAUDE.md` note: `CampaignMode` on `SessionMeta`, `modeProvider`/`setMode`,
  the pure `role_tags.dart` filter, the app-bar toggle, the Track/Sheet
  role-filtering + per-mode landing. Deferred: per-mode assistant suggestions.
- No new licensed content.
