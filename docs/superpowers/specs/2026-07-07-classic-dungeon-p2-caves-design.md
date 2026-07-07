# Classic Dungeon P2 — Caves, A2 Effects, Multi-level — Design

**Date:** 2026-07-07
**Status:** Approved (brainstorm) → writing plan
**Builds on:** `docs/superpowers/specs/2026-07-06-classic-dungeon-generator-design.md`
(P1, shipped PR #250). Same system id (`classic-dungeon`), same license posture
(Roll 4 Ruin © Nocturnal Peacock, CC-BY-NC-SA-4.0, attribution already shipped).

## Summary

Complete the Roll 4 Ruin implementation: the **fantasy-cave branch** (source
tables D–F + natural elements I), **real A2/D2 dungeon-type effects**
(tier bump, treasure bonus, branch crossover), and **multi-level descent**
(stairs/chasms create persisted deeper levels whose depth drives the G2/G3/G4
monster tiers). Caves render **organically** (wobbly perimeter paint, user's
pick) over the same grid/placement engine.

Decisions locked in brainstorm: P2 = caves + A2 effects + multi-level folded
together (user overrode the two-slice recommendation); organic cave paint
(option A) over reskinned rectangles.

## 1. Data rail — `build_dungeon.py` additions

Transcribe the cave branch from the zine (pages 5–7) + natural elements
(page 10), same hand-transcribed-literals + self-check rail:

| Table | Roll | Notes |
|---|---|---|
| D1 | D12 | cave entrance surroundings (row 12 = reroll on A1) |
| D2 | 2D6 | cave type — structured effects like A2 (see below) |
| E1 | D66 | tunnel shape families (`tunnel_families` range map; type-die values 1–3, vertical-offset flavor 1 up / 2 down / 3 none rides detail text) |
| E2 | D6 | tunnel stocking |
| E3 | D20 | tunnel feature |
| E4 | D20 | obstacle (P1's label fallback becomes a real table) |
| E5 | D10 | cavestone (rolled once per cave level; "change of cavestone" rows re-roll it) |
| F1 | D66 | cave shape families (`cave_families`; type-die 4–6, offset 4 none / 5 down / 6 up) |
| F2 | D6 | cave stocking |
| F3 | D20 | cave feature |
| F4 | D20 | special cave |
| F5 | D6 | cave re-stocking |
| I1–I8 | various | secret cave, arcane occurrences, vein, cave curio, interventions, flora, liquid, gas — full tables replacing P1's `label_fallbacks` entries |

**`{lvl:...}` machine tokens.** Level-transition and crossover rows are tagged
structurally in the row text so the generator never text-parses:
- `{lvl:down}` — one level down (e.g. "Way down a floor")
- `{lvl:updown}` — D6: 1–5 down, 6 up (C3 "Stairs (1-5. -1 lvl, 6.+1 lvl)", F3 slope)
- `{lvl:chasm}` — down D4 levels (F4 chasm, C4 hole "-D4 levels")
- `{lvl:cross}` — branch crossover ("Doors to dungeon A-C" / "Door to cave-system D-F", C4 row 14, F4 row 3)

**D2 structured effects** (mirror A2's schema): 2 Crystal Caves … 9 Outpost
(`{"monster_die": 20}` like A2-4's D12 note), 10 Beast Lair
(`{"tier_bump": 1, "vein_bonus": 3}`), 4 Dungeon Entrance
(`{"leads_to_dungeon": true}`), 12 Alien Hive (note-only in P2; combo rolls
deferred). Notes reference tables by name (de-tokenized on display, P1 rule).

**Self-check extends:** row counts (D1=12, D2 keys 2–12, E2/F2/F5=6, E3/E4/F3/F4
=20, E5=10, I3=18, I4/I5/I6/I7/I8 per zine), tunnel/cave family d66 coverage,
`{lvl:*}` token vocabulary is exactly the four above, every new `{ref}` known.
`label_fallbacks` shrinks to only what stays un-shipped.

## 2. Engine

- **`DungeonBranch {dungeon, cave}`** (new enum, `generator.dart`). A room's
  branch is derivable from its `roomType`: `corridor`/`chamber` = dungeon,
  `tunnel`/`cave` = cave. `roomType` gains those two values.
- **Footprints:** tunnels reuse the corridor footprint catalog, caves reuse the
  chamber catalog — the JSON `tunnel_families`/`cave_families` range maps target
  the SAME family ids (zero new geometry; organic look is paint, §4).
- **`DungeonGenContext`** grows `branch`, `depth` (replaces the unused `level`),
  `stone` (cavestone name, cave levels only; empty for dungeon).
- **Type die on the cave branch:** 1–3 tunnel / 4–6 cave, same entry-door-kind
  mapping as P1 (1=locked … 6=locked). Vertical-offset flavor from E1/F1 headers
  rides the room's detail line, not the level model.
- **Depth → monster tier:** depth 1–2 → G2, 3–4 → G3, 5+ → G4, then
  `effect.tierBump` shifts one step (capped at G4). Cave stocking rolls monsters
  from the same G tables (zine: caves use the same monster section).
- **Real H8 treasure:** `rollTreasure(tables, depth, bonus, dice)` — d4 form
  (coins/items/gems) + `d10 + depth − 1 + bonus` row (clamped to the 18-row
  list), then resolves embedded dice notation (`D6`, `2D6`, `*k` multipliers) to
  an actual amount: "Treasure: 340 GP (2D6*25 GP, gems)". Stocking rows that
  reference `{ref:H8}` now roll it for real (replacing the P1 "treasure" label);
  `treasure_bonus` (A2 Cursed ruins +3) and Beast Lair's `vein_bonus` (+3 on I3
  vein rolls) apply.
- **`RoomResult`** grows `levelDelta` (int; 0 = none, from `{lvl}` tokens —
  `updown`/`chasm` roll their die during generation) and `crossoverTo`
  (`DungeonBranch?`, from `{lvl:cross}` and the A2-12/D2-4 stocking effects).
- **Branch inheritance:** a child room generates on its parent room's branch,
  unless the parent carries `crossoverTo` — then the child uses the other
  branch's tables (and its `roomType` records it, so grandchildren continue
  there). The entrance room's branch comes from which Enter button was used.
- **`stockDouble` / A2-4 / A2-5 / A2-6 / A2-8 / A2-9 / A2-11 conditional
  stocking effects:** the "on a 6 on B2/C2" family of A2/D2 effects is
  implemented generically: the effect declares `{"on_stock_6": "<row text with
  refs>"}` in the JSON; when the stocking die rolls 6 ("Nothing (or Type
  effect)"), the generator expands that row instead of "Nothing". This turns the
  P1 note-only effects into real behavior with one mechanism.

## 3. Multi-level model

- **`DungeonLevel {depth, branch, typeName, note, stone, rooms, corridors,
  currentRoomId}`** (models.dart). **`MapState` grows `List<DungeonLevel>
  levels` + `int activeLevel`**; the P1 top-level `rooms`/`corridors`/
  `currentRoomId` become views of the ACTIVE level (single point of change
  inside `MapState`/`MapNotifier`; the painter and existing call sites keep
  reading `state.rooms` etc.). JSON: `levels` array; a P1-shape JSON (bare
  `rooms`) loads as a single depth-1 dungeon level. Hex fields untouched.
- **This fixes P1's ephemeral-A2 gap:** the rolled dungeon/cave type, its
  effect, and the cavestone persist on the level, so restarts keep the effect
  (P1 kept it in pane state).
- **Descend/ascend:** a room with `levelDelta != 0` gets a persistent marker
  (stored in `DungeonRoom` as `levelDelta`); its detail card shows
  **Descend**/**Ascend**. Tap → if the target depth exists, switch
  `activeLevel`; else create the level (same branch as the room; its entrance
  room generates like any room per the P1 precedent — the zine's A3/D3
  entrance-hall shape tables stay unmodelled — plus cavestone for cave levels)
  and switch.
  Depth can go past 5 (tier just stays G4). A `{lvl:chasm}` D4 drop targets
  `depth + rolled` directly (intermediate depths are NOT materialized — only
  levels you land on exist).
- **Factions stay dungeon-wide** (one registry per campaign, unchanged).
- **Reset** clears all levels + factions (existing reset path, now clearing
  `levels`).
- **Level header + switcher:** classic pane header shows `Depth N · <typeName>`
  (+ stone for caves); when `levels.length > 1`, depth chips switch
  `activeLevel`.

## 4. UI

- **Enter buttons:** empty classic pane shows "Enter the dungeon" AND
  "Enter a cave" (`classic-enter` / `classic-enter-cave`). Cave entry rolls
  D1 + D2 + entrance hall + E5 stone.
- **Organic cave paint (pick A):** cave/tunnel rooms draw the fused-cell
  perimeter as a closed wobbly path — each perimeter edge subdivided with
  deterministic jitter seeded from the room id (stable across repaints; pure
  function, unit-testable) — filled with a cave tint distinct from dungeon
  rooms. Dungeon rooms render exactly as P1. Door glyphs stay at cell-edge
  midpoints, drawn over the blob.
- **Detail card:** gains Descend/Ascend button when the room carries
  `levelDelta`; crossover rooms note "openings lead to the <other branch>".

## 5. Error handling

- Unknown/malformed `{lvl}` token → ignored (row renders, no marker) — build
  self-check makes this unreachable for shipped data.
- Treasure-notation resolution failure → falls back to the raw row text.
- Level-switch to a missing index → clamped; descend on a depth that would
  exceed no limit (no cap).
- All P1 tolerances (empty tables, unknown refs, decode failures) unchanged.

## 6. Testing

- Build self-checks (§1). Unit: branch inheritance + crossover chain;
  depth→tier (+bump, cap); `rollTreasure` (notation, bonus, clamp, fallback);
  `{lvl}` parsing incl. chasm D4; `on_stock_6` expansion; level create/switch/
  reset in `MapNotifier`; P1-shape JSON loads as one level; organic-path
  generator (closed, deterministic per id, cell-count invariant). Widget:
  enter-cave flow, descend creates + switches to depth 2, switcher chips, base
  pane untouched, P1 dungeon flow regression. Device-verify per P1 recipe.

## 7. Out of scope (P3+)

- Interactive vein harvesting + trap triggering (expression parser).
- D2-12 Alien Hive "roll twice and combine" monster synthesis.
- Materializing intermediate chasm depths; per-level snapshot/export imagery.
- Key items for locked doors.
