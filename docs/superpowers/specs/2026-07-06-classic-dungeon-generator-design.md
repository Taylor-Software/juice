# Classic Dungeon Generator (Roll 4 Ruin) — Design

**Date:** 2026-07-06
**Status:** Approved (brainstorm) → writing plan
**System id:** `classic-dungeon` (opt-in, `SystemCategory.exploration`, NOT in `kAllSystems`)

## Summary

Vendor **Roll 4 Ruin: Classic Dungeon Generator v2.1** (Nocturnal Peacock) as a
new opt-in campaign system that turns the existing **Map → Dungeon** pane into a
room-by-room *classic* dungeon crawler: shape-accurate multi-cell rooms placed by
directed door-to-door exploration, depth-scaled monster/treasure economy, and
tracked monster factions.

This is **P1 = the dungeon branch only** (source pages A–C + monsters G +
build-elements H). The cave branch (D–F), multi-level descent, and interactive
trap triggering are **deferred to P2** (separate spec).

### Licensing

Roll 4 Ruin is **CC BY-NC-SA 4.0** (confirmed on the itch.io page; the creator
explicitly invited online-tool adaptations *"If you Credit the Project/me feel
free to make an online Tool!"*). This is the same license family as the already
vendored Ironsworn/Starforged Datasworn content. The app is free and
non-commercial, satisfying the **NC** clause; **ShareAlike** is honored by
attribution and the app's overall free/open posture. Add an attribution line to
`kContentAttributions['classic-dungeon']` and the Settings → Sources & licenses
dialog:

> Roll 4 Ruin: Classic Dungeon Generator © Nocturnal Peacock, licensed under
> CC-BY-NC-SA-4.0.

Nothing traces the zine's pixel art. Table **text** is vendored (permitted);
room **geometry** is authored grid-fact data inspired by the zine's shape
catalog (the same facts-only posture used for the hexcrawl toolkit's geometry).

## Decisions locked in brainstorm

1. **Integration style:** living dungeon grid map (rooms render + persist on the
   Map → Dungeon pane as you explore) — not a roll-and-log generator sheet.
2. **Licensing:** vendor the actual tables under CC-BY-NC-SA-4.0 with attribution
   (not authored-inspired), following the `build_datasworn.py` precedent.
3. **Shape fidelity:** shape-accurate rooms — real multi-cell footprints with
   door sides, rendered as polygons, auto-rotated to mate the explored door,
   placed only where they fit.
4. **Shape-library richness:** a representative **catalog** (~15–20 corridor +
   ~15–20 chamber footprints) with the D66 roll mapped onto shape families — NOT
   132 hand-transcribed footprints.
5. **Scope split:** P1 dungeon branch; P2 caves + multi-level + interactive traps.
6. **Factions:** real tracked per-campaign faction state (registry + 5/6
   same-faction roll + auto-naming), not inline flavor text.
7. **Traps/secret rooms:** rendered as descriptive room detail text in P1; no
   interactive trigger/disarm mechanic (that needs the deferred expression parser).

## Architecture

Four layers, mirroring existing feature rails:

```
build_dungeon.py  ──►  assets/dungeon_data.json     (data rail; script = source of truth)
        │
lib/engine/dungeon/  (pure Dart, no Flutter)
   ├─ tables.dart      typed loaders for dungeon_data.json
   ├─ footprint.dart   RoomFootprint / DoorEdge / rotate + authored shape catalog
   ├─ placement.dart   placeRoom(): rotate+fit a footprint against occupied cells
   ├─ faction.dart     DungeonFaction registry + 5/6 same-faction roll + naming
   └─ generator.dart   generateRoom(): 4D6 resolution, ref-token expansion, A2 effect
        │
lib/engine/models.dart   DungeonRoom grows (footprint/doors/roomType); new DungeonFaction*
lib/state/providers.dart MapNotifier.addClassicRoom(); dungeonFactionsProvider
        │
lib/features/map_screen.dart  footprint-aware painter + door-tap exploration (gated)
lib/features/maps_tab.dart    Dungeon pane switches generator on `classic-dungeon`
```

### Data flow (one room)

1. User taps an **open door** on an existing room (or "Enter" for the first room).
2. `MapNotifier.addClassicRoom(fromRoomId, doorEdge, dice)`:
   a. `generator.generateRoom(ctx, dice)` → `RoomResult` (type, shape-family,
      stocking, monster+faction, reaction, treasure, `detail` text).
   b. `placement.placeRoom(occupiedCells, doorEdge, familyCandidates, dice)` →
      absolute cells + world door edges, or `null`.
   c. If placed: append a `DungeonRoom` (with footprint/doors), add corridor
      `[fromRoomId, newId]`, set `currentRoomId`, persist `MapState`.
   d. If the stocking produced an organized monster: resolve/extend the faction
      registry, persist `dungeonFactionsProvider`.
3. Painter re-renders: the new polygon appears with its unexplored door markers.

## Components

### `build_dungeon.py` → `assets/dungeon_data.json`

Source of truth. Hand-transcribed literals from the zine, self-verifying, emitted
to JSON and copied into `assets/` (never hand-edit the JSON). Transcribes the
**dungeon branch + shared tables**:

| Table | Roll | Contents |
|-------|------|----------|
| A1 | D12 | entrance surroundings (flavor strings) |
| A2 | 2D6 | dungeon type (name + **effect modifier**, see below) |
| B2 | D6  | corridor stocking (monster/feature/trap/change-door/nothing) |
| B3 | D20 | corridor feature (many cross-ref H/I/E — I/E are P2, see note) |
| B4 | D8×D12 | trap trigger × effect → display text |
| B5 | D10 | door types |
| C2 | D6  | chamber stocking |
| C3 | D20 | chamber feature |
| C4 | D20 | chamber special (incl. bossroom, secret room) |
| C5 | D6  | re-stocking (revisit) |
| G1 | 2D6 | reaction table |
| G2/G3/G4 | D12/D20 | monsters: upper / central / deep levels |
| G5/G6 | D12/D20 | miniboss / boss rooms |
| G7 | D20 | fauna |
| H1–H8 | various | build-elements: coffins, statues, secret room, containers, chests, shrine, frescos, treasure |

**Cross-references** in the source (e.g. C2 "Feature `C3` + Monster", B3 "Chest
`H5`", H5 "Trapped `B4`") are encoded as typed tokens `{"ref": "H5"}` inside the
row text so the generator's resolver can expand them recursively (with a depth
cap). Rows referencing **P2-only** tables (I = natural elements, E = cave
obstacles, D–F cave rooms) keep the ref token but the resolver renders a plain
label fallback in P1 (e.g. "flora" instead of expanding I6), noted with a
`log()`-style comment in the script so P2 can wire them.

**A2 effect modifiers** are structured where the effect is mechanical:
`{"tier_bump": 1}` (monster stocking begins at G3), `{"treasure_bonus": 3}`,
`{"stock_double": true}` (vault), `{"leads_to_caves": true}` (P2 no-op in P1) —
else a display-only `note`. P1's generator applies `stock_double` only;
`tier_bump`/`treasure_bonus` await the P2 treasure/level features and
`leads_to_caves` awaits the P2 cave branch (all parsed into `A2Type` now, so
P2 needs no data change). Unmechanizable notes show as dungeon-header flavor.

**Self-checks** (structural — geometry lives in Dart, so no pdftotext geometry
check; text tables *can* be cross-checked against a pdftotext extract when
present, like the verdant/lonelog rails):
- every table has the exact expected row count for its die,
- weighted/2D6 tables cover their full range with no gaps/overlaps,
- every `{"ref": X}` token targets a table that exists (in P1-or-P2 set),
- the D66→shape-family map (authored in Dart, but its **family keys** are
  declared in the JSON) covers 11–66 with no gaps.

### `lib/engine/dungeon/footprint.dart`

```
enum DoorKind { locked, door, open }   // 'open' = an unexplored opening (no door)
enum Side { n, e, s, w }
class Opening { final (int,int) cell; final Side side; }   // authored: WHERE a room connects
class DoorEdge { final (int,int) cell; final Side side; final DoorKind kind; } // runtime: an opening + its assigned kind
class RoomFootprint {
  final String family;            // 'straight', 'l-bend', 't-junction', 'cross', 'small-chamber', 'round', ...
  final List<(int,int)> cells;    // offsets from anchor (0,0)
  final List<Opening> openings;   // authored openings — sides that CAN connect (kind unset)
  RoomFootprint rotate(int quarterTurns);   // 0..3; 4-fold involution
  ({int minX,int minY,int maxX,int maxY}) get bounds;
}
```

Authored catalogs `kCorridorShapes` / `kChamberShapes` carry only **openings**
(which sides connect) — never door *kinds*. `rotate` maps `(x,y)→(-y,x)` per
quarter-turn and rotates each opening `Side` accordingly. A pure
`shapeFamilyForRoll(int d66, RoomType)` maps the roll onto a family (range map
declared in JSON, resolved to a candidate list of footprints in that family).

**Door kind comes from the type die, not the footprint.** In the zine the first
D6 (room type) simultaneously picks corridor-vs-chamber *and* the kind of the
door you entered through: 1=corridor+locked, 2=corridor+door, 3=corridor+no-door,
4=chamber+no-door, 5=chamber+door, 6=chamber+locked. So when the generator makes
a room, the type die sets `RoomType` **and** the `DoorKind` of the single edge
mating it to the room it was explored from. All the room's *other* openings stay
`open` (unexplored) until the player explores them (each becomes a fresh
generation whose type die sets that edge's kind). The stored `DungeonRoom.doors`
is thus built at placement time: one `DoorEdge` (the mated entry, kind from the
type die) + the remaining openings as `DoorKind.open`. The entrance room (0,0)
has no entry edge — all openings start `open`.

### `lib/engine/dungeon/placement.dart`

```
class Placement { final List<(int,int)> cells; final List<DoorEdge> worldDoors; }
Placement? placeRoom(
  Set<(int,int)> occupied,
  ({(int,int) cell, Side side}) fromDoor,   // the explored door's world edge
  List<RoomFootprint> candidates,
  Dice dice,
);
```

Tries candidates (dice-shuffled) × 4 rotations; for each, finds an **opening** on
the candidate whose side is opposite `fromDoor.side`, translates the footprint so
that opening mates the explored edge, accepts the first placement whose cells
don't intersect `occupied`. The mated opening becomes the room's entry `DoorEdge`
(its kind supplied by the caller from the type die); remaining openings become
`DoorKind.open`. Returns `null` if nothing fits (caller shows a "no room fits —
try another door" snackbar; deterministic under seeded dice).

### `lib/engine/dungeon/faction.dart`

```
class DungeonFaction { final String id, name, monsterType; final List<String> roomIds; }
class FactionRegistry { final List<DungeonFaction> factions; ... }
({FactionRegistry next, DungeonFaction? faction}) assignFaction(
  FactionRegistry reg, String monsterType, String roomId, Dice dice,
);
```

If a faction for `monsterType` exists → **5/6** (seeded `dice`) chance to reuse
it (append `roomId`), else mint a new faction named from an authored
`kFactionNames` word list (facts-only, ours; e.g. "Rotfangs", "Ashclaw Pack").
Pure; the notifier persists the returned registry.

### `lib/engine/dungeon/generator.dart`

```
class DungeonGenContext {
  final int level;                 // P1: always 1
  final A2Effect dungeonEffect;    // from A2, applied campaign-wide
  final RoomType wanted;           // corridor|chamber, or null = roll B/C type die
  final FactionRegistry factions;
}
class RoomResult {
  final RoomType type;             // from the type die (also fixes entryDoorKind)
  final DoorKind entryDoorKind;    // kind of the edge back to the room explored from
  final String shapeFamily;
  final List<StockingItem> stocking;   // features, monster(+faction+reaction), treasure, trap
  final String detail;             // rendered multi-line text for DungeonRoom.detail
  final FactionRegistry factions;  // possibly extended
}
RoomResult generateRoom(DungeonGenContext ctx, Dice dice);
```

Resolves the sequential **4D6** (D6 type → corridor/chamber **and** entry door
kind; 2D6 shape → D66 family; D6 content → stocking) plus additional rolls,
expanding `{ref}` tokens
(depth-capped at e.g. 4 to stop cycles), applies `A2Effect` (tier bump selects
G2/G3/G4; treasure bonus; stock double), rolls G1 reaction per monster and H8
treasure, and calls `assignFaction` for organized monsters. Depth tier in P1 is
level-1 → G2 unless the effect bumps it.

### Model + state changes

- **`DungeonRoom`** gains optional `footprint` (list of cell offsets, default =
  the single cell `[(0,0)]`), `doors` (list of `DoorEdge`), and `roomType`
  (`corridor`/`chamber`/`null`). JSON round-trips tolerantly; a legacy/base-pane
  room with no footprint renders exactly as today (one square). Pre-release, no
  migration needed.
- **`MapState.rooms`** reused as-is. `nextRoomPosition` (single-cell) stays for
  the base pane; classic placement is a separate path.
- **`MapNotifier.addClassicRoom(fromRoomId, doorEdge, dice)`** — new method doing
  generate → place → append room + corridor → faction persist. Base `addRoom`
  untouched.
- **`dungeonFactionsProvider`** — `AsyncNotifier<FactionRegistry>`, session-scoped
  key `juice.dungeon_factions.v1.<sessionId>`, added to `sessionScopedKeys` so it
  exports with the campaign. Cleared on dungeon reset.

### UI — `map_screen.dart` + `maps_tab.dart`

- `maps_tab.dart`: unchanged tab structure; the Dungeon pane reads
  `systems.contains('classic-dungeon')` and switches the generator/interaction.
- Painter: generalize `roomRectFor`/`roomIdAt` to iterate a room's `footprint`
  cells (single-cell footprint → identical to today). Draw the polygon as the
  union of cell rects (rounded outline), then **door markers** on each `DoorEdge`
  (open = arrow, door = short bar, locked = keyhole/lock glyph) using the zine's
  visual grammar in our own iconography.
- Interaction (classic mode only): tapping an **open** door on a room runs
  `addClassicRoom` mated to that edge; locked/no-door edges are inert (locked
  shows a lock, a future P2 could gate on a key). The first room is created by an
  "Enter the dungeon" action that rolls A1/A2 (stored as dungeon context/header)
  and places an entrance chamber at (0,0). Blind "Roll Next Room" is hidden in
  classic mode.
- Everything else on the pane (pan/zoom, tap-room detail card, linger, encounter
  link, snapshot-to-journal, journal logging) is reused unchanged.

## Error handling

- `placeRoom` returns `null` when no candidate fits → snackbar "No room fits that
  way — try another exit", no state change.
- `generateRoom` ref-expansion is depth-capped; a missing/unknown ref renders the
  raw label (never throws).
- Asset load failures surface via the existing data-provider error path (the
  pane already tolerates an unloaded oracle).
- Faction registry decode is tolerant (`fromJson` returns empty on malformed).

## Testing

- **`build_dungeon.py`**: the self-checks above run on every build; CI-style
  `python3 build_dungeon.py` must exit 0.
- **Dart unit** (`test/dungeon/`):
  - `footprint`: 4-fold rotation is an involution; door sides rotate correctly;
    bounds correct.
  - `placement`: mated door aligns; no cell overlap; deterministic pick under a
    seeded `Dice`; `null` when boxed in.
  - `faction`: 5/6 reuse vs new-faction split under seeded dice; naming is
    stable/unique; `roomIds` accumulate.
  - `generator`: ref-token expansion + depth cap (no infinite recursion on a
    self-referential ref); A2 tier-bump selects the right G-table; reaction +
    treasure resolve; organized monster triggers faction assignment.
  - `tables`: loader parses the shipped `dungeon_data.json`; row counts match.
- **Widget** (`test/`): classic Dungeon pane renders a multi-cell footprint,
  door-tap generates + places a mated room, single-cell/base pane unchanged when
  system off. Follow the rootBundle-hang recipe (override oracle/verdant/
  emulator/ruleset + dungeon-data providers with fixtures; `SharedPreferences.
  setMockInitialValues`).

## System registration checklist

`classic-dungeon` added to: `kKnownSystems`, `kSystemCategory`
(`exploration`), `kSystemLabels` ('Classic Dungeon'), `kSystemBlurbs` (with the
non-affiliation + attribution line), `kSystemShortName`/`kPresetIcons` if
present, `surfacesFor` (adds the Dungeon-crawl surface), the creation wizard's
addon chips (`cat-exploration`), and `kContentAttributions`.

## Internal build phases (for the plan)

1. **1a** data rail: `build_dungeon.py` + `dungeon_data.json` + `tables.dart` loader.
2. **1b** geometry: `footprint.dart` (+ authored catalog) + `placement.dart` + tests.
3. **1c** engine: `generator.dart` + `faction.dart` + tests.
4. **1d** model/state: `DungeonRoom` growth, `MapNotifier.addClassicRoom`,
   `dungeonFactionsProvider`, `sessionScopedKeys`.
5. **1e** UI: footprint-aware painter + door-tap exploration + Enter action.
6. **1f** registration + attribution + widget tests + docs/CLAUDE.md.

## Explicitly out of scope (P2, separate spec)

- Cave branch D–F + natural elements I (tunnels/caves/veins/flora/liquid/gas).
- Multi-level descent (stairs → new persisted level instance). P1 stairs = flavor.
- Interactive trap triggering / disarm (needs the deferred expression parser).
- Key items unlocking locked doors.
- 132-shape full-fidelity footprint transcription (P1 uses the family catalog).
