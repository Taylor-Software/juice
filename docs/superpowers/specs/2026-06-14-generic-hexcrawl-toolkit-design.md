# Generic Hexcrawl / Mapping Toolkit — Design

**Date:** 2026-06-14
**Status:** Approved direction (brainstorm) — H1 ready for implementation plan
**Author:** John Taylor + Claude

## Vision

juice is a **system-agnostic swiss-army-knife for solo TTRPG play** — a configurable play-aid
for whatever game the user brings (D&D, Shadowdark, Cairn, OSR, etc.), not tied to any one
ruleset. This feature adds a **generic mapping / hexcrawl toolkit**: procedural map + content
generation that works with any system because it provides *structure and prompts*, never
game-specific creatures or stats (the specific monster/result is left to the user's game).

SCRAWL (a niche solo RPG) inspired the *procedure*, but **none of its content is imported** —
the toolkit's tables are **authored, curated, system-agnostic** content.

## The two axes

Every map in juice can be built two ways, at four zoom levels:

**Paths**
- **Crawl** — reveal/generate one piece at a time as the player explores (fog-of-war).
- **Full** — generate the entire map/setting in one pass.

**Granularity levels**
- **Region** — the existing ~6-mile hex world map (terrain, sites, weather, travel).
- **Local zoom** — one hex expanded to sub-hexes (finer overland detail; new to juice).
- **Site** — a single landmark/point of interest with its features.
- **Dungeon** — the existing room-grid map (rooms, exits, contents, dressing).

All paths and levels draw from **one shared content library**.

## Architecture (mirrors the Verdant data rail)

- **Content asset** — `build_hexcrawl.py` → `assets/hexcrawl_data.json`: authored,
  self-verified, system-agnostic tables. A `HexcrawlData` Dart model + `hexcrawlDataProvider`.
- **Generation engine** — pure Dart (`lib/engine/hexcrawl.dart`), testable against a seeded
  `Dice`. Two reusable modes: `crawl` (produce one cell/room/site) and `full` (produce a whole
  map at a level). The engine is level-parameterized; both modes share the same table picks.
- **Surfaces** — a generic exploration-table **generator screen** (roll any table → log to
  journal), plus per-level map integration (region → existing hex map; dungeon → existing room
  grid) with a **crawl/full** control.
- **Gating** — a `hexcrawl` opt-in feature flag (not in `kAllSystems`; surfaced in New-Campaign
  + Edit-systems), consistent with the "pick your mix" configurability. Lives under the **Maps**
  tab beside the world map + Verdant.

## Roadmap (each phase its own spec → plan → build)

- **H1 — Foundation + exploration-table generator (THIS spec).** The `hexcrawl` flag, the
  `build_hexcrawl.py` rail, the universal/region content (terrains, climate→terrain,
  neighbouring-terrain weights, weather, hazards, site-types, region features, abstract
  encounter categories), the `HexcrawlData` model + provider, and a generator screen that rolls
  any table and logs results. The shared foundation every later phase consumes.
- **H2 — Region map generation, both paths.** Crawl-reveal (generate a hex as you travel:
  terrain via neighbouring-terrain, sites, weather) vs full-generate (a whole region of hexes),
  on the existing hex map. Establishes the reusable crawl/full engine.
- **H3 — Dungeon map generation, both paths.** Crawl room-by-room vs full dungeon, on the
  existing dungeon grid; adds dungeon room-shape/contents/dressing tables to the asset.
- **H4 — Local-zoom + Site generation, both paths.** Sub-hex and single-site generation; adds
  their content tables.

## H1 — detail (first slice)

### Content asset `assets/hexcrawl_data.json` (authored, system-agnostic)
- `terrains` — ~12–16 generic terrains `{key, name, climates[], travel: {difficulty, note},
  features[]}` (arctic, badlands, coast, desert, forest, hills, jungle, marsh, mountains,
  plains, ruins-waste, taiga, tundra, water…).
- `climateToTerrain` — per climate (`cold|temperate|hot`), a weighted starting-terrain table.
- `neighbouringTerrain` — per terrain, weighted adjacent-terrain table (drives H2's map growth).
- `weather` — generic weather d-table (clear/overcast/rain/storm/fog/snow/heat/wind/…).
- `hazards` — generic hazards (rockfall/flood/mire/exposure/lost/blocked-path/…).
- `siteTypes` — generic landmarks (cave/ruin/tower/shrine/spring/camp/monolith/settlement/…).
- `regionFeatures` — "what's notable about this hex" prompts.
- `encounterCategories` — abstract categories (predator / sapient threat / hazard /
  traveller-NPC / find / lair / nothing) — the *specific* result is the user's game.

`build_hexcrawl.py` self-verifies: unique keys; every `neighbouringTerrain`/`climateToTerrain`
entry references a defined terrain; weighted tables have positive integer weights; non-empty
tables. Same rail as `build_verdant.py` — script is source of truth, never hand-edit the JSON.

### Model / engine / UI
- `lib/engine/hexcrawl_data.dart` — `HexcrawlData` + typed rows + `load()`.
- `lib/engine/hexcrawl.dart` — pure helpers: `rollTerrain(climate)`, `rollNeighbour(terrain)`,
  `rollWeather()`, `rollHazard()`, `rollSiteType()`, `rollEncounterCategory()`, each taking a
  `Dice` and returning a typed result (weighted-pick logic lives here, testable).
- `lib/state/providers.dart` — `hexcrawlDataProvider` (FutureProvider).
- `lib/features/hexcrawl_screen.dart` — generator screen: pick a table (terrain/weather/site/
  hazard/encounter/feature), roll, show result, "log to journal". Gated under `hexcrawl`,
  a subtab under Maps. Read-only-ish; honours the loose-constraint rules (no TabBarView / no
  non-flex Material buttons under unbounded width).
- Registry `hexcrawl` ToolDef gated `hexcrawl` + route + Maps subtab; New-Campaign +
  Edit-systems checkbox.

### Testing
- `build_hexcrawl.py` self-verify passes.
- `hexcrawl_test.dart` — weighted-pick helpers are deterministic against a seeded `Dice`;
  every climate yields a defined terrain; neighbouring picks reference defined terrains.
- `hexcrawl_data_test.dart` — asset loads with expected shapes (file fixture).
- Gated generator-screen widget test (provider-overridden, per the rootBundle-hang rule).
- Registry/gating tests: `hexcrawl` tool present only when the flag is enabled.

## Asserted choices (open to change)
- **Authored generic content**, not SCRAWL's — system-agnostic + copyright-clean.
- **`hexcrawl` opt-in flag**, Maps placement.
- **H1 first** (content + table-roller), then H2 region / H3 dungeon / H4 local+site, each adding
  its content and the crawl/full generation for that level. The crawl/full engine is built once
  in H2 and reused.

## Out of scope (H1)
- The actual two-path map generation (H2–H4) — H1 ships the content + a plain table-roller.
- Any game-specific creatures/stats. Local-zoom and site *maps* (H4).
