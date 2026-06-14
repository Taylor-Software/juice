# Lonelog Dungeon-Crawling addon (P4b) — Design

**Date:** 2026-06-14
**Status:** Approved (autonomous, goal: continue to completion)
**Depends on:** P1 (lonelog flag)

## Goal

Track per-room status (the Lonelog Dungeon-Crawling addon's core: cleared/looted/locked/…)
on the existing Maps → Dungeon tool, surfaced when the `lonelog` system is on.

## Design

- **Model** — `DungeonRoom` gains `String status` (default `''`, written to JSON only when
  set; tolerant `maybeFromJson`). Backward-compatible. A `kDungeonRoomStatuses` const holds
  the addon's suggested palette (unexplored/active/cleared/looted/locked/trapped/safe/collapsed).
- **State** — `MapNotifier.setRoomStatus(id, status)` (mirrors `appendRoomDetail`); `''` clears.
- **UI** — the room detail card shows a `ChoiceChip` row of the statuses **when `lonelog` is
  on** (`_lonelogOn()` reads `enabledSystems`); tapping sets/clears the room's status.

Exits and a Dungeon Status block are out of scope for this slice (the addon itself says a
visual map beats exit-chains; juice already has the canvas). Canvas colour-by-status deferred.

## Testing
- `dungeon_room_status_test.dart`: status JSON round-trip + default-empty + not-serialized;
  palette uniqueness; `setRoomStatus` updates and persists (and `''` resets).
- Existing map-screen tests confirm the off-path is unchanged.

## Files
**New:** `test/dungeon_room_status_test.dart`.
**Edit:** `lib/engine/models.dart`, `lib/state/providers.dart`, `lib/features/map_screen.dart`.
