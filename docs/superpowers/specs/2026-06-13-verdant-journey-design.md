# Verdant Journey — Design

**Date:** 2026-06-13
**Status:** Approved (brainstorm), pending implementation plan
**Source:** *Verdant Hexcrawling* © 2026 Vince Pinton / Ibir Publishing — CC BY-NC-SA 4.0 — https://verdant.ibir.cc
Sourced from the supplied PDFs (Rules Brochure, Journey Sheet, Printable Card Sheets)
**and** the live website (v1.2 "Mate"), which carries content absent from the brochure:
the d10 Quick Encounters table, the Travel Pace / Independent Followers optional rules,
Modes of Transportation, and a corrected Random-Encounter rule (natural-12, not -1).

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
6. **Website-only additions (all approved):** (a) **natural-12 encounter rule**
   correction — applied to the core engine; (b) bundle the **d10 Quick Encounters**
   table and auto-roll it when an encounter triggers; (c) **Travel Pace** optional
   rule (Normal/Slow/Fast) as a pace selector feeding the Safety baseline; (d)
   **Independent Followers** optional rule (followers tracked but excluded from ER);
   (e) **Modes of Transportation** (Mounts/Boats/Airships) as a transport selector +
   reference. *Maintain Results* is explicitly out (pure GM convenience).

## Rules reference (verified from the PDFs + live website v1.2)

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
  **Dangerous encounter if `d12 + Safety < ER`.** A **natural 12** = an encounter
  with *no immediate danger* (a benign event). *(Live website v1.2 rule — supersedes
  the brochure's stale "natural 1 = encounter". The brochure PDF is out of date here.)*
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

Website-only content (v1.2; transcribed from verdant.ibir.cc, no PDF source):
- **d10 Quick Encounters** (a sample encounter table; the brochure has only the
  trigger): 1 Dark Clouds · 2 Hungry Vermin · 3 Mosquito Fever · 4 Shooting Star ·
  5 Landslide · 6 Hole in Backpack · 7 Quicksand · 8 Bad Omen · 9 Psychic Crickets ·
  10 A Coin on the Ground. Each has a short effect line. Mildly system-flavored
  (CON damage, gp, advantage) but usable as solo prompts.
- **Optional Rule — Travel Pace:** the party picks **Normal / Slow / Fast**. *Slow* =
  Safer (+2) but +1 watch to travel (compounds with Arduous Terrain). *Fast* = Deadly
  (−2) but allows an extra round in the same watch (compounds with Fast Trajectory).
- **Optional Rule — Independent Followers:** NPC followers don't help with tasks and
  **don't count toward party size / ER** unless they directly contribute to a task.
- **Modes of Transportation** (whole party must use it): *Mounts* — once/day **Rush**
  for an extra round in the same watch (not from a Broken-Paths terrain); *Boats* —
  travel through Waterways, and boats not party-powered aren't capped at 2 watches/day;
  *Airships* — travel over Impassable Terrain and ignore Arduous Terrain.

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
PDF-sourced literals against `pdftotext -layout` extracts when present
(`/tmp/verdant_rules.txt`, etc.). The website-only tables (Quick Encounters) and
optional-rule constants have no PDF — they are transcribed from verdant.ibir.cc and
verified structurally only; a code comment records the source URL + retrieval note.
**Never hand-edit the emitted JSON** — edit the script and rerun
`python3 build_verdant.py`, then copy output into `assets/`.

Tables emitted:
- `journey_tasks` (12): `{name, attribute, types:[T|S|C], success, failure, easier:[trait], harder:[trait], dependency}`.
- `terrain` (10): `{name, traits:[iconKey], special, flavor}`.
- `traits` (12): `{iconKey, name}`.
- `points_of_interest` (12): `{n:1..12, name, text}`.
- `quick_encounters` (10, website): `{n:1..10, name, text}` — the sample d10 table.
- `terrain_features` (3): `{name, text}`.
- `transport_modes` (3, website): `{key, name, text}` — Mounts / Boats / Airships.
- `constants`: `{erBase:4, erPerTwoChars, safer:2, riskier:-1, deadly:-2,
  watches:[{n,name,night:bool}], encounterRule, pace:{slow:2, fast:-2}}`.

Self-verify asserts: 12 tasks, 10 terrains, 12 traits, 12 POI (contiguous 1..12),
10 quick encounters (contiguous 1..10), 3 features, 3 transport modes; every task
`attribute` ∈ the six stats; every task/terrain trait icon ∈ `traits`.

## 3. Engine — pure & testable (`lib/engine/verdant.dart`)

No Flutter imports. Pure functions + small result records:
- `int encounterRisk(int partySize)` → `4 + partySize ~/ 2`.
- Encounter resolution returns one of three outcomes via an enum
  `EncounterOutcome { none, danger, benign }`:
  `EncounterOutcome resolveEncounter({required int d12, required int safety, required int er})`
  → `d12 == 12 ? benign : ((d12 + safety) < er ? danger : none)`.
  **(Natural-12 = benign event; low total = dangerous. No natural-1 rule.)**
- `({int d12, EncounterOutcome outcome}) rollEncounter(Dice dice, {int safety, int er})`.
- `({int n, String name, String text}) rollPoi(Dice dice, VerdantData data)` — d12.
- `({int n, String name, String text}) rollQuickEncounter(Dice dice, VerdantData data)` — d10 (website table).
- `({int n, String name}) rollTerrain(Dice dice, VerdantData data)` — d10, **homebrew**.
- `enum Pace { normal, slow, fast }` with `int paceMod(Pace p)` → slow `+2`, fast `-2`, normal `0`.
- `int baselineSafety({required bool night, Pace pace = Pace.normal})`
  → `(night ? deadly : 0) + paceMod(pace)` (night = watch ≥ 3, i.e. Evening or Night).
  Standing conditions stack; task outcomes are added on top during the round.
- `int erForParty(int partySize)` — ER ignores Independent Followers, so callers pass
  only the contributing party count (followers are a separate, excluded counter).
- `VerdantData` wrapper over `verdant_data.json` (table accessors), mirroring
  `OracleData`/`EmulatorData`.

Dice come from the shared `Dice` seam (same as the oracle), so tests inject a fake.

## 4. State — `lib/state/verdant.dart`

`VerdantJourney` (immutable, JSON):
`{partySize:int (default 1), independentFollowers:int (default 0), day:int (1),
watch:int (1..4), step:int (1..6), safetyLevel:int, pace:Pace (default normal),
transport:String? (null|mount|boat|airship), rushUsedToday:bool,
travelingThisRound:bool, roundNote:String}`
with `copyWith` + tolerant `fromJson` (unknown enums clamp to defaults).
All new fields are additive and default-valued, so old persisted state and
imported campaigns deserialize cleanly.

`VerdantNotifier extends AsyncNotifier<VerdantJourney>`, key
`juice.verdant.v1.<sessionId>`, mirroring `CrawlNotifier` (build/save/reset).
Operations: `setPartySize`, `setFollowers`, `setWatch`, `setPace`, `setTransport`,
`applyOutcome(safer|riskier|deadly)`, `advanceStep`,
`newRound` (resets Safety to `baselineSafety(night, pace)`), `rollDanger` (rolls the
encounter; on `danger`/`benign` also rolls a Quick Encounter; appends a journal entry
noting outcome + watch + ER), `rush` (mounts only, once/day → flags `rushUsedToday`,
adds a round), `nextWatch`/`endDay` (rolls `rushUsedToday` over at day end). ER is
computed from `partySize` only (followers excluded).

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
  Nighttime watches flagged 🌖 Deadly) · Party-size stepper → live **`ER: X`** ·
  Independent-Followers stepper (default 0; excluded from ER, with a hint why).
- **Pace + transport row:** Pace segmented control (Normal / Slow / Fast, showing
  its Safety effect) · Transport dropdown (None / Mount / Boat / Airship; selecting
  Mount reveals a **Rush** button, disabled once used until day end).
- **Safety dial:** current Safety Level (large) + **Safer +2 / Riskier −1 /
  Deadly −2** buttons. Resets to baseline (`night ± pace`) on new round; the baseline
  breakdown is shown (e.g. "−2 night +2 slow = 0").
- **Round stepper:** the 6 Journey-Round steps; a primary button advances the step;
  step 6 is **Danger!** → rolls `d12 + Safety` vs ER. On *danger* or *benign* it also
  rolls the **d10 Quick Encounter** and shows its result ("Danger — Quicksand" /
  "Benign — A Coin on the Ground" / "Clear"); the line is appended to the journal.
- **Map controls:** Travel · Explore (roll d12 POI) · Set terrain — write to the
  shared map.
- **Reference (collapsible):** Journey Tasks table + Terrain/Traits + POI list +
  Quick Encounters + Transport notes, sourced from `verdant_data.json`.

## 7. Attribution & help

- `assets/help_data.json` credits page "Content" section gains:
  *"Verdant Hexcrawling © Vince Pinton / Ibir Publishing — CC BY-NC-SA 4.0 —
  verdant.ibir.cc. Derived table data in this app stays CC BY-NC-SA 4.0."*
- New `'verdant'` help page (in `help_data.json`): the Journey Round, Safety/ER math,
  Watches, the optional rules in use (Travel Pace, Independent Followers), Modes of
  Transportation, the bundled d10 Quick Encounters, and how the solo tracker maps to
  the tabletop procedure (you resolve tasks, the tool tracks the dial).
  `toolHelpPage['verdant']='verdant'`.

## 8. Testing & verification (success criteria)

- **Engine unit tests** (`test/verdant_engine_test.dart`): `encounterRisk` for several
  party sizes; `resolveEncounter` truth table — natural-12 → `benign`, low total →
  `danger`, else `none`, and **no** natural-1 special case; `baselineSafety` for the
  night × pace matrix (e.g. night+slow = 0, night+fast = −4, day+fast = −2);
  POI / terrain / quick-encounter roll ranges and table mapping.
- **State test**: persistence round-trip incl. new fields; `newRound` resets Safety to
  `night ± pace` baseline; ER excludes `independentFollowers`; `rush` is once/day and
  resets at day end; tolerant `fromJson` for an unknown pace/transport value.
- **Widget tests** (`test/verdant_screen_test.dart`, mounted under `Scaffold`):
  party-size → ER updates and followers do **not** change ER; pace toggle shifts the
  baseline; Danger! logs outcome + (on danger/benign) a Quick Encounter to the journal;
  Explore plots a POI; Set terrain renders on the map; Mount enables Rush once.
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
Maps tool). Forced March / crossing checks are reference text, not modeled. The
*Maintain Results* optional rule is **out** (pure GM convenience, no tracker value).
Transport effects on travel distance/watch caps are reference text; only the Mount
**Rush** (extra round) is a tracked action. 5e/5.5e & Shadowdark system-specific
versions are not used (Juice has no character sheets).
