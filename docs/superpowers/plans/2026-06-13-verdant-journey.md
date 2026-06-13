# Verdant Journey Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new solo "Verdant Journey" tool — a journey tracker / play-aid for *Verdant Hexcrawling* (Ibir Publishing, CC BY-NC-SA 4.0) — that owns the Safety-Level/Encounter-Risk/Watch state and the dice, while the player resolves tasks; terrain + Points of Interest plot onto the existing shared hex Map.

**Architecture:** Mirrors existing Juice tool seams. Static data: `build_verdant.py` → `assets/verdant_data.json`, loaded via a `FutureProvider<VerdantData>`. Pure engine in `lib/engine/verdant.dart`. Session-scoped state in `lib/state/verdant.dart` (`VerdantNotifier`, key `juice.verdant.v1`). UI in `lib/features/verdant_screen.dart`, registered as the `'verdant'` tool/system. Map integration is additive optional fields on `HexCell`.

**Tech Stack:** Python 3 (data build), Dart/Flutter, flutter_riverpod (AsyncNotifier/FutureProvider), shared_preferences, `package:flutter_test`.

**Design source:** [docs/superpowers/specs/2026-06-13-verdant-journey-design.md](../specs/2026-06-13-verdant-journey-design.md). Read it before starting.

**Conventions (from CLAUDE.md):** Generated JSON is never hand-edited — edit `build_verdant.py` and rerun. Tests never construct `GemmaInterpreterService`. The tool host gives tools LOOSE constraints — UI must use `Flexible`/bounded sizes, no bare Material buttons as non-flex `Row` children, no `TabBarView` (see memory `juice-toolhost-loose-constraints`). A `dart format` hook runs on every `.dart` edit. Commit after each task; branch is `feat/verdant-journey`.

**Trait key vocabulary (used throughout):** `arduous, bountiful, broken_paths, fast_trajectory, foliage, impassable, nighttime, raining, reduced_visibility, scarcity, vantage_point, waterways`.

---

## Phase 1 — Data asset

### Task 1: `build_verdant.py` — the data source of truth

**Files:**
- Create: `build_verdant.py`
- Create (generated): `assets/verdant_data.json`

- [ ] **Step 1: Regenerate the cross-check extract**

The script cross-checks PDF-sourced literals against a `pdftotext` extract. Generate it from the user's brochure PDF (best-effort; the script tolerates its absence):

Run:
```bash
pdftotext -layout "/Users/johntaylor/Downloads/Verdant - Rules Brochure.pdf" /tmp/verdant_rules.txt
```
Expected: creates `/tmp/verdant_rules.txt` (~10 KB).

- [ ] **Step 2: Write `build_verdant.py`**

Create `build_verdant.py` with the complete content below. Literals are the source of truth. PDF-sourced tables (journey_tasks, terrain, traits, points_of_interest, terrain_features) come from the brochure + task/terrain cards; website-only tables (quick_encounters, transport_modes) and the natural-12 encounter rule come from verdant.ibir.cc v1.2 (no PDF — verified structurally only).

```python
#!/usr/bin/env python3
"""Verdant Hexcrawling — source of truth for the Verdant Journey tool data.

Like build_emulator.py: hand-transcribed literals here are authoritative; this
script (a) self-verifies table structure, (b) cross-checks PDF-sourced literals
against a pdftotext extract when present, and (c) emits assets/verdant_data.json.
NEVER hand-edit the emitted JSON — edit this script and rerun.

Sources:
  PDF (supplied): Verdant - Rules Brochure.pdf, Journey Sheet, Printable Card Sheets.
  Website v1.2 "Mate" (no PDF): https://verdant.ibir.cc — quick_encounters,
    transport_modes, and the corrected natural-12 random-encounter rule.
Verdant (c) 2026 Vince Pinton / Ibir Publishing, CC BY-NC-SA 4.0.
"""
import json
import os

OUT = "verdant_data.json"
RULES_EXTRACT = "/tmp/verdant_rules.txt"

# Twelve trait icon keys -> display names (brochure legend).
TRAITS = {
    "arduous": "Arduous Terrain",
    "bountiful": "Bountiful",
    "broken_paths": "Broken Paths",
    "fast_trajectory": "Fast Trajectory",
    "foliage": "Foliage",
    "impassable": "Impassable Terrain",
    "nighttime": "Nighttime",
    "raining": "Raining",
    "reduced_visibility": "Reduced Visibility",
    "scarcity": "Scarcity",
    "vantage_point": "Vantage Point",
    "waterways": "Waterways",
}

# Journey Tasks (brochure table + task cards + website Journey Tasks page).
# types: T=Traveling, S=Stationary, C=Concurrent. easier/harder are trait keys.
JOURNEY_TASKS = [
    {"name": "Bushwhack", "attribute": "STR", "types": ["T"],
     "success": "Safer", "failure": "Riskier",
     "easier": [], "harder": [], "dependency": "foliage"},
    {"name": "Camouflage", "attribute": "DEX", "types": ["S"],
     "success": "Safer", "failure": "Riskier",
     "easier": ["foliage", "reduced_visibility"], "harder": [], "dependency": None},
    {"name": "Entertain", "attribute": "CHA", "types": ["T", "S", "C"],
     "success": "Special", "failure": "Riskier",
     "easier": [], "harder": [], "dependency": None},
    {"name": "Explore", "attribute": "WIS", "types": ["T", "S", "C"],
     "success": "Special", "failure": "Riskier",
     "easier": ["vantage_point"], "harder": ["broken_paths", "reduced_visibility"],
     "dependency": None},
    {"name": "Forage", "attribute": "INT", "types": ["T", "S", "C"],
     "success": "Special", "failure": "Riskier",
     "easier": ["bountiful", "foliage"], "harder": ["scarcity"], "dependency": None},
    {"name": "Keep Watch", "attribute": "WIS", "types": ["T", "S"],
     "success": "Safer", "failure": "Riskier",
     "easier": ["vantage_point"], "harder": ["foliage", "reduced_visibility"],
     "dependency": None},
    {"name": "Navigate", "attribute": "INT", "types": ["T"],
     "success": "Safer", "failure": "Riskier",
     "easier": ["vantage_point"], "harder": ["broken_paths", "reduced_visibility"],
     "dependency": None},
    {"name": "Scout Ahead", "attribute": "DEX", "types": ["T"],
     "success": "Safer", "failure": "Riskier",
     "easier": ["foliage"], "harder": ["broken_paths"], "dependency": None},
    {"name": "Set Camp", "attribute": "INT", "types": ["S"],
     "success": "Safer", "failure": "Riskier",
     "easier": [], "harder": ["raining"], "dependency": "firewood"},
    {"name": "Sleep", "attribute": "CON", "types": ["S", "C"],
     "success": "Rest", "failure": "No Rest",
     "easier": [], "harder": [], "dependency": None},
    {"name": "Something Else", "attribute": None, "types": ["T", "S", "C"],
     "success": "???", "failure": "???",
     "easier": [], "harder": [], "dependency": None},
    {"name": "Use Spyglass", "attribute": "WIS", "types": ["S"],
     "success": "Safer", "failure": "Riskier",
     "easier": [], "harder": ["reduced_visibility"], "dependency": "Spyglass"},
]

# Ten terrain types (brochure terrain table + terrain cards).
TERRAIN = [
    {"key": "caatinga", "name": "Caatinga", "traits": ["vantage_point"],
     "special": "Blossoms"},
    {"key": "desert", "name": "Desert",
     "traits": ["fast_trajectory", "vantage_point", "scarcity"], "special": None},
    {"key": "floodplain", "name": "Floodplain",
     "traits": ["fast_trajectory", "bountiful", "vantage_point"], "special": "Floods"},
    {"key": "forest", "name": "Forest", "traits": ["foliage", "bountiful"],
     "special": None},
    {"key": "grassland", "name": "Grassland",
     "traits": ["fast_trajectory", "bountiful", "vantage_point"], "special": None},
    {"key": "hills", "name": "Hills", "traits": ["vantage_point"], "special": None},
    {"key": "marsh", "name": "Marsh",
     "traits": ["bountiful", "vantage_point", "broken_paths", "waterways"],
     "special": None},
    {"key": "mountain", "name": "Mountain",
     "traits": ["broken_paths", "vantage_point"], "special": None},
    {"key": "swamp", "name": "Swamp",
     "traits": ["foliage", "bountiful", "broken_paths", "waterways"], "special": None},
    {"key": "water", "name": "Water", "traits": ["impassable", "waterways"],
     "special": None},
]

# d12 Points of Interest (brochure).
POINTS_OF_INTEREST = [
    (1, "Uninhabited Cave", "Makes it Safer to spend the night and protects when it's Raining."),
    (2, "Wooden Watchtower", "Gives a Vantage Point. Old and creaky; has a chance of collapsing."),
    (3, "Hunting Trail", "Fast Trajectory when traveling through the trail, but is Deadly."),
    (4, "Abandoned Chapel", "Dedicated to a random deity. Possibly haunted."),
    (5, "Buried Treasure", "Recent rains left the chest partially revealed. Guarded by a will-o'-wisp."),
    (6, "Grove of Heart Palms", "Trees with heart-shaped fronds. 1d4 chutes can be foraged; eating one has the effect of a healing potion."),
    (7, "Adventurers' Cache", "A rival adventuring party stashed 1d6 torches and 1d6 rations here."),
    (8, "Desecrated Monument", "Old statue emanates necromantic energy. Attracts ghouls at night."),
    (9, "Fey-Kept Orchard", "Forage automatically succeeds here, but angers a nearby curupira."),
    (10, "Stargazer Monoliths", "Sleeping in this henge gives prophetic dreams. Get a Luck Token."),
    (11, "Ancient Portals", "Lies inactive. Reactivation connects it to other portals."),
    (12, "Earthmote", "Floating over the land. Atop is the cabin of a wizard named Randall, who gives good advice, making it Safer for the next 3 days."),
]

# d10 Quick Encounters (WEBSITE ONLY — verdant.ibir.cc, no PDF source).
QUICK_ENCOUNTERS = [
    (1, "Dark Clouds", "It will rain soon. Raining and Reduced Visibility next Watch."),
    (2, "Hungry Vermin", "A rat got into someone's backpack and ate all their rations."),
    (3, "Mosquito Fever", "Easy CON or take 1d4 CON damage (can't heal while sick). Repeat the check once per day; ends on success."),
    (4, "Shooting Star", "Make a wish! Someone gets a Luck Token."),
    (5, "Landslide", "Soil shifts beneath your feet! Normal DEX or take 2d6 damage."),
    (6, "Hole in Backpack", "A character notices their backpack is ruptured. Lose an item."),
    (7, "Quicksand", "Someone falls face-first. Hard DEX to exit, Hard STR to be pulled out. CON check each round to hold breath or take 1d6 damage."),
    (8, "Bad Omen", "A black cat crosses the path or ominous bird sounds bring bad luck. Roll with disadvantage next Watch."),
    (9, "Psychic Crickets", "An unnerving humming sound. Normal CHA or take 2d6 damage."),
    (10, "A Coin on the Ground", "1gp. Must be your lucky day!"),
]

# Terrain features (brochure).
TERRAIN_FEATURES = [
    {"name": "Cliff", "text": "Treat as Impassable Terrain. Climbing: the party can try to climb past if all beat a Normal STR check."},
    {"name": "River", "text": "Treat as Impassable Terrain with Waterways. Crossing: the party can try to swim past if all beat a STR check (Hard for rapids, Easy for slow streams)."},
    {"name": "Road", "text": "Automatic success on Navigate and Fast Trajectory when keeping to the road. Maintained Roads are usually patrolled: Safer if party members aren't outlaws, otherwise Deadly."},
]

# Modes of Transportation (WEBSITE ONLY).
TRANSPORT_MODES = [
    {"key": "mount", "name": "Mount", "text": "Mounts made for fast transport (e.g. horses) speed up travel. Rush: once per day, gain an additional Journey Round in the same watch. You can't rush from a terrain with Broken Paths."},
    {"key": "boat", "name": "Boat", "text": "Canoes, sailboats, longships and other vessels travel through Waterways. Boats not powered by the party aren't limited to 2 Watches of travel a day."},
    {"key": "airship", "name": "Airship", "text": "Airships can travel over Impassable Terrain and ignore Arduous Terrain."},
]

CONSTANTS = {
    "erBase": 4,            # ER = erBase + (partySize // 2)
    "safer": 2,
    "riskier": -1,
    "deadly": -2,
    "pace": {"slow": 2, "fast": -2},   # added to the round's baseline Safety
    "watches": [
        {"n": 1, "name": "Morning", "night": False},
        {"n": 2, "name": "Afternoon", "night": False},
        {"n": 3, "name": "Evening", "night": True},
        {"n": 4, "name": "Night", "night": True},
    ],
    # Live website v1.2 rule (supersedes the brochure's stale natural-1 rule):
    "encounterRule": "d12 + Safety Level < ER => dangerous encounter; a natural 12 => an encounter with no immediate danger.",
}


def build():
    return {
        "license": "CC BY-NC-SA 4.0",
        "attribution": "Verdant Hexcrawling (c) 2026 Vince Pinton / Ibir Publishing",
        "source": "https://verdant.ibir.cc",
        "traits": TRAITS,
        "journey_tasks": JOURNEY_TASKS,
        "terrain": TERRAIN,
        "points_of_interest": [
            {"n": n, "name": name, "text": text} for (n, name, text) in POINTS_OF_INTEREST
        ],
        "quick_encounters": [
            {"n": n, "name": name, "text": text} for (n, name, text) in QUICK_ENCOUNTERS
        ],
        "terrain_features": TERRAIN_FEATURES,
        "transport_modes": TRANSPORT_MODES,
        "constants": CONSTANTS,
    }


def verify(data):
    STATS = {"STR", "DEX", "CON", "INT", "WIS", "CHA"}
    traits = data["traits"]
    assert len(traits) == 12, f"expected 12 traits, got {len(traits)}"

    tasks = data["journey_tasks"]
    assert len(tasks) == 12, f"expected 12 tasks, got {len(tasks)}"
    for t in tasks:
        if t["attribute"] is not None:
            assert t["attribute"] in STATS, f"bad attribute {t['attribute']}"
        for ty in t["types"]:
            assert ty in ("T", "S", "C"), f"bad type {ty}"
        for key in t["easier"] + t["harder"]:
            assert key in traits, f"task {t['name']} unknown trait {key}"
        if t["dependency"] in traits:
            pass  # trait-keyed dependency
    terr = data["terrain"]
    assert len(terr) == 10, f"expected 10 terrain, got {len(terr)}"
    keys = {x["key"] for x in terr}
    assert len(keys) == 10, "duplicate terrain key"
    for x in terr:
        for key in x["traits"]:
            assert key in traits, f"terrain {x['name']} unknown trait {key}"

    poi = data["points_of_interest"]
    assert [p["n"] for p in poi] == list(range(1, 13)), "POI must be contiguous 1..12"
    qe = data["quick_encounters"]
    assert [q["n"] for q in qe] == list(range(1, 11)), "quick encounters must be 1..10"
    assert len(data["terrain_features"]) == 3
    assert len(data["transport_modes"]) == 3
    assert {m["key"] for m in data["transport_modes"]} == {"mount", "boat", "airship"}

    w = data["constants"]["watches"]
    assert [x["n"] for x in w] == [1, 2, 3, 4]
    assert [x["night"] for x in w] == [False, False, True, True], "Evening+Night are night"


def cross_check():
    """Best-effort: confirm a few brochure literals appear in the pdftotext extract."""
    if not os.path.exists(RULES_EXTRACT):
        print(f"note: {RULES_EXTRACT} missing; skipping PDF cross-check.")
        return
    with open(RULES_EXTRACT, encoding="utf-8") as f:
        text = f.read()
    for needle in ["Bushwhack", "Camouflage", "Earthmote", "Encounter Risk", "Watches"]:
        assert needle in text, f"expected '{needle}' in {RULES_EXTRACT}"
    print("PDF cross-check passed.")


if __name__ == "__main__":
    data = build()
    verify(data)
    cross_check()
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"wrote {OUT}: {len(data['journey_tasks'])} tasks, "
          f"{len(data['terrain'])} terrain, {len(data['quick_encounters'])} quick encounters")
```

- [ ] **Step 3: Run the build and verify it passes**

Run:
```bash
cd /Users/johntaylor/StudioProjects/juice && python3 build_verdant.py && cp verdant_data.json assets/verdant_data.json && ls -l assets/verdant_data.json
```
Expected: prints `PDF cross-check passed.` and `wrote verdant_data.json: 12 tasks, 10 terrain, 10 quick encounters`; `assets/verdant_data.json` exists.

- [ ] **Step 4: Verify task data against the cards (correctness check, not just structure)**

Open the task cards and confirm each task's attribute / type / easier / harder / dependency matches `JOURNEY_TASKS`. Sources: `/Users/johntaylor/Downloads/Printable Card Sheets.pdf` (pages 1–2) and https://verdant.ibir.cc/Journey+Tasks. Fix any mismatch in `build_verdant.py` and rerun Step 3. (The brochure's column alignment is ambiguous for a few cells — the cards/website are authoritative.)

- [ ] **Step 5: Commit**

```bash
git add build_verdant.py assets/verdant_data.json
git commit -m "feat(verdant): data builder + verdant_data.json asset"
```

### Task 2: bundle the asset + `VerdantData` wrapper + provider

**Files:**
- Modify: `pubspec.yaml` (assets list, after `- assets/help_data.json`)
- Create: `lib/engine/verdant_data.dart`
- Modify: `lib/state/providers.dart` (add `verdantDataProvider` next to `emulatorDataProvider` ~line 744)
- Test: `test/verdant_data_test.dart`

- [ ] **Step 1: Add the asset to `pubspec.yaml`**

In the `flutter: assets:` list, add a line after `- assets/help_data.json`:
```yaml
    - assets/verdant_data.json
```

- [ ] **Step 2: Write the failing test**

Create `test/verdant_data_test.dart`:
```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/verdant_data.dart';

void main() {
  final data = VerdantData(
      jsonDecode(File('assets/verdant_data.json').readAsStringSync())
          as Map<String, dynamic>);

  test('tables load with expected sizes and shapes', () {
    expect(data.tasks.length, 12);
    expect(data.terrain.length, 10);
    expect(data.traits.length, 12);
    expect(data.pointsOfInterest.length, 12);
    expect(data.quickEncounters.length, 10);
    expect(data.transportModes.length, 3);
    expect(data.terrainFeatures.length, 3);
  });

  test('constants expose ER + safety modifiers + watches', () {
    expect(data.erBase, 4);
    expect(data.safer, 2);
    expect(data.riskier, -1);
    expect(data.deadly, -2);
    expect(data.paceSlow, 2);
    expect(data.paceFast, -2);
    expect(data.watches.map((w) => w.night).toList(),
        [false, false, true, true]);
  });

  test('terrain trait keys resolve to trait names', () {
    final forest = data.terrain.firstWhere((t) => t.key == 'forest');
    expect(forest.traits, contains('foliage'));
    expect(data.traitName('foliage'), 'Foliage');
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/verdant_data_test.dart`
Expected: FAIL — `verdant_data.dart` / `VerdantData` does not exist.

- [ ] **Step 4: Write `lib/engine/verdant_data.dart`**

```dart
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// One Journey Task row.
class VerdantTask {
  const VerdantTask({
    required this.name,
    required this.attribute,
    required this.types,
    required this.success,
    required this.failure,
    required this.easier,
    required this.harder,
    required this.dependency,
  });

  final String name;
  final String? attribute; // null for "Something Else"
  final List<String> types; // 'T' | 'S' | 'C'
  final String success;
  final String failure;
  final List<String> easier; // trait keys
  final List<String> harder; // trait keys
  final String? dependency;

  static VerdantTask fromJson(Map<String, dynamic> j) => VerdantTask(
        name: j['name'] as String,
        attribute: j['attribute'] as String?,
        types: (j['types'] as List).cast<String>(),
        success: j['success'] as String,
        failure: j['failure'] as String,
        easier: (j['easier'] as List).cast<String>(),
        harder: (j['harder'] as List).cast<String>(),
        dependency: j['dependency'] as String?,
      );
}

/// One terrain type.
class VerdantTerrain {
  const VerdantTerrain(
      {required this.key,
      required this.name,
      required this.traits,
      required this.special});

  final String key;
  final String name;
  final List<String> traits; // trait keys
  final String? special;

  static VerdantTerrain fromJson(Map<String, dynamic> j) => VerdantTerrain(
        key: j['key'] as String,
        name: j['name'] as String,
        traits: (j['traits'] as List).cast<String>(),
        special: j['special'] as String?,
      );
}

/// A numbered table row (Points of Interest, Quick Encounters).
class VerdantRow {
  const VerdantRow({required this.n, required this.name, required this.text});
  final int n;
  final String name;
  final String text;

  static VerdantRow fromJson(Map<String, dynamic> j) => VerdantRow(
      n: j['n'] as int, name: j['name'] as String, text: j['text'] as String);
}

/// A named text block (terrain features, transport modes).
class VerdantNote {
  const VerdantNote({required this.key, required this.name, required this.text});
  final String key; // '' for terrain features
  final String name;
  final String text;
}

/// One watch in the day cycle.
class VerdantWatch {
  const VerdantWatch({required this.n, required this.name, required this.night});
  final int n;
  final String name;
  final bool night;
}

/// Typed wrapper over assets/verdant_data.json (mirrors EmulatorData/OracleData).
class VerdantData {
  VerdantData(this._json);

  final Map<String, dynamic> _json;

  static Future<VerdantData> load() async {
    final raw = await rootBundle.loadString('assets/verdant_data.json');
    return VerdantData(jsonDecode(raw) as Map<String, dynamic>);
  }

  Map<String, dynamic> get _c => _json['constants'] as Map<String, dynamic>;

  Map<String, String> get traits =>
      (_json['traits'] as Map).cast<String, String>();
  String traitName(String key) => traits[key] ?? key;

  List<VerdantTask> get tasks => (_json['journey_tasks'] as List)
      .map((e) => VerdantTask.fromJson(e as Map<String, dynamic>))
      .toList();

  List<VerdantTerrain> get terrain => (_json['terrain'] as List)
      .map((e) => VerdantTerrain.fromJson(e as Map<String, dynamic>))
      .toList();

  List<VerdantRow> get pointsOfInterest => (_json['points_of_interest'] as List)
      .map((e) => VerdantRow.fromJson(e as Map<String, dynamic>))
      .toList();

  List<VerdantRow> get quickEncounters => (_json['quick_encounters'] as List)
      .map((e) => VerdantRow.fromJson(e as Map<String, dynamic>))
      .toList();

  List<VerdantNote> get terrainFeatures => (_json['terrain_features'] as List)
      .map((e) => VerdantNote(
          key: '',
          name: (e as Map)['name'] as String,
          text: e['text'] as String))
      .toList();

  List<VerdantNote> get transportModes => (_json['transport_modes'] as List)
      .map((e) => VerdantNote(
          key: (e as Map)['key'] as String,
          name: e['name'] as String,
          text: e['text'] as String))
      .toList();

  List<VerdantWatch> get watches => (_c['watches'] as List)
      .map((e) => VerdantWatch(
          n: (e as Map)['n'] as int,
          name: e['name'] as String,
          night: e['night'] as bool))
      .toList();

  int get erBase => _c['erBase'] as int;
  int get safer => _c['safer'] as int;
  int get riskier => _c['riskier'] as int;
  int get deadly => _c['deadly'] as int;
  int get paceSlow => (_c['pace'] as Map)['slow'] as int;
  int get paceFast => (_c['pace'] as Map)['fast'] as int;

  VerdantTerrain? terrainByKey(String key) {
    for (final t in terrain) {
      if (t.key == key) return t;
    }
    return null;
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/verdant_data_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Add the provider**

In `lib/state/providers.dart`, find `emulatorDataProvider` (~line 744) and add directly below it:
```dart
final verdantDataProvider =
    FutureProvider<VerdantData>((ref) => VerdantData.load());
```
Add the import at the top with the other `engine/` imports:
```dart
import '../engine/verdant_data.dart';
```

- [ ] **Step 7: Verify analyze is clean and commit**

Run: `flutter analyze`
Expected: No issues found.
```bash
git add pubspec.yaml lib/engine/verdant_data.dart lib/state/providers.dart test/verdant_data_test.dart
git commit -m "feat(verdant): VerdantData wrapper + verdantDataProvider + asset bundling"
```

---

## Phase 2 — Engine (pure logic)

### Task 3: `lib/engine/verdant.dart` — encounter math, rolls, baseline

**Files:**
- Create: `lib/engine/verdant.dart`
- Test: `test/verdant_engine_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/verdant_engine_test.dart`:
```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/verdant.dart';
import 'package:juice_oracle/engine/verdant_data.dart';

void main() {
  final data = VerdantData(
      jsonDecode(File('assets/verdant_data.json').readAsStringSync())
          as Map<String, dynamic>);

  test('encounterRisk = 4 + party ~/ 2', () {
    expect(encounterRisk(1), 4);
    expect(encounterRisk(2), 5);
    expect(encounterRisk(3), 5);
    expect(encounterRisk(4), 6);
  });

  test('resolveEncounter: natural 12 is benign, low total is danger', () {
    // ER 5: d12+safety < 5 => danger.
    expect(resolveEncounter(d12: 12, safety: 0, er: 5), EncounterOutcome.benign);
    expect(resolveEncounter(d12: 12, safety: -4, er: 5), EncounterOutcome.benign);
    expect(resolveEncounter(d12: 2, safety: 0, er: 5), EncounterOutcome.danger);
    expect(resolveEncounter(d12: 5, safety: 0, er: 5), EncounterOutcome.none);
    expect(resolveEncounter(d12: 1, safety: 0, er: 5), EncounterOutcome.danger);
    // No natural-1 special case: 1 only triggers via the < ER comparison.
    expect(resolveEncounter(d12: 1, safety: 10, er: 5), EncounterOutcome.none);
  });

  test('baselineSafety stacks night and pace', () {
    expect(baselineSafety(night: false, pace: Pace.normal), 0);
    expect(baselineSafety(night: true, pace: Pace.normal), -2);
    expect(baselineSafety(night: false, pace: Pace.slow), 2);
    expect(baselineSafety(night: false, pace: Pace.fast), -2);
    expect(baselineSafety(night: true, pace: Pace.slow), 0);
    expect(baselineSafety(night: true, pace: Pace.fast), -4);
  });

  test('rolls land in range and map to the right table rows', () {
    final dice = Dice(_Seq([1, 12, 7, 3]));
    expect(rollPoi(dice, data).n, 1);
    final qe = rollQuickEncounter(dice, data);
    expect(qe.n, greaterThanOrEqualTo(1));
    expect(qe.n, lessThanOrEqualTo(10));
    expect(rollTerrain(dice, data).key, isNotEmpty);
  });
}

/// Deterministic RNG: returns (value-1) so Dice.dN(n) yields the queued value.
class _Seq implements RandomLike {}
```

> NOTE: the existing `Dice` takes a `dart:math` `Random`. For determinism use
> `Dice(_SeqRandom([...]))` where `_SeqRandom extends Random`. Replace the
> `_Seq`/`RandomLike` stub above with this helper at the bottom of the test file:
```dart
import 'dart:math';

class _SeqRandom implements Random {
  _SeqRandom(this._values);
  final List<int> _values;
  int _i = 0;
  @override
  int nextInt(int max) {
    final v = _values[_i++ % _values.length];
    return (v - 1) % max; // so Dice.dN returns v
  }
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}
```
Use `Dice(_SeqRandom([1]))` to force `dN`/`d12`/`d10` to return 1, etc. Adjust the roll test to queue concrete values and assert exact rows (e.g. `Dice(_SeqRandom([1]))` → `rollPoi(...).n == 1`).

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/verdant_engine_test.dart`
Expected: FAIL — `verdant.dart` does not exist.

- [ ] **Step 3: Write `lib/engine/verdant.dart`**

```dart
import 'verdant_data.dart';
import 'dice.dart';

/// Travel pace (Optional Rule: Travel Pace).
enum Pace { normal, slow, fast }

/// Result of an end-of-round Random Encounter check.
enum EncounterOutcome { none, danger, benign }

/// ER = 4 + (characters in party / 2), rounded down. Independent Followers
/// are excluded by callers (they pass the contributing party count only).
int encounterRisk(int partySize) => 4 + (partySize ~/ 2);

/// Live website v1.2 rule: a dangerous encounter when `d12 + safety < er`;
/// a natural 12 is a benign encounter (no immediate danger); otherwise none.
/// There is no natural-1 special case.
EncounterOutcome resolveEncounter(
    {required int d12, required int safety, required int er}) {
  if (d12 == 12) return EncounterOutcome.benign;
  if (d12 + safety < er) return EncounterOutcome.danger;
  return EncounterOutcome.none;
}

/// Round-start Safety baseline: standing conditions stack. Nighttime (Evening
/// or Night watch) is Deadly (−2); Slow pace is Safer (+2); Fast pace is
/// Deadly (−2). Task outcomes are added on top during the round.
int baselineSafety({required bool night, Pace pace = Pace.normal}) {
  var s = night ? -2 : 0;
  if (pace == Pace.slow) s += 2;
  if (pace == Pace.fast) s += -2;
  return s;
}

/// d12 + safety vs er, returning the die and the outcome.
({int d12, EncounterOutcome outcome}) rollEncounter(Dice dice,
    {required int safety, required int er}) {
  final d12 = dice.dN(12);
  return (d12: d12, outcome: resolveEncounter(d12: d12, safety: safety, er: er));
}

VerdantRow rollPoi(Dice dice, VerdantData data) =>
    data.pointsOfInterest[dice.dN(12) - 1];

VerdantRow rollQuickEncounter(Dice dice, VerdantData data) =>
    data.quickEncounters[dice.dN(10) - 1];

/// Homebrew (not a Verdant rule): pick a terrain at random for solo map-gen.
VerdantTerrain rollTerrain(Dice dice, VerdantData data) =>
    data.terrain[dice.dN(10) - 1];
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/verdant_engine_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/verdant.dart test/verdant_engine_test.dart
git commit -m "feat(verdant): pure engine — ER, natural-12 encounter, pace baseline, rolls"
```

---
## Phase 3 — State

### Task 4: `VerdantJourney` model + `VerdantNotifier` + persistence

**Files:**
- Create: `lib/state/verdant.dart`
- Modify: `lib/state/providers.dart` (`sessionScopedKeys` list — add `'juice.verdant.v1'`)
- Test: `test/verdant_state_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/verdant_state_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/verdant.dart';
import 'package:juice_oracle/state/verdant.dart';

void main() {
  test('defaults', () {
    const j = VerdantJourney();
    expect(j.partySize, 1);
    expect(j.independentFollowers, 0);
    expect(j.day, 1);
    expect(j.watch, 1);
    expect(j.step, 1);
    expect(j.pace, Pace.normal);
    expect(j.transport, isNull);
    expect(j.rushUsedToday, false);
  });

  test('JSON round-trip preserves all fields', () {
    const j = VerdantJourney(
      partySize: 3,
      independentFollowers: 2,
      day: 4,
      watch: 3,
      step: 5,
      safetyLevel: -1,
      pace: Pace.fast,
      transport: 'mount',
      rushUsedToday: true,
      travelingThisRound: true,
      roundNote: 'note',
    );
    final back = VerdantJourney.fromJson(j.toJson());
    expect(back.partySize, 3);
    expect(back.independentFollowers, 2);
    expect(back.day, 4);
    expect(back.watch, 3);
    expect(back.step, 5);
    expect(back.safetyLevel, -1);
    expect(back.pace, Pace.fast);
    expect(back.transport, 'mount');
    expect(back.rushUsedToday, true);
    expect(back.travelingThisRound, true);
    expect(back.roundNote, 'note');
  });

  test('tolerant fromJson: unknown pace/transport + missing keys -> defaults', () {
    final j = VerdantJourney.fromJson({'pace': 'zoom', 'transport': 'jetpack'});
    expect(j.pace, Pace.normal);
    expect(j.transport, isNull); // unknown transport dropped
    expect(j.partySize, 1);
  });

  test('newRoundSafety baseline = night ± pace', () {
    // watch 4 (Night) + fast pace -> -2 + -2 = -4.
    const j = VerdantJourney(watch: 4, pace: Pace.fast);
    expect(j.newRoundSafety, -4);
    // watch 1 (Morning) + slow -> +2.
    const k = VerdantJourney(watch: 1, pace: Pace.slow);
    expect(k.newRoundSafety, 2);
  });

  test('er excludes independent followers', () {
    const j = VerdantJourney(partySize: 4, independentFollowers: 3);
    expect(j.er, 6); // 4 + 4~/2, followers ignored
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/verdant_state_test.dart`
Expected: FAIL — `state/verdant.dart` does not exist.

- [ ] **Step 3: Write `lib/state/verdant.dart`**

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/verdant.dart';
import 'providers.dart' show sessionsProvider;

const _kTransportKeys = {'mount', 'boat', 'airship'};

/// Persisted Verdant journey bookkeeping. Map/hex data lives in mapProvider.
class VerdantJourney {
  const VerdantJourney({
    this.partySize = 1,
    this.independentFollowers = 0,
    this.day = 1,
    this.watch = 1,
    this.step = 1,
    this.safetyLevel = 0,
    this.pace = Pace.normal,
    this.transport,
    this.rushUsedToday = false,
    this.travelingThisRound = false,
    this.roundNote = '',
  });

  final int partySize;
  final int independentFollowers;
  final int day;
  final int watch; // 1..4
  final int step; // 1..6 (Journey Round step)
  final int safetyLevel;
  final Pace pace;
  final String? transport; // 'mount' | 'boat' | 'airship' | null
  final bool rushUsedToday;
  final bool travelingThisRound;
  final String roundNote;

  bool get isNight => watch >= 3; // Evening or Night
  int get er => encounterRisk(partySize); // followers excluded
  int get newRoundSafety => baselineSafety(night: isNight, pace: pace);

  VerdantJourney copyWith({
    int? partySize,
    int? independentFollowers,
    int? day,
    int? watch,
    int? step,
    int? safetyLevel,
    Pace? pace,
    String? transport,
    bool clearTransport = false,
    bool? rushUsedToday,
    bool? travelingThisRound,
    String? roundNote,
  }) =>
      VerdantJourney(
        partySize: partySize ?? this.partySize,
        independentFollowers: independentFollowers ?? this.independentFollowers,
        day: day ?? this.day,
        watch: watch ?? this.watch,
        step: step ?? this.step,
        safetyLevel: safetyLevel ?? this.safetyLevel,
        pace: pace ?? this.pace,
        transport: clearTransport ? null : (transport ?? this.transport),
        rushUsedToday: rushUsedToday ?? this.rushUsedToday,
        travelingThisRound: travelingThisRound ?? this.travelingThisRound,
        roundNote: roundNote ?? this.roundNote,
      );

  Map<String, dynamic> toJson() => {
        'partySize': partySize,
        'independentFollowers': independentFollowers,
        'day': day,
        'watch': watch,
        'step': step,
        'safetyLevel': safetyLevel,
        'pace': pace.name,
        'transport': transport,
        'rushUsedToday': rushUsedToday,
        'travelingThisRound': travelingThisRound,
        'roundNote': roundNote,
      };

  factory VerdantJourney.fromJson(Map<String, dynamic> j) {
    final paceName = j['pace'] as String?;
    final pace =
        Pace.values.where((p) => p.name == paceName).firstOrNull ?? Pace.normal;
    final t = j['transport'] as String?;
    return VerdantJourney(
      partySize: (j['partySize'] as int?) ?? 1,
      independentFollowers: (j['independentFollowers'] as int?) ?? 0,
      day: (j['day'] as int?) ?? 1,
      watch: ((j['watch'] as int?) ?? 1).clamp(1, 4),
      step: ((j['step'] as int?) ?? 1).clamp(1, 6),
      safetyLevel: (j['safetyLevel'] as int?) ?? 0,
      pace: pace,
      transport: _kTransportKeys.contains(t) ? t : null,
      rushUsedToday: (j['rushUsedToday'] as bool?) ?? false,
      travelingThisRound: (j['travelingThisRound'] as bool?) ?? false,
      roundNote: (j['roundNote'] as String?) ?? '',
    );
  }
}

class VerdantNotifier extends AsyncNotifier<VerdantJourney> {
  static const _baseKey = 'juice.verdant.v1';
  late String _scopedKey;

  @override
  Future<VerdantJourney> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey);
    if (raw == null || raw.isEmpty) return const VerdantJourney();
    return VerdantJourney.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<VerdantJourney> get _ready async => state.valueOrNull ?? await future;

  Future<void> save(VerdantJourney j) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, jsonEncode(j.toJson()));
    state = AsyncData(j);
  }

  Future<void> setPartySize(int n) async =>
      save((await _ready).copyWith(partySize: n.clamp(1, 99)));

  Future<void> setFollowers(int n) async =>
      save((await _ready).copyWith(independentFollowers: n.clamp(0, 99)));

  Future<void> setPace(Pace p) async => save((await _ready).copyWith(pace: p));

  Future<void> setTransport(String? key) async {
    final s = await _ready;
    await save(key == null
        ? s.copyWith(clearTransport: true)
        : s.copyWith(transport: key));
  }

  Future<void> setWatch(int w) async =>
      save((await _ready).copyWith(watch: w.clamp(1, 4)));

  Future<void> setTraveling(bool v) async =>
      save((await _ready).copyWith(travelingThisRound: v));

  /// A task outcome: Safer (+2) / Riskier (−1) / Deadly (−2).
  Future<void> applyDelta(int delta) async {
    final s = await _ready;
    await save(s.copyWith(safetyLevel: s.safetyLevel + delta));
  }

  Future<void> setSafety(int v) async =>
      save((await _ready).copyWith(safetyLevel: v));

  Future<void> advanceStep() async {
    final s = await _ready;
    await save(s.copyWith(step: s.step >= 6 ? 6 : s.step + 1));
  }

  /// Start a fresh round: step 1, Safety reset to the night±pace baseline.
  Future<void> newRound() async {
    final s = await _ready;
    await save(s.copyWith(step: 1, safetyLevel: s.newRoundSafety, roundNote: ''));
  }

  /// Advance the watch; past Night rolls into the next day and resets Rush.
  Future<void> nextWatch() async {
    final s = await _ready;
    if (s.watch >= 4) {
      await save(s.copyWith(day: s.day + 1, watch: 1, rushUsedToday: false));
    } else {
      await save(s.copyWith(watch: s.watch + 1));
    }
  }

  /// Mounts only: once per day. Caller checks transport == 'mount'.
  Future<void> useRush() async {
    final s = await _ready;
    if (s.rushUsedToday) return;
    await save(s.copyWith(rushUsedToday: true));
  }

  Future<void> reset() async {
    await _ready;
    await save(const VerdantJourney());
  }
}

final verdantProvider =
    AsyncNotifierProvider<VerdantNotifier, VerdantJourney>(VerdantNotifier.new);
```

> NOTE: `firstOrNull` needs `import 'package:collection/collection.dart';` OR
> replace with: `Pace.values.firstWhere((p) => p.name == paceName, orElse: () => Pace.normal)`.
> Use the `orElse` form to avoid adding a dependency.

- [ ] **Step 4: Fix the `firstOrNull` usage**

Replace the `pace` resolution in `fromJson` with:
```dart
    final pace = Pace.values
        .firstWhere((p) => p.name == paceName, orElse: () => Pace.normal);
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/verdant_state_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Register the persistence key**

In `lib/state/providers.dart`, add `'juice.verdant.v1'` to the `sessionScopedKeys` list (after `'juice.map.v1'`):
```dart
  'juice.map.v1',
  'juice.verdant.v1',
  'juice.settings.v1',
```

- [ ] **Step 7: Verify analyze + commit**

Run: `flutter analyze`
Expected: No issues found.
```bash
git add lib/state/verdant.dart lib/state/providers.dart test/verdant_state_test.dart
git commit -m "feat(verdant): VerdantJourney state + notifier + session-scoped persistence"
```

---

## Phase 4 — Map integration (additive)

### Task 5: `HexCell` gains optional `terrain` + `pois`

**Files:**
- Modify: `lib/engine/models.dart` (HexCell ~lines 392–425)
- Test: extend `test/map_screen_test.dart` (or add `test/hexcell_test.dart`)

- [ ] **Step 1: Write the failing test**

Add to a new file `test/hexcell_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('terrain + pois round-trip; omitted when empty', () {
    const bare = HexCell(col: 0, row: 0, envRow: 3);
    expect(bare.terrain, isNull);
    expect(bare.pois, isEmpty);
    expect(bare.toJson().containsKey('terrain'), false);
    expect(bare.toJson().containsKey('pois'), false);

    const full = HexCell(
        col: 1, row: 2, envRow: 5, terrain: 'forest', pois: [3, 7]);
    final back = HexCell.maybeFromJson(full.toJson())!;
    expect(back.terrain, 'forest');
    expect(back.pois, [3, 7]);
    expect(back.envRow, 5);
  });

  test('copyWith sets terrain + pois', () {
    const c = HexCell(col: 0, row: 0, envRow: 1);
    final t = c.copyWith(terrain: 'desert', pois: [1]);
    expect(t.terrain, 'desert');
    expect(t.pois, [1]);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/hexcell_test.dart`
Expected: FAIL — `HexCell` has no `terrain`/`pois`.

- [ ] **Step 3: Update `HexCell`**

Replace the `HexCell` class body (lines ~392–425) with:
```dart
class HexCell {
  const HexCell({
    required this.col,
    required this.row,
    required this.envRow,
    this.lost = false,
    this.terrain,
    this.pois = const [],
  });
  final int col;
  final int row;
  final int envRow; // 1..10 -> wilderness_environment table
  final bool lost;
  final String? terrain; // Verdant terrain key, e.g. 'forest'; null = Juice env
  final List<int> pois; // Verdant Points of Interest numbers (1..12)

  HexCell copyWith({
    int? envRow,
    bool? lost,
    String? terrain,
    bool clearTerrain = false,
    List<int>? pois,
  }) =>
      HexCell(
        col: col,
        row: row,
        envRow: envRow ?? this.envRow,
        lost: lost ?? this.lost,
        terrain: clearTerrain ? null : (terrain ?? this.terrain),
        pois: pois ?? this.pois,
      );

  Map<String, dynamic> toJson() => {
        'col': col,
        'row': row,
        'envRow': envRow,
        'lost': lost,
        if (terrain != null) 'terrain': terrain,
        if (pois.isNotEmpty) 'pois': pois,
      };

  /// Parses one hex entry; null for anything without a map shape and int
  /// coordinates. envRow clamps into the table range 1..10.
  static HexCell? maybeFromJson(dynamic j) {
    if (j is! Map || j['col'] is! int || j['row'] is! int) return null;
    return HexCell(
      col: j['col'] as int,
      row: j['row'] as int,
      envRow: ((j['envRow'] as int?) ?? 1).clamp(1, 10),
      lost: (j['lost'] as bool?) ?? false,
      terrain: j['terrain'] as String?,
      pois: ((j['pois'] as List?) ?? const []).whereType<int>().toList(),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/hexcell_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/hexcell_test.dart
git commit -m "feat(verdant): HexCell gains optional terrain + pois (additive, backward-compatible)"
```

### Task 6: `mapProvider` — `setHexTerrain` + `addHexPoi`

**Files:**
- Modify: `lib/state/providers.dart` (`MapNotifier`, after `revealHexAt` ~line 495)
- Test: add to `test/map_screen_test.dart` a `mapProvider` group, OR `test/verdant_map_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/verdant_map_test.dart`:
```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> container({String? mapJson}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      if (mapJson != null) 'juice.map.v1.default': mapJson,
    });
    return ProviderContainer();
  }

  test('setHexTerrain + addHexPoi annotate an existing hex', () async {
    final c = await container(
        mapJson: jsonEncode({
          'hexes': [
            {'col': 0, 'row': 0, 'envRow': 3}
          ],
        }));
    await c.read(mapProvider.future);
    await c.read(mapProvider.notifier).setHexTerrain(0, 0, 'forest');
    await c.read(mapProvider.notifier).addHexPoi(0, 0, 7);
    await c.read(mapProvider.notifier).addHexPoi(0, 0, 7); // no duplicate
    final h = c.read(mapProvider).value!.hexes.single;
    expect(h.terrain, 'forest');
    expect(h.pois, [7]);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/verdant_map_test.dart`
Expected: FAIL — methods don't exist.

- [ ] **Step 3: Add the methods**

In `MapNotifier` (after `revealHexAt`, before `resetDungeon`):
```dart
  /// Set the Verdant terrain key on an existing hex; no-op for unknown cells.
  Future<void> setHexTerrain(int col, int row, String terrainKey) async {
    final s = await _ready;
    if (!s.hexes.any((h) => h.col == col && h.row == row)) return;
    await save(s.copyWith(hexes: [
      for (final h in s.hexes)
        if (h.col == col && h.row == row) h.copyWith(terrain: terrainKey) else h,
    ]));
  }

  /// Add a Point of Interest (1..12) to an existing hex; ignores duplicates.
  Future<void> addHexPoi(int col, int row, int poiN) async {
    final s = await _ready;
    if (!s.hexes.any((h) => h.col == col && h.row == row)) return;
    await save(s.copyWith(hexes: [
      for (final h in s.hexes)
        if (h.col == col && h.row == row)
          h.copyWith(pois: h.pois.contains(poiN) ? h.pois : [...h.pois, poiN])
        else
          h,
    ]));
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/verdant_map_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/verdant_map_test.dart
git commit -m "feat(verdant): mapProvider setHexTerrain + addHexPoi"
```

### Task 7: `_HexPainter` renders Verdant terrain + POI badge

**Files:**
- Modify: `lib/features/map_screen.dart` (`_HexPainter` ~lines 662–775, plus a terrain-hue map)

- [ ] **Step 1: Add a terrain-hue map near `_envHues` (~line 404)**

```dart
/// Fixed hues for the 10 Verdant terrain keys (used when a hex has Verdant
/// terrain instead of a Juice envRow).
const Map<String, Color> _verdantTerrainHues = {
  'caatinga': Color(0xFF8D6E63),
  'desert': Color(0xFFE0C068),
  'floodplain': Color(0xFF7CB342),
  'forest': Color(0xFF2E7D32),
  'grassland': Color(0xFF9CCC65),
  'hills': Color(0xFFA1887F),
  'marsh': Color(0xFF26A69A),
  'mountain': Color(0xFF78909C),
  'swamp': Color(0xFF558B2F),
  'water': Color(0xFF1E88E5),
};
```

- [ ] **Step 2: In `_HexPainter.paint`, branch fill + label on `terrain`**

Find where each hex's fill is computed (`_envHues[h.envRow - 1]...`) and the name label (`envNames[h.envRow - 1]`). Replace the fill computation:
```dart
      final hasTerrain = h.terrain != null;
      final baseHue = hasTerrain
          ? (_verdantTerrainHues[h.terrain] ?? scheme.surfaceVariant)
          : _envHues[h.envRow - 1];
      final fill = (isCurrent ? baseHue : baseHue.withValues(alpha: 0.5));
```
and the label:
```dart
      final name = hasTerrain
          ? (h.terrain![0].toUpperCase() + h.terrain!.substring(1))
          : envNames[h.envRow - 1];
```

- [ ] **Step 3: Draw a POI count badge when `h.pois` is non-empty**

After painting the hex name, inside the per-hex loop, add:
```dart
      if (h.pois.isNotEmpty) {
        final badge = TextPainter(
          text: TextSpan(
            text: '★${h.pois.length}',
            style: TextStyle(color: scheme.tertiary, fontSize: 11),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        badge.paint(canvas, center + Offset(-badge.width / 2, 10));
      }
```
(Use the same `center`/`scheme` the loop already computes for the name; match local variable names.)

- [ ] **Step 4: Update `shouldRepaint` to react to terrain/POI changes**

`_HexPainter.shouldRepaint` compares hex lists. Ensure it repaints when terrain/pois change — comparing `hexes` identity already covers this because `save()` always produces a new list. No change needed if it compares `old.hexes != hexes`; if it compares lengths only, change to also compare a content signature. Verify by reading the existing `shouldRepaint`.

- [ ] **Step 5: Verify analyze + existing map tests still pass + commit**

Run: `flutter analyze && flutter test test/map_screen_test.dart`
Expected: No issues; all map tests pass (rendering is additive; envRow path unchanged).
```bash
git add lib/features/map_screen.dart
git commit -m "feat(verdant): Hex tab renders Verdant terrain + POI badge (envRow fallback)"
```

---

## Phase 5 — System + tool registration

### Task 8: register `'verdant'` system, tool, help mapping, and new-campaign checkbox

**Files:**
- Modify: `lib/engine/models.dart` (`kAllSystems` ~line 727)
- Modify: `lib/shared/tool_registry.dart` (imports, `toolSystem`, `toolHelpPage`, `buildToolRegistry`)
- Modify: `lib/shared/home_shell.dart` (`_NewCampaignDialogState`: `_verdant` field, `_submit`, a `sys-verdant` checkbox, doc comment)
- Modify: `test/home_shell_test.dart` (the "system checkboxes" test — expect a fifth checkbox)
- Test: extend `test/home_shell_test.dart`

- [ ] **Step 1: Add `'verdant'` to `kAllSystems`**

In `lib/engine/models.dart`:
```dart
const kAllSystems = {'juice', 'mythic', 'ironsworn', 'party', 'verdant'};
```

- [ ] **Step 2: Register the tool**

In `lib/shared/tool_registry.dart`:
- Add import: `import '../features/verdant_screen.dart';`
- In `toolSystem`, add: `'verdant': 'verdant',`
- In `toolHelpPage`, add: `'verdant': 'verdant',`
- In `buildToolRegistry`'s `all` list, add a `ToolDef` in the Exploration group (after the `maps` entry):
```dart
    ToolDef(
      id: 'verdant',
      label: 'Verdant Journey',
      icon: Icons.forest_outlined,
      group: 'Exploration',
      badge: 'Verdant',
      builder: (o) => VerdantScreen(oracle: o!),
    ),
```

- [ ] **Step 3: Add the new-campaign checkbox**

In `lib/shared/home_shell.dart` `_NewCampaignDialogState`:
- Add field: `bool _verdant = true;`
- In `_submit`'s `picked` set, add: `if (_verdant) 'verdant',`
- Add a `CheckboxListTile` after the party one:
```dart
          CheckboxListTile(
            key: const Key('sys-verdant'),
            title: const Text('Verdant Hexcrawling'),
            value: _verdant,
            onChanged: (v) => setState(() => _verdant = v ?? true),
          ),
```
- Update the dialog doc comment "four system checkboxes" → "five system checkboxes".

- [ ] **Step 4: Update the existing home_shell test**

Read `test/home_shell_test.dart`'s "new campaign dialog shows system checkboxes" test. If it asserts a specific count of `CheckboxListTile`s or checks specific keys, add `sys-verdant`. If it only unchecks party, add an assertion that `find.byKey(const Key('sys-verdant'))` exists and that leaving it checked includes `'verdant'` in the created campaign's systems. Make the minimal change to keep it green and cover the new checkbox.

- [ ] **Step 5: Run the tests + analyze**

Run: `flutter test test/home_shell_test.dart && flutter analyze`
Expected: PASS; No issues found. (VerdantScreen must exist — this task depends on Phase 6 Task 9. If executing in order, either stub `VerdantScreen` first or do Task 9 before Step 2 here. Recommended: implement Task 9 first, then this task. Reorder accordingly.)

- [ ] **Step 6: Commit**

```bash
git add lib/engine/models.dart lib/shared/tool_registry.dart lib/shared/home_shell.dart test/home_shell_test.dart
git commit -m "feat(verdant): register verdant system, tool, help mapping, campaign checkbox"
```

---
## Phase 6 — UI

> **Execution order:** Do Task 9 BEFORE Task 8 Step 2 (the tool registry imports `VerdantScreen`). If using subagent-driven execution, run Task 9, then Task 8.

### Task 9: `lib/features/verdant_screen.dart` + widget tests

**Files:**
- Create: `lib/features/verdant_screen.dart`
- Test: `test/verdant_screen_test.dart`

**Loose-constraint rules (mandatory):** root is a `ListView` (gives children bounded
width + vertical scroll — safe under the tool host's loose constraints). Multi-button
rows use `Wrap`. No `TabBarView`. Verify on the Pixel in Phase 8.

- [ ] **Step 1: Write `lib/features/verdant_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/oracle.dart';
import '../engine/verdant.dart';
import '../engine/verdant_data.dart';
import '../state/providers.dart';
import '../state/verdant.dart';

/// Solo journey tracker / play-aid for Verdant Hexcrawling. Owns the
/// Safety-Level / Encounter-Risk / Watch state and the dice; the player
/// resolves tasks. Terrain + POIs plot onto the shared hex map (mapProvider).
class VerdantScreen extends ConsumerWidget {
  const VerdantScreen({super.key, required this.oracle});

  final Oracle oracle;

  static const _watchNames = ['Morning', 'Afternoon', 'Evening', 'Night'];
  static const _stepNames = [
    'Round Starts — declare Watch',
    'Travel — move to next hex',
    'Task Assignment',
    'Task Execution — roll checks',
    'Time Passes — reveal hexes',
    'Danger! — roll encounter',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journeyAsync = ref.watch(verdantProvider);
    final dataAsync = ref.watch(verdantDataProvider);
    final mapAsync = ref.watch(mapProvider);

    return journeyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Verdant error: $e')),
      data: (j) => dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Verdant data error: $e')),
        data: (data) => _body(context, ref, j, data, mapAsync.valueOrNull),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, VerdantJourney j,
      VerdantData data, MapState? map) {
    final theme = Theme.of(context);
    final notifier = ref.read(verdantProvider.notifier);
    final currentHex = (map == null ||
            map.currentHexCol == null ||
            map.currentHexRow == null)
        ? null
        : map.hexes
            .where((h) =>
                h.col == map.currentHexCol && h.row == map.currentHexRow)
            .cast<HexCell?>()
            .firstOrNull;

    return ListView(
      key: const Key('verdant-list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // -- Header: day / watch / party / ER --
        Text('Day ${j.day}', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Watch', style: theme.textTheme.labelLarge),
        Wrap(
          spacing: 6,
          children: [
            for (var i = 0; i < 4; i++)
              ChoiceChip(
                key: Key('watch-${i + 1}'),
                label: Text('${_watchNames[i]}${i >= 2 ? ' 🌖' : ''}'),
                selected: j.watch == i + 1,
                onSelected: (_) => notifier.setWatch(i + 1),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _stepper(context, 'Party in party', j.partySize,
            (v) => notifier.setPartySize(v),
            min: 1, keyName: 'party'),
        _stepper(context, 'Independent followers (excluded from ER)',
            j.independentFollowers, (v) => notifier.setFollowers(v),
            min: 0, keyName: 'followers'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('Encounter Risk: ${j.er}',
              key: const Key('verdant-er'),
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
        ),
        const Divider(),

        // -- Pace + transport --
        Text('Travel pace', style: theme.textTheme.labelLarge),
        SegmentedButton<Pace>(
          segments: const [
            ButtonSegment(value: Pace.normal, label: Text('Normal')),
            ButtonSegment(value: Pace.slow, label: Text('Slow +2')),
            ButtonSegment(value: Pace.fast, label: Text('Fast −2')),
          ],
          selected: {j.pace},
          showSelectedIcon: false,
          onSelectionChanged: (s) => notifier.setPace(s.first),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Transport', style: theme.textTheme.labelLarge),
            const SizedBox(width: 12),
            Flexible(
              child: DropdownButton<String?>(
                key: const Key('verdant-transport'),
                isExpanded: true,
                value: j.transport,
                items: [
                  const DropdownMenuItem(value: null, child: Text('On foot')),
                  for (final m in data.transportModes)
                    DropdownMenuItem(value: m.key, child: Text(m.name)),
                ],
                onChanged: (v) => notifier.setTransport(v),
              ),
            ),
            if (j.transport == 'mount') ...[
              const SizedBox(width: 8),
              FilledButton.tonal(
                key: const Key('verdant-rush'),
                onPressed: j.rushUsedToday ? null : () => notifier.useRush(),
                child: Text(j.rushUsedToday ? 'Rushed' : 'Rush'),
              ),
            ],
          ],
        ),
        const Divider(),

        // -- Safety dial --
        Text('Safety Level', style: theme.textTheme.labelLarge),
        Text('${j.safetyLevel >= 0 ? '+' : ''}${j.safetyLevel}',
            key: const Key('verdant-safety'),
            style: theme.textTheme.displaySmall),
        Text(_baselineHint(j),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              key: const Key('verdant-safer'),
              onPressed: () => notifier.applyDelta(data.safer),
              child: const Text('Safer +2'),
            ),
            FilledButton.tonal(
              key: const Key('verdant-riskier'),
              onPressed: () => notifier.applyDelta(data.riskier),
              child: const Text('Riskier −1'),
            ),
            OutlinedButton(
              key: const Key('verdant-deadly'),
              onPressed: () => notifier.applyDelta(data.deadly),
              child: const Text('Deadly −2'),
            ),
          ],
        ),
        const Divider(),

        // -- Round stepper --
        Text('Journey Round', style: theme.textTheme.labelLarge),
        Text('${j.step}. ${_stepNames[j.step - 1]}',
            key: const Key('verdant-step'),
            style: theme.textTheme.bodyLarge),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              key: const Key('verdant-advance'),
              onPressed: () => notifier.advanceStep(),
              child: const Text('Next step'),
            ),
            FilledButton.tonal(
              key: const Key('verdant-danger'),
              onPressed: () => _rollDanger(context, ref, j, data),
              child: const Text('Danger! (roll)'),
            ),
            OutlinedButton(
              key: const Key('verdant-new-round'),
              onPressed: () => notifier.newRound(),
              child: const Text('New round'),
            ),
            OutlinedButton(
              key: const Key('verdant-next-watch'),
              onPressed: () => notifier.nextWatch(),
              child: const Text('Next watch'),
            ),
          ],
        ),
        const Divider(),

        // -- Current hex (shared map) --
        Text('Current hex', style: theme.textTheme.labelLarge),
        Text(
          currentHex == null
              ? 'No hex yet — Travel to reveal one.'
              : '${_terrainName(data, currentHex.terrain)}'
                  '${currentHex.pois.isEmpty ? '' : ' · POIs: '
                      '${currentHex.pois.map((n) => data.pointsOfInterest[n - 1].name).join(', ')}'}',
          key: const Key('verdant-current-hex'),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonal(
              key: const Key('verdant-travel'),
              onPressed: () => _travel(ref),
              child: const Text('Travel (reveal hex)'),
            ),
            OutlinedButton(
              key: const Key('verdant-set-terrain'),
              onPressed:
                  currentHex == null ? null : () => _setTerrain(context, ref, data),
              child: const Text('Set terrain'),
            ),
            OutlinedButton(
              key: const Key('verdant-explore'),
              onPressed:
                  currentHex == null ? null : () => _explore(context, ref, data),
              child: const Text('Explore (roll POI)'),
            ),
          ],
        ),
        const Divider(),

        // -- Reference --
        _reference(context, data),
      ],
    );
  }

  String _baselineHint(VerdantJourney j) {
    final parts = <String>[];
    if (j.isNight) parts.add('−2 night');
    if (j.pace == Pace.slow) parts.add('+2 slow');
    if (j.pace == Pace.fast) parts.add('−2 fast');
    final base = parts.isEmpty ? '0' : parts.join(' ');
    return 'New-round baseline: $base = ${j.newRoundSafety}';
  }

  String _terrainName(VerdantData data, String? key) {
    if (key == null) return 'Unset terrain';
    return data.terrainByKey(key)?.name ?? key;
  }

  Future<void> _travel(WidgetRef ref) async {
    // Reveal the next hex (envRow placeholder; Verdant terrain overrides display).
    await ref
        .read(mapProvider.notifier)
        .revealHex(envRow: 1, lost: false, dice: oracle.dice);
  }

  Future<void> _explore(
      BuildContext context, WidgetRef ref, VerdantData data) async {
    final map = ref.read(mapProvider).valueOrNull;
    if (map?.currentHexCol == null) return;
    final poi = rollPoi(oracle.dice, data);
    await ref
        .read(mapProvider.notifier)
        .addHexPoi(map!.currentHexCol!, map.currentHexRow!, poi.n);
    await ref
        .read(journalProvider.notifier)
        .add('Verdant — Point of Interest', '${poi.name}. ${poi.text}');
    if (context.mounted) {
      _snack(context, 'Found: ${poi.name}');
    }
  }

  Future<void> _setTerrain(
      BuildContext context, WidgetRef ref, VerdantData data) async {
    final map = ref.read(mapProvider).valueOrNull;
    if (map?.currentHexCol == null) return;
    final key = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              key: const Key('terrain-roll'),
              leading: const Icon(Icons.casino_outlined),
              title: const Text('Roll random terrain (homebrew)'),
              onTap: () =>
                  Navigator.pop(ctx, rollTerrain(oracle.dice, data).key),
            ),
            const Divider(),
            for (final t in data.terrain)
              ListTile(
                key: Key('terrain-${t.key}'),
                title: Text(t.name),
                subtitle: Text(t.traits.map(data.traitName).join(' · ')),
                onTap: () => Navigator.pop(ctx, t.key),
              ),
          ],
        ),
      ),
    );
    if (key == null) return;
    await ref
        .read(mapProvider.notifier)
        .setHexTerrain(map!.currentHexCol!, map.currentHexRow!, key);
  }

  Future<void> _rollDanger(
      BuildContext context, WidgetRef ref, VerdantJourney j, VerdantData data) async {
    final r = rollEncounter(oracle.dice, safety: j.safetyLevel, er: j.er);
    final label = switch (r.outcome) {
      EncounterOutcome.danger => 'Encounter!',
      EncounterOutcome.benign => 'Benign encounter',
      EncounterOutcome.none => 'Clear',
    };
    var body = 'd12 ${r.d12} + safety ${j.safetyLevel} vs ER ${j.er} → $label';
    if (r.outcome != EncounterOutcome.none) {
      final qe = rollQuickEncounter(oracle.dice, data);
      body = '$body\n${qe.name}: ${qe.text}';
    }
    await ref
        .read(journalProvider.notifier)
        .add('Verdant — Day ${j.day} ${_watchNames[j.watch - 1]}', body);
    if (context.mounted) _snack(context, label);
  }

  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));

  Widget _stepper(BuildContext context, String label, int value,
      void Function(int) onChanged,
      {required int min, required String keyName}) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          key: Key('$keyName-minus'),
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Text('$value', key: Key('$keyName-value')),
        IconButton(
          key: Key('$keyName-plus'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => onChanged(value + 1),
        ),
      ],
    );
  }

  Widget _reference(BuildContext context, VerdantData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExpansionTile(
          key: const Key('ref-tasks'),
          title: const Text('Journey Tasks'),
          children: [
            for (final t in data.tasks)
              ListTile(
                dense: true,
                title: Text('${t.name}'
                    '${t.attribute == null ? '' : ' (${t.attribute})'}'),
                subtitle: Text('${t.types.join('/')} · '
                    '✓ ${t.success} / ✗ ${t.failure}'
                    '${t.dependency == null ? '' : ' · needs ${t.dependency}'}'),
              ),
          ],
        ),
        ExpansionTile(
          key: const Key('ref-terrain'),
          title: const Text('Terrain & Traits'),
          children: [
            for (final t in data.terrain)
              ListTile(
                dense: true,
                title: Text(t.name),
                subtitle: Text([
                  ...t.traits.map(data.traitName),
                  if (t.special != null) '★ ${t.special}',
                ].join(' · ')),
              ),
          ],
        ),
        ExpansionTile(
          key: const Key('ref-poi'),
          title: const Text('Points of Interest (d12)'),
          children: [
            for (final p in data.pointsOfInterest)
              ListTile(
                  dense: true,
                  leading: Text('${p.n}'),
                  title: Text(p.name),
                  subtitle: Text(p.text)),
          ],
        ),
        ExpansionTile(
          key: const Key('ref-quick'),
          title: const Text('Quick Encounters (d10)'),
          children: [
            for (final q in data.quickEncounters)
              ListTile(
                  dense: true,
                  leading: Text('${q.n}'),
                  title: Text(q.name),
                  subtitle: Text(q.text)),
          ],
        ),
        ExpansionTile(
          key: const Key('ref-transport'),
          title: const Text('Modes of Transportation'),
          children: [
            for (final m in data.transportModes)
              ListTile(dense: true, title: Text(m.name), subtitle: Text(m.text)),
            for (final f in data.terrainFeatures)
              ListTile(dense: true, title: Text(f.name), subtitle: Text(f.text)),
          ],
        ),
      ],
    );
  }
}
```

> NOTE: `firstOrNull` on the `currentHex` iterable needs
> `import 'package:collection/collection.dart';` — OR rewrite as a manual loop.
> Check whether `collection` is already a transitive import used elsewhere; if not,
> replace the `currentHex` computation with:
> ```dart
> HexCell? currentHex;
> if (map != null && map.currentHexCol != null && map.currentHexRow != null) {
>   for (final h in map.hexes) {
>     if (h.col == map.currentHexCol && h.row == map.currentHexRow) { currentHex = h; break; }
>   }
> }
> ```
> Use the manual loop to avoid a new dependency. `HexCell` is exported from
> `engine/models.dart` (re-exported via `engine/oracle.dart` or import models directly —
> add `import '../engine/models.dart';` if `HexCell` isn't visible).

- [ ] **Step 2: Write the widget test**

Create `test/verdant_screen_test.dart`:
```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/engine/verdant_data.dart';
import 'package:juice_oracle/features/verdant_screen.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:juice_oracle/state/verdant.dart';

void main() {
  final oracleData = OracleData(
      jsonDecode(File('assets/oracle_data.json').readAsStringSync())
          as Map<String, dynamic>);
  final verdantData = VerdantData(
      jsonDecode(File('assets/verdant_data.json').readAsStringSync())
          as Map<String, dynamic>);

  Future<ProviderContainer> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // Load verdant data from file (rootBundle override for tests).
        verdantDataProvider.overrideWith((ref) async => verdantData),
      ],
      child: MaterialApp(
        home: Scaffold(body: VerdantScreen(oracle: Oracle(oracleData))),
      ),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(VerdantScreen)));
  }

  testWidgets('ER updates with party; followers do not change ER',
      (tester) async {
    await pump(tester);
    expect(find.text('Encounter Risk: 4'), findsOneWidget); // party 1
    await tester.tap(find.byKey(const Key('party-plus'))); // party 2
    await tester.pumpAndSettle();
    expect(find.text('Encounter Risk: 5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('followers-plus'))); // followers 1
    await tester.pumpAndSettle();
    expect(find.text('Encounter Risk: 5'), findsOneWidget); // unchanged
  });

  testWidgets('Safer/Riskier move the dial', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byKey(const Key('verdant-safer')));
    await tester.pumpAndSettle();
    expect(c.read(verdantProvider).value!.safetyLevel, 2);
    await tester.tap(find.byKey(const Key('verdant-riskier')));
    await tester.pumpAndSettle();
    expect(c.read(verdantProvider).value!.safetyLevel, 1);
  });

  testWidgets('Travel reveals a hex; Danger! logs to the journal',
      (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byKey(const Key('verdant-travel')));
    await tester.pumpAndSettle();
    expect(c.read(mapProvider).value!.hexes, isNotEmpty);

    await tester.tap(find.byKey(const Key('verdant-danger')));
    await tester.pumpAndSettle();
    final entries = c.read(journalProvider).value!;
    expect(entries.any((e) => e.title.startsWith('Verdant — Day 1')), true);
  });

  testWidgets('no layout exception under a tight Scaffold', (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('verdant-list')), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the widget test**

Run: `flutter test test/verdant_screen_test.dart`
Expected: PASS (4 tests). Fix any compile errors (imports, `firstOrNull`) per the NOTE above.

- [ ] **Step 4: Commit**

```bash
git add lib/features/verdant_screen.dart test/verdant_screen_test.dart
git commit -m "feat(verdant): Verdant Journey screen (tracker UI) + widget tests"
```

---

## Phase 7 — Attribution & help

### Task 10: credits line + `verdant` help page

**Files:**
- Modify: `assets/help_data.json` (the `credits` page "Content" blocks; add a new `verdant` page)
- Test: extend `test/help_screen_test.dart` (it already asserts every non-help tool id maps to a real help page — `toolHelpPage['verdant']='verdant'` requires a `verdant` page to exist)

- [ ] **Step 1: Add the credits line**

In `assets/help_data.json`, in the `credits` page's `blocks` array, add after the Triple-O / PET lines (keep alphabetical-ish ordering with the other content credits):
```json
{"p": "Verdant Hexcrawling © Vince Pinton / Ibir Publishing — CC BY-NC-SA 4.0 — verdant.ibir.cc. Derived table data in this app stays CC BY-NC-SA 4.0."}
```

- [ ] **Step 2: Add the `verdant` help page**

Find the section that holds tool help pages (the pages referenced by `toolHelpPage`, e.g. the one containing `maps`). Add a new page object to that section's `pages` array:
```json
{
  "id": "verdant",
  "title": "Verdant Journey",
  "blocks": [
    {"p": "A solo tracker for Verdant Hexcrawling (Ibir Publishing). You resolve Journey Tasks in your own game; this tool tracks the Safety Level, Encounter Risk, Watch and rolls the Random Encounter."},
    {"h": "The Journey Round"},
    {"p": "1. Round Starts (declare Watch). 2. Travel. 3. Task Assignment. 4. Task Execution — tap Safer/Riskier as your tasks succeed or fail. 5. Time Passes. 6. Danger! — roll the encounter."},
    {"h": "Safety & Encounter Risk"},
    {"p": "Encounter Risk = 4 + party ÷ 2 (Independent Followers excluded). Each round Safety resets to a baseline: Nighttime (Evening/Night) is Deadly −2, Slow pace +2, Fast pace −2. Danger! rolls d12 + Safety: below ER is a dangerous encounter; a natural 12 is a benign encounter."},
    {"h": "Map"},
    {"p": "Travel reveals a hex on the shared Map; Set terrain and Explore (roll d12 Points of Interest) annotate it. View the map in the Maps tool."},
    {"p": "Verdant Hexcrawling © Vince Pinton / Ibir Publishing, CC BY-NC-SA 4.0."}
  ]
}
```

- [ ] **Step 3: Run the help test + the registry test**

Run: `flutter test test/help_screen_test.dart`
Expected: PASS — including "toolHelpPage maps every non-help tool id to a real help page" (now that `verdant` page exists).

- [ ] **Step 4: Commit**

```bash
git add assets/help_data.json
git commit -m "feat(verdant): credits attribution + Verdant Journey help page"
```

---

## Phase 8 — Verify & ship

### Task 11: full verification, on-device check, PR

- [ ] **Step 1: Full analyze + test suite**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`; all tests pass (≈ existing 620 + new Verdant tests). Fix anything red before proceeding.

- [ ] **Step 2: On-device loose-constraint check (Pixel, debug)**

Build/run on the Pixel and open **Verdant Journey** from the launcher (it's in the Exploration group), then open the **Maps → Hex** tab. Confirm: the Verdant screen renders fully and scrolls; no `RenderFlex`/`BoxConstraints` exceptions in logcat; after Travel + Set terrain + Explore, the Maps Hex tab shows the Verdant terrain colour + a ★ POI badge on the current hex. (Headless tests cannot catch a host freeze — this step is required; see memory `juice-toolhost-loose-constraints`.)

Run (reference): `flutter run -d <pixel-id>` then drive with `adb shell input tap` / `adb exec-out screencap`. Watch logcat for `flutter` layout errors.

- [ ] **Step 3: Update CLAUDE.md project notes**

Add a bullet under "Project notes" documenting `build_verdant.py` → `assets/verdant_data.json` (same rail as `build_emulator.py`; website-sourced quick-encounters/transport have no PDF). Commit:
```bash
git add CLAUDE.md
git commit -m "docs: note build_verdant.py data rail"
```

- [ ] **Step 4: Push + open PR**

```bash
git push -u origin feat/verdant-journey
gh pr create --title "Add Verdant Journey tool (solo Verdant Hexcrawling tracker)" --body "<summary: tracker design, map integration, website-sourced features (d10 quick encounters, travel pace, independent followers, transport, natural-12 fix), attribution CC BY-NC-SA 4.0, verification: analyze+tests+on-device>"
```

- [ ] **Step 5: Mark done**

Confirm CI/checks; report the PR URL.

---

## Self-review (completed by plan author)

**Spec coverage:** §1 Architecture → Tasks 2,4,8. §2 Data asset → Task 1 (all tables incl. quick_encounters/transport + self-verify). §3 Engine → Task 3 (resolveEncounter natural-12, baselineSafety incl. pace, rolls). §4 State → Task 4 (all fields incl. pace/transport/followers/rush; ER excludes followers; tolerant fromJson). §5 Map integration → Tasks 5,6,7 (additive HexCell, mapProvider methods, painter). §6 UI → Task 9 (header/pace/transport/dial/round/current-hex/reference; loose-constraint ListView+Wrap). §7 Attribution → Task 10. §8 Testing → tests in every task + Task 11 (analyze/test/on-device). §9 Out-of-scope respected (no Maintain Results, no char sheets).

**Placeholder scan:** PR body in Task 11 Step 4 is a `<summary>` placeholder — acceptable (final prose written at PR time). All code steps contain complete code. Two `firstOrNull` usages are flagged with concrete dependency-free replacements.

**Type consistency:** `Pace`/`EncounterOutcome` enums defined in Task 3, used identically in Tasks 4 & 9. `VerdantData` accessors (Task 2) match engine/UI call sites. `HexCell.copyWith(terrain:,pois:,clearTerrain:)` (Task 5) matches mapProvider calls (Task 6) and painter reads (Task 7). `setHexTerrain`/`addHexPoi` names consistent Tasks 6↔9. `verdantProvider`/`verdantDataProvider` names consistent Tasks 2,4,9.

**Known ordering dependency:** Task 9 (VerdantScreen) must precede Task 8 Step 2 (registry import) — flagged in Phase 6 header.

