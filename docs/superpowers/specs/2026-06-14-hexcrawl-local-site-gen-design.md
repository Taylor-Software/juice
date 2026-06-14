# Hexcrawl H4 — Local-Zoom + Site Generation — Design

**Date:** 2026-06-14
**Status:** Approved (brainstorm) — ready for implementation plans
**Depends on:** H1 (`hexcrawl` flag, `HexcrawlData`, build rail), H2 (region hex map, `HexCell.site`,
`_HexPainter`, `rollNeighbour`), H3 (dungeon grid placement/painter — reused for the site interior)

## Goal

The final two granularity levels of the generic Hexcrawl toolkit, **inline on the World map**, each
with both paths (**Crawl** = reveal one piece at a time, **Full** = generate the whole thing):

- **Local zoom** — expand one revealed hex into a **7-hex flower** (its terrain up close).
- **Site** — a landmark on a hex gets a generated **detail writeup** (a card) and, on **Enter**, a
  small **interior map**.

All gated by the existing `hexcrawl` flag. All content is authored, system-agnostic, via
`build_hexcrawl.py` (never hand-edit the JSON). System-agnostic means structure + prompts only —
never game-specific creatures/stats.

## Decisions (settled in brainstorm)

- **Site = card + Enter** (writeup card on the hex, plus an interior map behind an Enter button).
- **Local zoom = 7-hex flower** (center sub-hex = parent terrain; 6 ring sub-hexes rolled finer).
- **Inline on the World map** — no new subtabs. Tapping a *revealed* hex selects it and shows a
  detail card below the canvas; the canvas itself switches mode (region → flower → interior) with a
  Back control. One `InteractiveViewer`, no modal dialog (honours the loose-constraint freeze rule:
  no TabBarView / no non-flex Material buttons under unbounded width).

## Slices (each its own plan → PR, independently shippable)

- **H4a — Local zoom (flower).** Sub-hex `local` field + `LocalCell`; `localFeatures` content;
  `rollLocalCell`; `crawlLocal`/`generateLocal`; flower canvas mode + controls.
- **H4b — Site detail card.** `siteLines` field; `siteOccupants`/`siteHooks`/`siteFeatures`
  content; `rollSiteLine`/`rollSiteDetail`; `crawlSite`/`generateSite`; hex-select detail card.
- **H4c — Site interior (Enter).** `siteAreas` field + `SiteArea`; `siteAreaTypes` content;
  `rollSiteArea`; `crawlSiteArea`/`generateSiteInterior`; interior canvas mode (reuses the dungeon
  grid placement + painter logic, but stored on the hex — never `MapState.rooms`, so the separate
  Dungeon tab is never clobbered).

## Data model (`lib/engine/models.dart`) — additive to `HexCell`

Three new optional fields, each omitted-when-empty in JSON, tolerant in `maybeFromJson`, with a
`clearX` flag in `copyWith` (the house pattern). `col`/`row` stay immutable.

```dart
// H4a
class LocalCell {                       // one ring sub-hex of the flower
  final int slot;                       // 0..5 ring position (clockwise from north)
  final String terrain;                 // hexcrawl terrain key
  final String feature;                 // a localFeatures entry
}
// on HexCell: final List<LocalCell> local;   // [] = not zoomed; <6 = partial crawl

// H4b
// on HexCell: final List<String> siteLines;  // revealed writeup lines, in reveal order

// H4c
class SiteArea {                        // one interior area (mini dungeon grid)
  final int x;
  final int y;
  final String name;                    // a siteAreaTypes entry
}
// on HexCell: final List<SiteArea> siteAreas; // [] = interior not generated
```

The flower **center** is not stored — it is the parent hex's own `terrain`. Site **type** stays the
existing `HexCell.site` string; `siteLines` is the generated detail on top of it.

## Generic content (authored → `assets/hexcrawl_data.json` via `build_hexcrawl.py`)

Flat string tables (same rail as H3's dungeon tables), each added to `build()`, to the `verify()`
non-empty/no-dup flat-table list, and to a `HexcrawlData` `_flat()` getter:

- **H4a** `localFeatures` (~10): "A trickling stream", "A rocky outcrop", "A dense thicket",
  "A quiet clearing", "Fresh animal tracks", "A fallen tree", "A muddy hollow", "A worn game trail",
  "An old fire-pit", "A weathered marker".
- **H4b** `siteOccupants` (~10): "Unoccupied / abandoned", "A lone hermit or hold-out",
  "A small band", "A territorial beast", "A larger warband", "Scavengers", "A guardian",
  "Pilgrims or travellers", "Something unnatural", "Recently emptied".
- **H4b** `siteHooks` (~10): "Something valuable is hidden here", "A captive needs freeing",
  "A rival is also seeking it", "It guards a passage onward", "A curse or ill omen hangs over it",
  "It holds a clue to a larger mystery", "It is not what it appears", "A debt is owed here",
  "It is slowly being reclaimed", "An old promise binds it".
- **H4b** `siteFeatures` (~10): "A defensible approach", "Signs of a struggle", "A hidden cache",
  "A source of fresh water", "Faded markings or writing", "A collapsed section", "An unusual smell",
  "Evidence of recent use", "A commanding view", "An uneasy quiet".
- **H4c** `siteAreaTypes` (~10): "Entrance", "Antechamber", "Main hall", "Storeroom",
  "Inner sanctum", "Collapsed section", "Hidden alcove", "Well or shaft", "Living quarters",
  "Lookout".

## Engine (`lib/engine/hexcrawl.dart`) — pure, seeded-testable

- **H4a** `rollLocalCell(HexcrawlData data, String centerTerrain, int slot, Dice dice) → LocalCell`
  — `terrain = rollNeighbour(centerTerrain)?.key ?? centerTerrain`; `feature = rollFrom(localFeatures)`.
- **H4b** `rollSiteLine(HexcrawlData data, int index, Dice dice) → String` — `index 0` → `"Held by: " +
  rollFrom(siteOccupants)`; `index 1` → `"Hook: " + rollFrom(siteHooks)`; `index ≥ 2` →
  `"Feature: " + rollFrom(siteFeatures)`. `rollSiteDetail(data, dice) → List<String>` returns the
  first 4 lines (occupant, hook, 2 features) for Full.
- **H4c** `rollSiteArea(HexcrawlData data, Dice dice) → String` — `rollFrom(siteAreaTypes)`.

## State (`MapNotifier`, `lib/state/providers.dart`)

Each operates on the selected hex `(col,row)`, `copyWith`-ing that `HexCell` in `MapState.hexes`
(no-op if the hex is absent). Mirrors the H2/H3 crawl/full pairing.

- **H4a** `crawlLocal(col,row, data, dice)` — append `rollLocalCell(...)` for the next free `slot`
  (0..5; no-op at 6). `generateLocal(col,row, data, dice)` — fill all 6 ring slots.
- **H4b** `crawlSite(col,row, data, dice)` — append `rollSiteLine(data, siteLines.length, dice)`
  (cap 5). `generateSite(col,row, data, dice)` — set `siteLines = rollSiteDetail(...)`.
- **H4c** `crawlSiteArea(col,row, data, dice)` — append one `SiteArea` placed via the existing
  `nextRoomPosition` grid walk over the current `siteAreas`. `generateSiteInterior(col,row, count,
  data, dice)` — add `count` areas (clamp ~3..12).

## UI (`lib/features/map_screen.dart`, `HexMapPaneState`) — inline, gated

- New state: `_selCol/_selRow` (selected revealed hex) and `_zoomMode ∈ {region, flower, interior}`.
- **Tap**: an *unrevealed neighbour* still reveals (unchanged); a *revealed* hex now **selects** it
  (`_selCol/_selRow`, `_zoomMode = region`) → shows a detail card below the canvas.
- **Detail card** (reuses the Dungeon detail-card pattern): terrain name; if `site != null`, the
  site type + the `siteLines` writeup; gated `hexcrawl` controls — **Crawl site** / **Full site**
  (H4b), **Enter** (H4c, only when a site exists), **Zoom in** (H4a, only when the hex has a
  `terrain` — the flower center derives from it; legacy env-only hexes don't offer it). Each
  loggable to journal.
- **Canvas mode** (the `Expanded` content switches by `_zoomMode`, conditional widget, not
  TabBarView):
  - `region` → existing `_HexPainter`.
  - `flower` → a 7-hex flower painter (center = parent terrain; 6 ring slots from `local`); controls
    **Reveal sub-hex** (crawl) / **Fill hex** (full) + **Back**.
  - `interior` → the dungeon-grid painter logic over `siteAreas`; controls **Reveal area** (crawl) /
    **Generate interior (N)** (full) + **Back**.
- All new buttons live in `Wrap`/`Flexible` (loose-constraint safe) and are gated by
  `_hexcrawlOn()` (the existing `enabledSystems.contains('hexcrawl')` read).

## Testing

- `build_hexcrawl.py` self-verify covers all five new flat tables (non-empty, no dup).
- `hexcrawl_data_test.dart` — the five tables load and are non-empty.
- Engine (pure, seeded `Dice`): `rollLocalCell` terrain is a defined key + feature ∈ `localFeatures`;
  `rollSiteLine` label-by-index + body from the right table; `rollSiteDetail` returns 4 ordered
  lines; `rollSiteArea` ∈ `siteAreaTypes`.
- `MapNotifier` (mock prefs, seeded `Dice`): `crawlLocal` adds one ring cell and caps at 6;
  `generateLocal` fills 6; `crawlSite` appends one line and caps; `generateSite` sets 4 lines;
  `crawlSiteArea` adds one area (valid grid coords); `generateSiteInterior(N)` adds N. Each targets
  a selected hex and leaves other hexes + `MapState.rooms` untouched.
- Model round-trip: `HexCell` with `local`/`siteLines`/`siteAreas` survives toJson→maybeFromJson;
  empty collections omitted.
- Widget (provider-overridden, per the rootBundle-hang rule): selecting a revealed hex shows the
  card; the H4 controls appear only when `hexcrawl` is on; Zoom-in / Enter switch canvas mode and
  Back returns to region.

## Files

**New:** `test/hexcrawl_local_test.dart`, `test/hexcrawl_site_test.dart` (engine + notifier),
`test/hexcrawl_hex_detail_test.dart` (widget). **Edit:** `build_hexcrawl.py` +
`assets/hexcrawl_data.json`, `lib/engine/models.dart`, `lib/engine/hexcrawl_data.dart`,
`lib/engine/hexcrawl.dart`, `lib/state/providers.dart`, `lib/features/map_screen.dart`,
`test/hexcrawl_data_test.dart`, `CLAUDE.md` (note the new tables).

## Asserted calls (veto)

- **Authored generic content** (not lifted), mirroring H1–H3.
- **Site interior stored on the hex**, reusing the dungeon **grid logic** (`nextRoomPosition`,
  painter), NOT `MapState.rooms` — keeps the Dungeon tab independent.
- **Inline canvas-mode switch** over a modal — avoids InteractiveViewer gesture conflict + the
  unbounded-width freeze.
- **Flower center is derived** from the parent hex's terrain (not stored).

## Out of scope

- New subtabs (decided against). Region/dungeon changes (H2/H3 are done).
- Persisting per-hex weather/encounters (H1's generator covers ad-hoc rolls).
- Game-specific creatures/treasure/stats (system-agnostic categories only).
- Nested zoom (a sub-hex of a sub-hex) or multi-site hexes.
