# Lonelog Wargaming addon (P4f) — Design

**Date:** 2026-06-14
**Status:** Approved (autonomous, goal: continue to completion)
**Depends on:** P1 (lonelog flag), P3 (journal highlights the emitted block)

## Goal

A per-campaign **unit roster** (the Wargaming addon's `[Unit:Name|size|status]`, units as
groups, not individuals) with a `[BATTLE]`-block journal emit, gated under `lonelog`.

## Scope

Unit roster (name, size, status from the addon palette) + emit a `[BATTLE]` block. The
Battletech-specific richness (per-location armor grid, heat thresholds) and Tn#/Force/Scenario
notation are deferred — this delivers the addon's load-bearing unit-vs-individual model and its
block. A compact new tool, same shape as the Resource tracker.

## Design

- **Model** `Unit {id, name, size, status}` + `kUnitStatuses` palette (Fresh/Steady/Wavering/
  Broken/Routed/Rallied/Pinned/Engaged/Exhausted). Round-trips; empty fields omitted.
- **State** `UnitNotifier extends _PersistedList<Unit>` + `unitsProvider`
  (`juice.units.v1`, in `sessionScopedKeys` + `campaign_io`). `add` / `updateUnit` / `remove`
  (`update` is reserved by `AsyncNotifier`).
- **Serializer** `battleToLonelog(List<Unit>)` → `[BATTLE]` / `[Unit:Name|size|status]` per
  unit (fields joined by `|`, delimiter-sanitized) / `[/BATTLE]`.
- **UI** `BattlePane` — add field, roster list (tap → size field + status chips, delete), and
  an "Add [BATTLE] to journal" button. Gated `Battle` subtab in Tracking + registry `battle`
  tool (`toolSystem['battle']='lonelog'`, route → `(tracking,'battle')`).

## Gating

Rides under the `lonelog` umbrella flag; off for default/legacy campaigns.

## Testing
`lonelog_wargaming_test.dart`: `Unit` round-trip + omit-empty; `battleToLonelog` block shape +
sanitization; palette; `UnitNotifier` add/updateUnit/remove persist. `tool_registry_test`:
`battle` present only with `lonelog`. Tracking tests confirm the off-path is unchanged.

## Files
**New:** `lib/engine/lonelog_wargaming.dart`, `lib/features/battle_pane.dart`,
`test/lonelog_wargaming_test.dart`.
**Edit:** `lib/engine/models.dart`, `lib/state/providers.dart`, `lib/state/campaign_io.dart`,
`lib/features/tracking_tab.dart`, `lib/shared/tool_registry.dart`, `lib/shared/destination.dart`,
`test/tool_registry_test.dart`.
