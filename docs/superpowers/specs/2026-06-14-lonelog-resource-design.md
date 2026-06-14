# Lonelog Resource Tracking addon (P4d) — Design

**Date:** 2026-06-14
**Status:** Approved (autonomous, goal: continue to completion)
**Depends on:** P1 (lonelog flag)

## Goal

A per-campaign inventory tracker (the Resource Tracking addon's `[Inv:Name|qty|props]`),
surfaced as a gated tool when the `lonelog` system is on.

## Scope

Inventory items only (name, quantity, freeform properties) — the addon's core. Wealth
(`[Wealth:]`) and usage-dice are deferred (notable but secondary). A real but **compact**
new tool, following the established `_PersistedList` + subtab pattern.

## Design

- **Model** `InvItem {id, name, qty, props}` (engine/models.dart) — round-trips; `props`
  omitted from JSON when empty.
- **State** `InventoryNotifier extends _PersistedList<InvItem>` + `inventoryProvider`
  (session-scoped key `juice.inventory.v1`, added to `sessionScopedKeys` and `campaign_io`
  validation so it exports/imports). `add` / `adjustQty` (clamped 0..9999) / `setProps` / `remove`.
- **UI** `ResourcesPane` — add field + a list (name ×qty, tap to edit props, `−`/`+` steppers,
  delete). Lives as a **gated `Resources` subtab** in the Tracking tab (added only when
  `lonelog` is on) and as a registry `resources` tool (`toolSystem['resources']='lonelog'`,
  route → `(tracking, 'resources')`).

## Gating

Rides under the `lonelog` umbrella flag (no separate toggle). Since `lonelog` is not in
`kAllSystems`, default/legacy campaigns don't show it; shell/tracking tests with a default
session are unaffected.

## Testing
- `inventory_test.dart`: `InvItem` round-trip + props-omitted; notifier add/adjust(clamp)/
  setProps/remove persist.
- `tool_registry_test`: `resources` present only with `lonelog`.
- Existing tracking-tab tests confirm the off-path (no Resources subtab) is unchanged.

## Files
**New:** `lib/features/resources_pane.dart`, `test/inventory_test.dart`.
**Edit:** `lib/engine/models.dart`, `lib/state/providers.dart`, `lib/state/campaign_io.dart`,
`lib/features/tracking_tab.dart`, `lib/shared/tool_registry.dart`, `lib/shared/destination.dart`,
`test/tool_registry_test.dart`.
