# Settlement map generator (map hierarchy epic) — design

Status: **P1 shipped.** P2/P3 deferred (recorded below).

## Problem

The maps feature had a world hex map and dungeon sites anchored to hexes, but
**no settlement map structure** — only a `settlement()` oracle that rolled a
name/establishment/artisan/news table. The player asked for a city/town
generator, links across map levels (world → city/town/region → building →
dungeon), and dungeons at any level of the map.

## P1 (shipped)

A **Settlement map site** parallel to `DungeonSite`, plus a generator, on a new
**Maps → Town** subtab.

- **Model** (`models.dart`):
  - `Building {id, name, type, note}` — one location inside a settlement
    (facts-only freeform; JSON omits empty fields).
  - `SettlementSite {id, name, kind, buildings, note, anchorHexCol/Row}` — a flat
    list of buildings, optionally anchored to a world hex (`hasAnchor`).
  - `MapState.settlements` + `activeSettlementId` (+ `activeSettlement` getter,
    `settlementAnchoredAt`). JSON `settlements`/`activeSettlement` omitted when
    empty → legacy byte-stable; the existing `juice.map.v1` key is reused (no new
    key).
- **Oracle** (`oracle.dart`): `settlementName()` + `buildingType()` single-pick
  helpers over the existing authored `settlement_*` tables (no new data rail,
  facts-only).
- **State** (`MapNotifier`): `generateSettlement(oracle, {anchor, buildingCount})`
  (name + N buildings, made active), `addSettlement`, `switchSettlement`,
  `anchorSettlementHere` (anchors the active unanchored settlement, else
  generates a new one at the hex), `unanchorSettlement`, `renameSettlement`,
  `setSettlementKind`/`setSettlementNote`, `removeSettlement` (reassigns active),
  and building CRUD (`addBuilding`/`updateBuilding`/`removeBuilding`) via a shared
  `_updateSettlement`.
- **UI** (`settlement_pane.dart`, Maps → Town): a settlement switcher (when >1),
  Generate town / New buttons, name+kind header with rename/delete, an anchor
  chip (anchors to the current crawl hex when set, shows the pinned hex + Unlink
  when anchored), and a building list with add/edit/delete.

Covered by `test/settlement_test.dart` (model + notifier) and
`test/settlement_pane_test.dart` (widget).

## Deferred

- **P2 — cross-nesting links.** Let a `Building` link to a `DungeonSite`
  (building → dungeon "Enter") and generalize `LocationRef` to address a
  settlement/building (so journal entries, encounters, and places can pin inside
  a town). Add a world hex **"Town here"** detail-card chip (mirrors the dungeon
  chip) for anchoring/creating a settlement directly from the map. "Dungeons at
  any level" = allow `DungeonSite.anchor` to reference a building, not only a hex.
- **P3 — richer generation.** Authored town tables (size, government, districts,
  notable NPCs) via `build_oracle.py`; a rendered settlement map canvas
  (districts/streets) instead of a building list; region tier between world and
  town.
