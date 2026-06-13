# Verdant Journey — Design

**Date:** 2026-06-13
**Status:** Approved (brainstorm), pending implementation plan
**Source:** *Verdant Hexcrawling* © 2026 Vince Pinton / Ibir Publishing — CC BY-NC-SA 4.0 — https://verdant.ibir.cc

## Summary

Add a new **Verdant Journey** tool: a solo **journey tracker / play-aid** for Ibir
Publishing's *Verdant Hexcrawling* survival-hexcrawl procedure. The tool owns the
journey state (watch, day, Safety Level dial, Encounter Risk) and the dice (the
Random Encounter check, the d12 Points of Interest, an optional homebrew terrain
roll); the player owns task outcomes (tapping Safer/Riskier as they resolve tasks
in their own underlying system). Terrain and Points of Interest are plotted onto
the **existing shared hex Map**.

### Why a tracker, not an emulator
Juice has no PC character sheets or attributes. Verdant's Journey Tasks are
attribute checks (STR/DEX/WIS/INT/CHA/CON at Normal/Easy/Hard), so the tool
**cannot** auto-resolve them — there is nothing to roll against. The faithful,
in-pattern fit is a tracker that automates the bookkeeping the dial does on paper.

### Decisions (from brainstorm)
1. **Shape:** new dedicated tool (not folded into the Maps Hex tab).
2. **Job:** journey tracker / play-aid. Tool owns state + dice; user owns task outcomes.
3. **Hex/terrain:** plot onto the **existing** hex Map (additive `HexCell` fields).
4. **Terrain source:** pick from the 10 terrains by default **+ optional homebrew
   d10 roll** (clearly flagged non-Verdant); d12 Points of Interest always rolled.
5. **License:** Verdant is CC BY-NC-SA 4.0 — the same family as the Juice core
   (also CC BY-NC-SA) and Mythic (CC-BY-NC). Juice is and stays free/non-commercial,
   so NC/SA obligations are already the repo baseline. Attribution rendered in credits.

## Rules reference (verified from the PDFs)

- **Journey Round (6 steps):** 1. Round Starts (declare Watch) · 2. Travel (move to
  next hex if traveling) · 3. Task Assignment · 4. Task Execution (Safer on success,
  Riskier on failure; some tasks "special") · 5. Time Passes (if traveling, reveal
  adjacent hexes) · 6. Danger! (roll Random Encounter).
- **Watches:** day = 4 watches (~6h): 1 ☀ Morning · 2 ☀ Afternoon · 3 🌖 Evening ·
  4 🌖 Night. The two 🌖 watches (Evening, Night) are **Nighttime** → ☁ Reduced
  Visibility and make the journey **Deadly**. (The source marks both Evening and
  Night with 🌖; "Nighttime" = either moon watch, not Night alone.)
- **Safety Level:** starts each round at **0**. Safer = **+2**, Riskier = **−1**,
  Deadly = **−2**. A Nighttime watch (Evening or Night) sets the round's baseline to
  Deadly (−2). Task success usually +2, failure usually −1; other conditions may modify.
- **Encounter Risk:** `ER = 4 + (characters in party ÷ 2)`, rounded down.
- **Random Encounter (end of round):** roll d12, add Safety Level, compare to ER.
  **Encounter if `d12 + Safety < ER`, OR if the d12 was a natural 1.**
- **Travel:** 2 watches/day (Forced March +1 on a party-wide Normal CON check —
  reference text only). Adjacent hexes revealed at end of a travel.
- **Points of Interest:** d12 table; found when exploring. Permanent, may be hidden,
  no per-hex limit.
- **Terrain:** 10 types (Caatinga, Desert, Floodplain, Forest, Grassland, Hills,
  Marsh, Mountain, Swamp, Water), each with trait icons + a "special" note.
  **No random-terrain table exists** — terrain is authored, not rolled.
- **Traits (12):** Arduous Terrain, Bountiful, Broken Paths, Fast Trajectory,
  Foliage, Impassable Terrain, Nighttime, Raining, Reduced Visibility, Scarcity,
  Vantage Point, Waterways.
- **Terrain features (3):** Cliff (impassable; climb STR check), River (impassable +
  waterways; swim STR check, hard for rapids / easy for slow streams), Road (auto
  Navigate success + Fast Trajectory; maintained roads safer unless outlaws).
- **No resource tracks** (rations/fatigue/HP) exist in Verdant — those belong to the
  player's underlying ruleset and are out of scope.

## 1. Architecture & integration

- Add `'verdant'` to **`kAllSystems`** (`lib/engine/models.dart`) → per-campaign
  toggle, auto-listed in the new-campaign dialog checkboxes (like party/mythic/ironsworn).
- Register tool **`'verdant'` "Verdant Journey"** in `buildToolRegistry`
  (`lib/shared/tool_registry.dart`): group **Exploration**, icon
  `Icons.forest_outlined`, badge **`Verdant`**, `toolSystem['verdant']='verdant'`,
  `toolHelpPage['verdant']='verdant'`.
- Persistence: add **`'juice.verdant.v1'`** to `sessionScopedKeys`
  (`lib/state/providers.dart`) → session-scoped + auto-included in campaign export.
  **No `campaignSchemaVersion` bump** — additive key; old files simply lack it, and an
  old app ignores an unknown key. Stays schema v2.
- Verdant state holds journey bookkeeping only. **Hex map data stays in the existing
  `mapProvider`** (shared with the Maps tool).

## 2. Data asset — `build_verdant.py` → `assets/verdant_data.json`

Follows the `build_emulator.py` rail: hand-transcribed literals are the source of
truth in the Python script; the script self-verifies structure and cross-checks the
literals against `pdftotext -layout` extracts when present
(`/tmp/verdant_rules.txt`, etc.). **Never hand-edit the emitted JSON** — edit the
script and rerun `python3 build_verdant.py`, then copy output into `assets/`.

Tables emitted:
- `journey_tasks` (12): `{name, attribute, types:[T|S|C], success, failure, easier:[trait], harder:[trait], dependency}`.
- `terrain` (10): `{name, traits:[iconKey], special, flavor}`.
- `traits` (12): `{iconKey, name}`.
- `points_of_interest` (12): `{n:1..12, name, text}`.
- `terrain_features` (3): `{name, text}`.
- `constants`: `{erBase:4, erPerTwoChars, safer:2, riskier:-1, deadly:-2, watches:[{n,name,night:bool}], encounterRule}`.

Self-verify asserts: 12 tasks, 10 terrains, 12 traits, 12 POI (contiguous 1..12),
3 features; every task `attribute` ∈ the six stats; every task/terrain trait icon ∈
`traits`.

## 3. Engine — pure & testable (`lib/engine/verdant.dart`)

No Flutter imports. Pure functions + small result records:
- `int encounterRisk(int partySize)` → `4 + partySize ~/ 2`.
- `bool encounterCheck({required int d12, required int safety, required int er})`
  → `d12 == 1 || (d12 + safety) < er`.
- `({int d12, bool encounter}) rollEncounter(Dice dice, {int safety, int er})`.
- `({int n, String name, String text}) rollPoi(Dice dice, VerdantData data)` — d12.
- `({int n, String name}) rollTerrain(Dice dice, VerdantData data)` — d10, **homebrew**.
- `int baselineSafety({required bool night})` → `night ? deadly : 0`
  (night = watch ≥ 3, i.e. Evening or Night).
- `VerdantData` wrapper over `verdant_data.json` (table accessors), mirroring
  `OracleData`/`EmulatorData`.

Dice come from the shared `Dice` seam (same as the oracle), so tests inject a fake.

## 4. State — `lib/state/verdant.dart`

`VerdantJourney` (immutable, JSON):
`{partySize:int (default 1), day:int (1), watch:int (1..4), step:int (1..6),
safetyLevel:int, travelingThisRound:bool, roundNote:String}`
with `copyWith` + tolerant `fromJson`.

`VerdantNotifier extends AsyncNotifier<VerdantJourney>`, key
`juice.verdant.v1.<sessionId>`, mirroring `CrawlNotifier` (build/save/reset).
Operations: `setPartySize`, `setWatch`, `applyOutcome(safer|riskier|deadly)`,
`advanceStep`, `newRound` (resets Safety to `baselineSafety(night)`), `rollDanger`
(returns encounter result + appends a journal entry), `endDay`/`nextWatch`.

No rations/fatigue/HP — not in Verdant.

## 5. Map integration (additive; touches the just-fixed Maps tool)

`HexCell` (`lib/engine/models.dart`) gains **optional** fields:
- `final String? terrain;` (Verdant terrain key, e.g. `'forest'`)
- `final List<int> pois;` (POI numbers 1..12; default `const []`)

`copyWith`, `toJson` (omit `terrain` when null and `pois` when empty — keeps
Juice-only exports byte-clean), and `maybeFromJson` (tolerant parse) updated.
Juice `envRow` is preserved and unchanged.

`_HexPainter` (`lib/features/map_screen.dart`): a cell with `terrain != null`
renders by **Verdant terrain** (a fixed hue per terrain + the terrain name);
otherwise the existing Juice `envRow` rendering is untouched. POIs shown as a small
count badge/dot on the cell. **Render rule:** Verdant terrain takes precedence over
`envRow` for display; they never both show.

New `mapProvider` methods (beside existing `revealHex*`), additive:
- `setHexTerrain(int col, int row, String terrainKey)`
- `addHexPoi(int col, int row, int poiN)`

Verdant tool map actions write through these + the existing reveal/travel plumbing,
sharing `currentHexCol/Row`:
- **Travel** → move to next hex + reveal adjacent (reuse existing reveal).
- **Explore** → `rollPoi` → `addHexPoi` on current hex.
- **Set terrain** → picker (10 terrains) or homebrew d10 roll → `setHexTerrain`.

> Risk: this modifies `map_screen.dart`, recently fixed for the loose-constraint
> freeze. Edits are additive (new optional fields + a render branch); the existing
> `IndexedStack`/`Flexible` structure is preserved. Re-verify on device.

## 6. UI — `lib/features/verdant_screen.dart`

Single screen. **Must obey the loose-constraint contract** (see memory
`juice-toolhost-loose-constraints`): bounded widths via `Flexible`, no bare
Material buttons as non-flex `Row` children, no `TabBarView`; use `IndexedStack`
if any tabbing is needed. Verify on the Pixel, not just headless tests.

Layout, top → bottom (mirrors the paper journey-sheet dial):
- **Header strip:** `Day N` · Watch selector (Morning/Afternoon/Evening/Night;
  Night flagged 🌖 Deadly) · Party-size stepper → live **`ER: X`**.
- **Safety dial:** current Safety Level (large) + **Safer +2 / Riskier −1 /
  Deadly −2** buttons. Resets to baseline (0, or −2 at Night) on new round.
- **Round stepper:** the 6 Journey-Round steps; a primary button advances the step;
  step 6 is **Danger!** → rolls `d12 + Safety` vs ER → "Encounter!" / "Clear",
  appended to the journal.
- **Map controls:** Travel · Explore (roll d12 POI) · Set terrain — write to the
  shared map.
- **Reference (collapsible):** Journey Tasks table + Terrain/Traits + POI list,
  sourced from `verdant_data.json`.

## 7. Attribution & help

- `assets/help_data.json` credits page "Content" section gains:
  *"Verdant Hexcrawling © Vince Pinton / Ibir Publishing — CC BY-NC-SA 4.0 —
  verdant.ibir.cc. Derived table data in this app stays CC BY-NC-SA 4.0."*
- New `'verdant'` help page (in `help_data.json`): the Journey Round, Safety/ER math,
  Watches, and how the solo tracker maps to the tabletop procedure (you resolve tasks,
  the tool tracks the dial). `toolHelpPage['verdant']='verdant'`.

## 8. Testing & verification (success criteria)

- **Engine unit tests** (`test/verdant_engine_test.dart`): `encounterRisk` for several
  party sizes; `encounterCheck` truth table incl. natural-1 and night baseline;
  POI/terrain roll ranges and table mapping.
- **State test**: persistence round-trip; `newRound` resets Safety to baseline;
  night baseline = −2.
- **Widget tests** (`test/verdant_screen_test.dart`, mounted under `Scaffold`):
  party-size → ER updates; Safer/Riskier move the dial; Danger! logs to journal;
  Explore plots a POI; Set terrain renders on the map.
- **Map test**: `HexCell` terrain/pois JSON round-trip; painter renders Verdant
  terrain over envRow.
- **`build_verdant.py`** self-verify passes.
- **`flutter analyze`** clean; **full `flutter test`** green.
- **On-device Pixel check**: open Verdant Journey + the Maps Hex tab with Verdant
  terrain/POI present; no layout exception / freeze (loose-constraint class — headless
  cannot catch a host freeze).

## 9. Out of scope (YAGNI)

No character sheets/attributes; no auto-resolved task checks; no multi-PC modeling;
no rations/fatigue/HP tracks; no card-draw animations; no new hex *grid* (reuses the
Maps tool). Forced March / crossing checks are reference text, not modeled.
