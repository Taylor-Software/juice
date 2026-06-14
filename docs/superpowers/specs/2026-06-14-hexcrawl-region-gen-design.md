# Hexcrawl H2 — Region Map Generation — Design

**Date:** 2026-06-14
**Status:** Approved (brainstorm) — ready for implementation plan
**Depends on:** H1 (`hexcrawl` flag, `HexcrawlData`, the pick engine)

## Goal

When the `hexcrawl` feature is on, generate **terrain + sites across the shared World hex
map**, two paths:
- **Crawl** — reveal the next hex; its terrain is rolled from an adjacent generated hex via
  the neighbouring-terrain table, and it may carry a site.
- **Full** — generate a connected region of N hexes in one pass from a climate-seeded start,
  each hex with terrain and possibly a site.

Reuses H1's content + pick engine and juice's existing World hex map.

## Integration (reuse existing infra)

- **Canvas:** the existing World hex map — `HexMapPane` (`lib/features/map_screen.dart`),
  `MapState.hexes`, `HexCell`.
- **Model:** `HexCell` gains `String? site` (the hexcrawl site-type on this hex; null = none),
  with `copyWith`/`toJson`/`fromJson` (backward-compatible — omitted from JSON when null).
  Generated terrain reuses the existing `HexCell.terrain` string field.
- **Engine:** `lib/engine/hexcrawl_map.dart` (pure, no Flutter):
  - `List<HexNeighbour> hexNeighbours(int col, int row)` — the 6 odd-q offset neighbours.
  - `RegionResult generateRegion({required HexcrawlData data, required String climate,
    required int count, required Dice dice})` — grows a connected set of `count` hexes from a
    climate-seeded start (each new hex's terrain = `rollNeighbour` from an already-placed
    adjacent hex), each hex rolled for a site (chance + `siteTypes` pick). Returns a list of
    `{col,row,terrainKey,site?}` relative to (0,0).
  - `({String terrain, String? site}) rollCrawlHex(HexcrawlData data, String fromTerrain,
    Dice dice)` — the single-step crawl pick (neighbour terrain + optional site).
  - Site chance: roll `dice.dN(6)`; `<= 2` → a site (`rollFrom(siteTypes)`), else none.
- **State:** `MapNotifier` (`lib/state/providers.dart`):
  - `crawlHexcrawl(HexcrawlData, String climate, Dice)` — reveal the next hex (existing
    `nextHexPosition` positioning); its terrain = `rollCrawlHex` from the current hex's terrain
    (or a climate-seeded terrain if the current hex has none); set `terrain` + `site`; advance
    current.
  - `generateRegion(HexcrawlData, String climate, int count, Dice)` — place the generated
    region's hexes (offsets anchored at the current hex or origin), each with terrain + site;
    set current to the start.
- **UI:** when `hexcrawl` is enabled, `HexMapPane` shows a **hexcrawl controls block** — a
  climate `ChoiceChip` row, a "Reveal next (hexcrawl)" button (crawl), and a "Generate region"
  button with a small size stepper (full). The `_HexPainter` palette is **extended** to color
  all 12 hexcrawl terrain keys (union with the existing Verdant palette), and draws a small
  **site marker** (dot) on hexes with `site != null`. The existing Juice/Verdant `_travel`
  control is untouched.

## Asserted scope calls (veto)

- **One terrain + at most one site per hex** (`HexCell.terrain` + new `HexCell.site`). Whichever
  system generated a hex's terrain wins; no multi-terrain.
- **Site chance d6 ≤ 2** (~1/3 of hexes) — simple, generic; tunable in the engine later.
- **Region anchored at the current hex** (or origin if none); grows to `count` connected hexes.

## Testing

- `hexcrawl_map_test.dart` (pure, seeded `Dice`): `hexNeighbours` returns 6 distinct cells;
  `generateRegion(count: N)` yields exactly N **connected** hexes, all with terrains defined in
  `HexcrawlData`, sites (when present) drawn from `siteTypes`, deterministic per seed;
  `rollCrawlHex` returns a defined neighbour terrain.
- `HexCell` `site` JSON round-trip + omitted-when-null (model test).
- `MapNotifier` tests: `crawlHexcrawl` adds one hex with a defined terrain and advances current;
  `generateRegion(N)` populates N hexes with terrain.
- Palette test: every hexcrawl terrain key resolves to a color.
- Widget: the hexcrawl controls appear only when the `hexcrawl` flag is on (off-path unchanged).

## Files

**New:** `lib/engine/hexcrawl_map.dart`, `test/hexcrawl_map_test.dart`.
**Edit:** `lib/engine/models.dart` (`HexCell.site`), `lib/state/providers.dart`
(`crawlHexcrawl`, `generateRegion`), `lib/features/map_screen.dart` (hexcrawl controls + palette
+ site marker), `test/map_screen_test.dart` or a new map-notifier test.

## Out of scope (later phases)

H3 dungeon gen, H4 local-zoom + site detail. Multi-site hexes, named/persistent sites, and
encounter rolling per hex (H1's generator handles encounters on demand).
