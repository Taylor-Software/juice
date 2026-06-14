# Hexcrawl H3 — Dungeon Map Generation — Design

**Date:** 2026-06-14
**Status:** Approved (brainstorm) — ready for implementation plan
**Depends on:** H1 (`hexcrawl` flag, `HexcrawlData`, build rail), the existing Dungeon grid + P4b room status

## Goal

When `hexcrawl` is on, generate dungeon rooms with **generic, system-agnostic content** on the
existing Dungeon room grid, two paths: **Crawl** (one room) and **Full** (an N-room dungeon at
once). Parallels H2; reuses the existing `addRoom` placement/corridor logic.

## Generic content (authored, into `assets/hexcrawl_data.json` via `build_hexcrawl.py`)

- `dungeonRoomTypes` (~10): Chamber, Corridor junction, Great hall, Cave, Vault, Shrine, Cell
  block, Pit, Stairway, Flooded room.
- `dungeonContents` (~8): Empty, Monster lair, Trap, Treasure, Puzzle / mechanism, Denizen /
  NPC, Hazard, Curious feature.
- `dungeonDressing` (~10): Rubble-strewn floor, Dripping water, Old bones, Claw marks, A faint
  draft, Mouldering tapestry, A cold spot, Scattered coins, A strange smell, Flickering shadows.

`build_hexcrawl.py.verify()` additionally asserts these three tables are non-empty and have no
duplicates (same rail).

## Engine / state

- `lib/engine/hexcrawl_data.dart` — `HexcrawlData` gains `dungeonRoomTypes`, `dungeonContents`,
  `dungeonDressing` flat-list getters.
- `lib/engine/hexcrawl.dart` — `rollDungeonRoom(HexcrawlData data, Dice dice) → ({String title,
  String detail})`: `title = rollFrom(dungeonRoomTypes)`; `detail = "${rollFrom(dungeonContents)}.
  ${rollFrom(dungeonDressing)}."`. Pure, seeded-testable.
- `MapNotifier` (`lib/state/providers.dart`):
  - `crawlDungeon(HexcrawlData data, Dice dice)` — `final r = rollDungeonRoom(...); await
    addRoom(title: r.title, detail: r.detail, dice: dice);`.
  - `generateDungeon(HexcrawlData data, int count, Dice dice)` — loop `count` × (roll +
    `addRoom`). Reuses the existing grid placement, corridor linking, and current-room update.

## UI

When `hexcrawl` is enabled, the **Dungeon** pane (`DungeonMapPaneState`) shows a gated controls
block: a "New room (hexcrawl)" button (crawl) + a "Generate dungeon (N)" button with a size
stepper (full, clamp 4..30). The existing Juice-oracle "New room" is untouched. Gating reuses
`_lonelogOn()`-style read of `enabledSystems.contains('hexcrawl')`.

## Asserted calls (veto)

- **Authored generic dungeon content** (not lifted), mirroring H1.
- **Reuse `addRoom`** for both paths (no new grid-growth engine — 4-neighbor placement +
  corridors already exist).
- **Crawl = a separate hexcrawl control** alongside the Juice-oracle "New room".

## Testing

- `build_hexcrawl.py` self-verify includes the three new tables.
- `hexcrawl_dungeon_test.dart` (pure, seeded `Dice`): `rollDungeonRoom` title ∈ `dungeonRoomTypes`,
  detail contains a `dungeonContents` entry and a `dungeonDressing` entry.
- `MapNotifier` tests: `crawlDungeon` adds one room with a non-empty title; `generateDungeon(N)`
  adds N rooms (connected via corridors as `addRoom` already guarantees).
- `hexcrawl_data_test.dart` — the three dungeon tables load and are non-empty.
- Widget: the Dungeon hexcrawl controls appear only when the `hexcrawl` flag is on.

## Files

**New:** `test/hexcrawl_dungeon_test.dart`.
**Edit:** `build_hexcrawl.py` + `assets/hexcrawl_data.json`, `lib/engine/hexcrawl_data.dart`,
`lib/engine/hexcrawl.dart`, `lib/state/providers.dart`, `lib/features/map_screen.dart`,
`test/hexcrawl_data_test.dart`.

## Out of scope

H4 local-zoom + site generation. Per-room encounter rolling (H1's generator does that). Mapping
dungeon contents to game-specific monsters/treasure (system-agnostic categories only).
