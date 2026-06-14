# Generic Hexcrawl Toolkit — H1 (Foundation + Exploration Tables) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the shared, system-agnostic hexcrawl content library + a generator screen that rolls any exploration table and logs results — the foundation H2–H4 (map generation) build on.

**Architecture:** Mirrors the Verdant data rail: `build_hexcrawl.py` (authored, self-verified) → `assets/hexcrawl_data.json` → `HexcrawlData` model + `hexcrawlDataProvider` → a pure `hexcrawl.dart` weighted/uniform pick engine → a `HexcrawlScreen` generator, gated by a new `hexcrawl` opt-in flag and surfaced as a Maps subtab.

**Tech Stack:** Python 3 (asset), Dart/Flutter, flutter_riverpod, shared_preferences, package:flutter_test.

**Scope guard (H1 only):** content library + plain table-roller. No two-path map generation (H2–H4). No game-specific creatures/stats. No dungeon/local/site content yet (their phases add it).

---

## File structure

**New:** `build_hexcrawl.py`, `assets/hexcrawl_data.json` (generated), `lib/engine/hexcrawl_data.dart`, `lib/engine/hexcrawl.dart`, `lib/features/hexcrawl_screen.dart`, `test/hexcrawl_data_test.dart`, `test/hexcrawl_test.dart`, `test/hexcrawl_screen_test.dart`.
**Edit:** `pubspec.yaml`, `lib/state/providers.dart` (provider), `lib/shared/tool_registry.dart`, `lib/shared/destination.dart`, `lib/features/maps_tab.dart`, `lib/shared/home_shell.dart` (New-Campaign + Edit-systems checkboxes), `test/tool_registry_test.dart`.

---

### Task 1: Content asset — `build_hexcrawl.py` → `assets/hexcrawl_data.json`

**Files:** Create `build_hexcrawl.py`, `assets/hexcrawl_data.json`; Modify `pubspec.yaml`.

- [ ] **Step 1: Write `build_hexcrawl.py`**

```python
#!/usr/bin/env python3
"""Generic, system-agnostic hexcrawl content library — source of truth for the
Hexcrawl toolkit. Authored content (NOT lifted from any game); informed by
common hexcrawl procedure. Same rail as build_verdant.py: this script is
authoritative, self-verifies structure, and emits hexcrawl_data.json. Copy the
output into assets/; never hand-edit the JSON.
"""
import json

CLIMATES = ["cold", "temperate", "hot"]

# Generic terrains. difficulty = navigation/travel difficulty (2 easy .. 4 hard).
TERRAINS = [
    {"key": "arctic", "name": "Arctic", "climates": ["cold"], "difficulty": 3,
     "travelNote": "Slow, exposed; risk of cold.", "features": ["Ice field", "Frozen river", "Snowdrift"]},
    {"key": "coast", "name": "Coast", "climates": ["cold", "temperate", "hot"], "difficulty": 2,
     "travelNote": "Open shoreline; tidal hazards.", "features": ["Tidal flats", "Sea cliffs", "Driftwood"]},
    {"key": "desert", "name": "Desert", "climates": ["hot"], "difficulty": 3,
     "travelNote": "Open but harsh; water is scarce.", "features": ["Dunes", "Dry wash", "Rock spire"]},
    {"key": "forest", "name": "Forest", "climates": ["temperate"], "difficulty": 3,
     "travelNote": "Dense cover slows travel.", "features": ["Old grove", "Game trail", "Fallen timber"]},
    {"key": "hills", "name": "Hills", "climates": ["cold", "temperate", "hot"], "difficulty": 3,
     "travelNote": "Rolling ground; many vantage points.", "features": ["Rocky knoll", "Hidden vale", "Cairn"]},
    {"key": "jungle", "name": "Jungle", "climates": ["hot"], "difficulty": 4,
     "travelNote": "Thick, humid, hard going.", "features": ["Vine wall", "Canopy gap", "Mud wallow"]},
    {"key": "marsh", "name": "Marsh", "climates": ["temperate", "hot"], "difficulty": 4,
     "travelNote": "Boggy, easy to get mired or lost.", "features": ["Reed beds", "Black pool", "Sunken log"]},
    {"key": "mountains", "name": "Mountains", "climates": ["cold", "temperate"], "difficulty": 4,
     "travelNote": "Steep climbs; thin air.", "features": ["Narrow pass", "Sheer cliff", "Scree slope"]},
    {"key": "plains", "name": "Plains", "climates": ["cold", "temperate", "hot"], "difficulty": 2,
     "travelNote": "Open and fast.", "features": ["Tall grass", "Lone tree", "Old road"]},
    {"key": "taiga", "name": "Taiga", "climates": ["cold"], "difficulty": 3,
     "travelNote": "Cold conifer forest.", "features": ["Snowy pines", "Frozen bog", "Logging cut"]},
    {"key": "wastes", "name": "Wastes", "climates": ["temperate", "hot"], "difficulty": 3,
     "travelNote": "Broken, barren badlands.", "features": ["Cracked earth", "Ash flat", "Twisted rock"]},
    {"key": "water", "name": "Open water", "climates": ["cold", "temperate", "hot"], "difficulty": 2,
     "travelNote": "Crossed by boat only.", "features": ["Open swell", "Hidden reef", "Floating debris"]},
]

# climate -> weighted starting-terrain table.
CLIMATE_TO_TERRAIN = {
    "cold": [("plains", 3), ("taiga", 3), ("hills", 2), ("arctic", 2), ("mountains", 2), ("coast", 1)],
    "temperate": [("forest", 3), ("plains", 3), ("hills", 2), ("marsh", 2), ("mountains", 1), ("coast", 1), ("wastes", 1)],
    "hot": [("plains", 3), ("desert", 3), ("jungle", 2), ("hills", 2), ("wastes", 1), ("coast", 1)],
}

# terrain -> weighted neighbouring-terrain table (drives H2 map growth).
NEIGHBOURING = {
    "arctic": [("arctic", 3), ("taiga", 2), ("mountains", 2), ("coast", 1)],
    "coast": [("coast", 2), ("plains", 2), ("hills", 1), ("marsh", 1), ("water", 2)],
    "desert": [("desert", 3), ("wastes", 2), ("hills", 1), ("plains", 1)],
    "forest": [("forest", 3), ("hills", 2), ("plains", 2), ("marsh", 1), ("mountains", 1)],
    "hills": [("hills", 3), ("plains", 2), ("mountains", 2), ("forest", 1)],
    "jungle": [("jungle", 3), ("marsh", 2), ("hills", 1), ("plains", 1)],
    "marsh": [("marsh", 2), ("plains", 2), ("forest", 1), ("coast", 1)],
    "mountains": [("mountains", 3), ("hills", 2), ("arctic", 1), ("forest", 1)],
    "plains": [("plains", 3), ("hills", 2), ("forest", 2), ("coast", 1), ("wastes", 1)],
    "taiga": [("taiga", 3), ("arctic", 2), ("mountains", 1), ("plains", 1)],
    "wastes": [("wastes", 3), ("desert", 2), ("hills", 1), ("plains", 1)],
    "water": [("water", 3), ("coast", 3)],
}

WEATHER = ["Clear skies", "Overcast", "Light rain", "Heavy rain / storm",
           "Fog / mist", "Snow / sleet", "Searing heat", "High winds"]
HAZARDS = ["Rockfall / slide", "Flash flood", "Mire / quicksand", "Exposure / extreme cold or heat",
           "Lost the trail", "Path blocked", "Unstable ground", "Sudden drop / crevasse"]
SITE_TYPES = ["Cave or grotto", "Ruined structure", "Watchtower", "Shrine or altar",
              "Spring or well", "Abandoned camp", "Standing stones", "Small settlement",
              "Old battlefield", "Strange landmark"]
REGION_FEATURES = ["A river crossing", "A commanding vantage point", "Dense, snagging thicket",
                   "A sheltered clearing", "Fresh animal tracks", "A weathered boundary marker",
                   "Signs of recent passage", "An unsettling stillness"]
ENCOUNTER_CATEGORIES = ["Nothing of note", "Predator or beast", "Sapient threat",
                        "Environmental hazard", "Traveller or NPC", "A useful find", "A lair or site"]


def build():
    return {
        "license": "CC0 / authored generic content",
        "climates": CLIMATES,
        "terrains": TERRAINS,
        "climateToTerrain": {c: [{"terrain": t, "weight": w} for (t, w) in rows]
                             for c, rows in CLIMATE_TO_TERRAIN.items()},
        "neighbouringTerrain": {k: [{"terrain": t, "weight": w} for (t, w) in rows]
                                for k, rows in NEIGHBOURING.items()},
        "weather": WEATHER,
        "hazards": HAZARDS,
        "siteTypes": SITE_TYPES,
        "regionFeatures": REGION_FEATURES,
        "encounterCategories": ENCOUNTER_CATEGORIES,
    }


def verify(data):
    keys = {t["key"] for t in data["terrains"]}
    assert len(keys) == len(data["terrains"]), "duplicate terrain key"
    for t in data["terrains"]:
        assert t["difficulty"] in (2, 3, 4), f"bad difficulty {t['key']}"
        for c in t["climates"]:
            assert c in data["climates"], f"bad climate {c}"
        assert t["features"], f"terrain {t['key']} has no features"
    for c, rows in data["climateToTerrain"].items():
        assert c in data["climates"], f"bad climate key {c}"
        for r in rows:
            assert r["terrain"] in keys, f"climateToTerrain {c} -> unknown {r['terrain']}"
            assert r["weight"] >= 1, "weight must be >= 1"
    for k, rows in data["neighbouringTerrain"].items():
        assert k in keys, f"neighbouringTerrain unknown source {k}"
        for r in rows:
            assert r["terrain"] in keys, f"neighbour of {k} -> unknown {r['terrain']}"
            assert r["weight"] >= 1, "weight must be >= 1"
    # Every terrain has a neighbouring table.
    assert keys <= set(data["neighbouringTerrain"]), "a terrain lacks a neighbouring table"
    for name in ["weather", "hazards", "siteTypes", "regionFeatures", "encounterCategories"]:
        assert data[name], f"{name} is empty"
        assert len(data[name]) == len(set(data[name])), f"{name} has duplicates"


if __name__ == "__main__":
    data = build()
    verify(data)
    with open("hexcrawl_data.json", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"wrote hexcrawl_data.json: {len(data['terrains'])} terrains, "
          f"{len(data['siteTypes'])} site types, {len(data['weather'])} weather")
```

- [ ] **Step 2: Run it, copy to assets, register**

Run: `python3 build_hexcrawl.py && cp hexcrawl_data.json assets/hexcrawl_data.json`
Expected: prints `wrote hexcrawl_data.json: 12 terrains, 10 site types, 8 weather`; no assertion error.

Add to `.gitignore` after the `/verdant_data.json` line:
```
/hexcrawl_data.json
```
Add to `pubspec.yaml` `assets:` after `- assets/lonelog_data.json`:
```yaml
    - assets/hexcrawl_data.json
```

- [ ] **Step 3: Commit**

```bash
git add build_hexcrawl.py assets/hexcrawl_data.json pubspec.yaml .gitignore
git commit -m "feat(hexcrawl): authored generic content asset (build_hexcrawl.py)"
```

---

### Task 2: `HexcrawlData` model + loader + provider

**Files:** Create `lib/engine/hexcrawl_data.dart`, `test/hexcrawl_data_test.dart`; Modify `lib/state/providers.dart`.

- [ ] **Step 1: Write the failing test** — `test/hexcrawl_data_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';

void main() {
  final data = HexcrawlData(
      jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
          as Map<String, dynamic>);

  test('loads terrains, climate map, neighbour map, and flat tables', () {
    expect(data.climates, containsAll(['cold', 'temperate', 'hot']));
    expect(data.terrains.length, greaterThanOrEqualTo(10));
    expect(data.terrainByKey('plains')?.name, 'Plains');
    expect(data.climateToTerrain['hot'], isNotEmpty);
    expect(data.neighbouringTerrain['forest'], isNotEmpty);
    expect(data.weather, isNotEmpty);
    expect(data.siteTypes, isNotEmpty);
    expect(data.encounterCategories, contains('Nothing of note'));
  });

  test('every weighted row references a defined terrain', () {
    final keys = data.terrains.map((t) => t.key).toSet();
    for (final rows in data.climateToTerrain.values) {
      for (final r in rows) {
        expect(keys, contains(r.terrain));
      }
    }
    for (final rows in data.neighbouringTerrain.values) {
      for (final r in rows) {
        expect(keys, contains(r.terrain));
      }
    }
  });
}
```

- [ ] **Step 2: Run it** — Run: `flutter test test/hexcrawl_data_test.dart` → FAIL (URI doesn't exist).

- [ ] **Step 3: Write `lib/engine/hexcrawl_data.dart`**

```dart
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class HexTerrain {
  const HexTerrain(
      {required this.key,
      required this.name,
      required this.climates,
      required this.difficulty,
      required this.travelNote,
      required this.features});
  final String key;
  final String name;
  final List<String> climates;
  final int difficulty;
  final String travelNote;
  final List<String> features;

  static HexTerrain fromJson(Map<String, dynamic> j) => HexTerrain(
        key: j['key'] as String,
        name: j['name'] as String,
        climates: (j['climates'] as List).cast<String>(),
        difficulty: j['difficulty'] as int,
        travelNote: (j['travelNote'] as String?) ?? '',
        features: (j['features'] as List).cast<String>(),
      );
}

/// A weighted terrain row in a climate/neighbouring table.
class WeightedTerrain {
  const WeightedTerrain(this.terrain, this.weight);
  final String terrain;
  final int weight;

  static WeightedTerrain fromJson(Map<String, dynamic> j) =>
      WeightedTerrain(j['terrain'] as String, j['weight'] as int);
}

/// Typed wrapper over assets/hexcrawl_data.json (mirrors VerdantData).
class HexcrawlData {
  HexcrawlData(this._json);
  final Map<String, dynamic> _json;

  static Future<HexcrawlData> load() async {
    final raw = await rootBundle.loadString('assets/hexcrawl_data.json');
    return HexcrawlData(jsonDecode(raw) as Map<String, dynamic>);
  }

  List<String> get climates => (_json['climates'] as List).cast<String>();

  List<HexTerrain> get terrains => (_json['terrains'] as List)
      .map((e) => HexTerrain.fromJson(e as Map<String, dynamic>))
      .toList();

  HexTerrain? terrainByKey(String key) {
    for (final t in terrains) {
      if (t.key == key) return t;
    }
    return null;
  }

  Map<String, List<WeightedTerrain>> _weightedMap(String field) =>
      (_json[field] as Map).map((k, v) => MapEntry(
            k as String,
            (v as List)
                .map((e) => WeightedTerrain.fromJson(e as Map<String, dynamic>))
                .toList(),
          ));

  Map<String, List<WeightedTerrain>> get climateToTerrain =>
      _weightedMap('climateToTerrain');
  Map<String, List<WeightedTerrain>> get neighbouringTerrain =>
      _weightedMap('neighbouringTerrain');

  List<String> _flat(String field) => (_json[field] as List).cast<String>();
  List<String> get weather => _flat('weather');
  List<String> get hazards => _flat('hazards');
  List<String> get siteTypes => _flat('siteTypes');
  List<String> get regionFeatures => _flat('regionFeatures');
  List<String> get encounterCategories => _flat('encounterCategories');
}
```

- [ ] **Step 4: Run the test** — Run: `flutter test test/hexcrawl_data_test.dart` → PASS (2 tests).

- [ ] **Step 5: Add the provider** — in `lib/state/providers.dart`, add the import beside the other engine imports:
```dart
import '../engine/hexcrawl_data.dart';
```
and the provider after `lonelogDataProvider`:
```dart

final hexcrawlDataProvider =
    FutureProvider<HexcrawlData>((ref) => HexcrawlData.load());
```

- [ ] **Step 6: Verify + commit** — Run: `dart analyze lib/engine/hexcrawl_data.dart lib/state/providers.dart` → No issues.
```bash
git add lib/engine/hexcrawl_data.dart test/hexcrawl_data_test.dart lib/state/providers.dart
git commit -m "feat(hexcrawl): HexcrawlData model + loader + provider"
```

---

### Task 3: Pure pick engine — `hexcrawl.dart`

**Files:** Create `lib/engine/hexcrawl.dart`, `test/hexcrawl_test.dart`.

- [ ] **Step 1: Write the failing test** — `test/hexcrawl_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/hexcrawl.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';

HexcrawlData _data() => HexcrawlData(
    jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  final data = _data();

  test('weightedPick respects weights and only returns table values', () {
    const table = [WeightedTerrain('a', 3), WeightedTerrain('b', 1)];
    // Deterministic across many seeds: every pick is a/b, and 'a' (weight 3)
    // wins clearly more than half.
    final picks = [
      for (var i = 0; i < 400; i++) weightedPick(table, Dice(Random(i)))
    ];
    expect(picks.every((p) => p == 'a' || p == 'b'), isTrue);
    expect(picks.where((p) => p == 'a').length, greaterThan(picks.length ~/ 2));
  });

  test('rollTerrain returns a terrain valid for the climate', () {
    for (final climate in data.climates) {
      final t = rollTerrain(data, climate, Dice(Random(7)));
      expect(t, isNotNull);
      expect(data.terrainByKey(t!.key), isNotNull);
    }
  });

  test('rollNeighbour returns a defined terrain', () {
    final t = rollNeighbour(data, 'forest', Dice(Random(3)));
    expect(t, isNotNull);
    expect(data.terrains.map((x) => x.key), contains(t!.key));
  });

  test('flat-table rolls return an option from the table', () {
    expect(data.weather, contains(rollFrom(data.weather, Dice(Random(2)))));
    expect(data.encounterCategories,
        contains(rollFrom(data.encounterCategories, Dice(Random(9)))));
  });
}
```

- [ ] **Step 2: Run it** — Run: `flutter test test/hexcrawl_test.dart` → FAIL (URI doesn't exist).

- [ ] **Step 3: Write `lib/engine/hexcrawl.dart`**

```dart
/// Pure pick helpers for the generic hexcrawl toolkit. No Flutter. Weighted and
/// uniform table rolls against a [Dice]; the content lives in [HexcrawlData].
library;

import 'dice.dart';
import 'hexcrawl_data.dart';

/// Weighted pick: probability proportional to weight. Returns the terrain key.
String weightedPick(List<WeightedTerrain> table, Dice dice) {
  final total = table.fold<int>(0, (a, e) => a + e.weight);
  var roll = dice.dN(total); // 1..total
  for (final e in table) {
    roll -= e.weight;
    if (roll <= 0) return e.terrain;
  }
  return table.last.terrain;
}

/// Uniform pick from a flat list of strings.
String rollFrom(List<String> options, Dice dice) =>
    options[dice.dN(options.length) - 1];

/// A starting terrain for [climate].
HexTerrain? rollTerrain(HexcrawlData data, String climate, Dice dice) {
  final table = data.climateToTerrain[climate];
  if (table == null || table.isEmpty) return null;
  return data.terrainByKey(weightedPick(table, dice));
}

/// The terrain of a hex adjacent to one of [terrainKey].
HexTerrain? rollNeighbour(HexcrawlData data, String terrainKey, Dice dice) {
  final table = data.neighbouringTerrain[terrainKey];
  if (table == null || table.isEmpty) return null;
  return data.terrainByKey(weightedPick(table, dice));
}
```

- [ ] **Step 4: Run the test** — Run: `flutter test test/hexcrawl_test.dart` → PASS (4 tests).

- [ ] **Step 5: Commit**
```bash
git add lib/engine/hexcrawl.dart test/hexcrawl_test.dart
git commit -m "feat(hexcrawl): pure weighted/uniform pick engine"
```

---

### Task 4: Gating — `hexcrawl` flag + registry + route

**Files:** Modify `lib/shared/tool_registry.dart`, `lib/shared/destination.dart`, `test/tool_registry_test.dart`.

- [ ] **Step 1: Write the failing test** — append to `test/tool_registry_test.dart` before the final `}`:

```dart
  test('hexcrawl gating: present only when the hexcrawl feature is enabled', () {
    expect(
        buildToolRegistry(family: [], systems: {'juice'})
            .any((t) => t.id == 'hexcrawl'),
        isFalse);
    final tool = buildToolRegistry(family: [], systems: {'juice', 'hexcrawl'})
        .singleWhere((t) => t.id == 'hexcrawl');
    expect(tool.group, 'Exploration');
    expect(tool.label, 'Hexcrawl');
  });
```

Also add `'hexcrawl'` to the `validSystems` set in the `toolSystem covers every possible tool id` test (next to `'lonelog'`).

- [ ] **Step 2: Run it** — Run: `flutter test test/tool_registry_test.dart` → FAIL (`Bad state: No element`).

- [ ] **Step 3: Add the ToolDef + toolSystem entry** — in `lib/shared/tool_registry.dart`, add to `toolSystem` (after `'verdant': 'verdant',`):
```dart
  'hexcrawl': 'hexcrawl',
```
and add this ToolDef in `buildToolRegistry` immediately after the `verdant` ToolDef:
```dart
    const ToolDef(
      id: 'hexcrawl',
      label: 'Hexcrawl',
      icon: Icons.travel_explore_outlined,
      group: 'Exploration',
      badge: 'Hexcrawl',
    ),
```

- [ ] **Step 4: Add the route** — in `lib/shared/destination.dart` `toolLocation`, after `'verdant': (Destination.maps, 'journey'),`:
```dart
  'hexcrawl': (Destination.maps, 'hexcrawl'),
```

- [ ] **Step 5: Run the test** — Run: `flutter test test/tool_registry_test.dart` → PASS.

- [ ] **Step 6: Commit**
```bash
git add lib/shared/tool_registry.dart lib/shared/destination.dart test/tool_registry_test.dart
git commit -m "feat(hexcrawl): register gated hexcrawl tool"
```

---

### Task 5: `HexcrawlScreen` generator + Maps subtab

**Files:** Create `lib/features/hexcrawl_screen.dart`, `test/hexcrawl_screen_test.dart`; Modify `lib/features/maps_tab.dart`.

- [ ] **Step 1: Write the failing test** — `test/hexcrawl_screen_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/features/hexcrawl_screen.dart';
import 'package:juice_oracle/state/providers.dart';

HexcrawlData _data() => HexcrawlData(
    jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('rolls a weather result and shows it', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [hexcrawlDataProvider.overrideWith((ref) async => _data())],
      child: const MaterialApp(home: Scaffold(body: HexcrawlScreen())),
    ));
    await t.pumpAndSettle();

    expect(find.text('Weather'), findsWidgets);
    await t.tap(find.byKey(const Key('roll-weather')));
    await t.pumpAndSettle();
    // A weather result label appears in the result area.
    expect(find.byKey(const Key('hexcrawl-result')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it** — Run: `flutter test test/hexcrawl_screen_test.dart` → FAIL (URI doesn't exist).

- [ ] **Step 3: Write `lib/features/hexcrawl_screen.dart`**

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/hexcrawl.dart';
import '../engine/hexcrawl_data.dart';
import '../state/providers.dart';

/// Generic exploration-table generator (Hexcrawl toolkit H1): roll any
/// system-agnostic table and log the result to the journal. Plain scroll +
/// Wrap of buttons — no TabBarView / non-flex buttons (loose-constraint safe).
class HexcrawlScreen extends ConsumerStatefulWidget {
  const HexcrawlScreen({super.key});

  @override
  ConsumerState<HexcrawlScreen> createState() => _HexcrawlScreenState();
}

class _HexcrawlScreenState extends ConsumerState<HexcrawlScreen> {
  final _dice = Dice(Random());
  String _climate = 'temperate';
  String _resultTitle = '';
  String _resultBody = '';

  void _set(String title, String body) =>
      setState(() {
        _resultTitle = title;
        _resultBody = body;
      });

  void _logToJournal() {
    if (_resultBody.isEmpty) return;
    ref.read(journalProvider.notifier).add(_resultTitle, _resultBody);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logged to journal')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(hexcrawlDataProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load hexcrawl data: $e')),
      data: (data) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Climate', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 6,
            children: [
              for (final c in data.climates)
                ChoiceChip(
                  label: Text(c),
                  selected: _climate == c,
                  onSelected: (_) => setState(() => _climate = c),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Roll a table', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                key: const Key('roll-terrain'),
                onPressed: () {
                  final t = rollTerrain(data, _climate, _dice);
                  if (t != null) {
                    _set('Terrain', '${t.name} — ${t.travelNote}');
                  }
                },
                child: const Text('Terrain'),
              ),
              FilledButton.tonal(
                key: const Key('roll-weather'),
                onPressed: () =>
                    _set('Weather', rollFrom(data.weather, _dice)),
                child: const Text('Weather'),
              ),
              FilledButton.tonal(
                key: const Key('roll-hazard'),
                onPressed: () =>
                    _set('Hazard', rollFrom(data.hazards, _dice)),
                child: const Text('Hazard'),
              ),
              FilledButton.tonal(
                key: const Key('roll-site'),
                onPressed: () =>
                    _set('Site', rollFrom(data.siteTypes, _dice)),
                child: const Text('Site'),
              ),
              FilledButton.tonal(
                key: const Key('roll-feature'),
                onPressed: () =>
                    _set('Feature', rollFrom(data.regionFeatures, _dice)),
                child: const Text('Feature'),
              ),
              FilledButton.tonal(
                key: const Key('roll-encounter'),
                onPressed: () => _set(
                    'Encounter', rollFrom(data.encounterCategories, _dice)),
                child: const Text('Encounter'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_resultBody.isNotEmpty)
            Card(
              key: const Key('hexcrawl-result'),
              child: ListTile(
                title: Text(_resultTitle),
                subtitle: Text(_resultBody),
                trailing: IconButton(
                  icon: const Icon(Icons.post_add_outlined),
                  tooltip: 'Log to journal',
                  onPressed: _logToJournal,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test** — Run: `flutter test test/hexcrawl_screen_test.dart` → PASS.

- [ ] **Step 5: Add the gated Maps subtab** — in `lib/features/maps_tab.dart`, add the import:
```dart
import 'hexcrawl_screen.dart';
```
change the build to include a gated subtab:
```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showJourney = systems.contains('verdant');
    final showHexcrawl = systems.contains('hexcrawl');
    return SubtabHost(
      destination: Destination.maps,
      tabs: [
        const SubtabDef('world', 'World'),
        const SubtabDef('dungeon', 'Dungeon'),
        if (showJourney) const SubtabDef('journey', 'Journey'),
        if (showHexcrawl) const SubtabDef('hexcrawl', 'Hexcrawl'),
      ],
      children: [
        HexMapPane(oracle: oracle),
        DungeonMapPane(oracle: oracle),
        if (showJourney) VerdantScreen(oracle: oracle),
        if (showHexcrawl) const HexcrawlScreen(),
      ],
    );
  }
```

- [ ] **Step 6: Verify + commit** — Run: `dart analyze lib/features/hexcrawl_screen.dart lib/features/maps_tab.dart` → No issues.
```bash
git add lib/features/hexcrawl_screen.dart test/hexcrawl_screen_test.dart lib/features/maps_tab.dart
git commit -m "feat(hexcrawl): exploration-table generator screen + gated Maps subtab"
```

---

### Task 6: Campaign toggles — New-Campaign + Edit-systems

**Files:** Modify `lib/shared/home_shell.dart`, `test/lonelog_campaign_ui_test.dart`.

- [ ] **Step 1: Write the failing test** — append a `testWidgets` to `test/lonelog_campaign_ui_test.dart` (after the existing ones, before the final `}`):

```dart
  testWidgets('New Campaign dialog offers a Hexcrawl toggle (default off)',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        verdantDataProvider.overrideWith((ref) async => _verdant),
        emulatorDataProvider.overrideWith((ref) async => _emu),
        lonelogDataProvider.overrideWith((ref) async => _lonelog),
      ],
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Campaigns'));
    await t.pumpAndSettle();
    await t.tap(find.text('New campaign'));
    await t.pumpAndSettle();

    final hex = find.byKey(const Key('sys-hexcrawl'));
    expect(hex, findsOneWidget);
    expect(t.widget<CheckboxListTile>(hex).value, isFalse);
  });
```

- [ ] **Step 2: Run it** — Run: `flutter test test/lonelog_campaign_ui_test.dart` → FAIL (no `sys-hexcrawl`).

- [ ] **Step 3: Add to `_NewCampaignDialogState`** — in `lib/shared/home_shell.dart`, add the field after `bool _lonelog = false;`:
```dart
  bool _hexcrawl = false;
```
add to the `picked` set in `_submit` after `if (_lonelog) 'lonelog',`:
```dart
      if (_hexcrawl) 'hexcrawl',
```
add this `CheckboxListTile` after the `sys-lonelog` one:
```dart
          CheckboxListTile(
            key: const Key('sys-hexcrawl'),
            title: const Text('Hexcrawl toolkit'),
            value: _hexcrawl,
            onChanged: (v) => setState(() => _hexcrawl = v ?? false),
          ),
```

- [ ] **Step 4: Add to `_EditSystemsDialog`** — in the `_EditSystemsDialogState.build` `content` Column children, after `_row('lonelog', 'Lonelog journaling'),`:
```dart
          _row('hexcrawl', 'Hexcrawl toolkit'),
```

- [ ] **Step 5: Run the test + commit** — Run: `flutter test test/lonelog_campaign_ui_test.dart` → PASS. Run: `dart analyze lib/shared/home_shell.dart` → No issues.
```bash
git add lib/shared/home_shell.dart test/lonelog_campaign_ui_test.dart
git commit -m "feat(hexcrawl): enable Hexcrawl at campaign creation + edit-systems"
```

---

### Task 7: Full verification + docs

- [ ] **Step 1: Document the rail** — in `CLAUDE.md` under "## Project notes", add a bullet after the Lonelog one:
```markdown
- The generic Hexcrawl toolkit asset (`assets/hexcrawl_data.json`: authored,
  system-agnostic terrains/climate/neighbour weights + weather/hazards/site-types/
  features/encounter-categories) is generated by `build_hexcrawl.py`. Same rail as
  `build_verdant.py`: authored literals are the source of truth, the script
  self-verifies structure (unique terrain keys, weighted rows reference defined
  terrains, non-empty tables); edit the script, rerun `python3 build_hexcrawl.py`,
  copy `hexcrawl_data.json` into `assets/`; never hand-edit the JSON. Gated by an
  opt-in `hexcrawl` feature flag (NOT in `kAllSystems`). H1 of the generic
  hexcrawl/mapping toolkit (see `docs/superpowers/specs/2026-06-14-generic-hexcrawl-toolkit-design.md`).
```

- [ ] **Step 2: Full suite** — Run: `flutter test` → all pass (the H1 tests + existing).

- [ ] **Step 3: Analyze** — Run: `flutter analyze` → No issues found.

- [ ] **Step 4: Commit**
```bash
git add CLAUDE.md
git commit -m "docs(hexcrawl): document build_hexcrawl.py rail in CLAUDE.md"
```

---

## Self-review

**Spec coverage (H1):** `hexcrawl` flag + gating (Tasks 4, 6); `build_hexcrawl.py` rail + authored content (Task 1); `HexcrawlData` model + provider (Task 2); pure pick engine (Task 3); generator screen + Maps subtab (Task 5); CLAUDE.md rail note (Task 7). The universal/region content (terrains, climate→terrain, neighbouring, weather, hazards, site-types, region-features, encounter-categories) is all in Task 1. Out-of-scope (H2–H4 map gen, dungeon/local/site content) — no task builds them. ✓

**Placeholder scan:** none — every code/test step is complete.

**Type consistency:** `HexcrawlData` getters (`climates`, `terrains`, `terrainByKey`, `climateToTerrain`, `neighbouringTerrain`, `weather`, `hazards`, `siteTypes`, `regionFeatures`, `encounterCategories`), `HexTerrain` (`key/name/climates/difficulty/travelNote/features`), `WeightedTerrain` (`terrain/weight`), engine fns (`weightedPick(List<WeightedTerrain>, Dice)`, `rollFrom(List<String>, Dice)`, `rollTerrain(HexcrawlData, String, Dice)`, `rollNeighbour(...)`), `hexcrawlDataProvider`, tool id `hexcrawl`, flag `hexcrawl`, subtab key `hexcrawl`, asset `assets/hexcrawl_data.json`, screen `HexcrawlScreen` — all consistent across tasks. The Task 3 test's first `weightedPick` block is intentionally a deterministic distribution check (seeded per-iteration).
