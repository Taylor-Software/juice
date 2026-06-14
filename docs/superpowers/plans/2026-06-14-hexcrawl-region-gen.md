# Hexcrawl H2 — Region Map Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate terrain + sites across the shared World hex map, two paths (crawl-reveal one hex; full-generate a connected region), when the `hexcrawl` feature is on.

**Architecture:** A pure `hexcrawl_map.dart` engine (reusing H1's pick engine + the existing `hexNeighbors`) grows a connected region or a single crawl hex; `MapNotifier` writes the results into the existing `HexCell` (terrain reused, new `site` field); the existing `_HexPainter` gains a hexcrawl terrain palette + a site marker; `HexMapPane` shows gated hexcrawl controls.

**Tech Stack:** Dart/Flutter, flutter_riverpod, shared_preferences, package:flutter_test.

**Scope guard (H2):** region terrain + sites on the World map. No dungeon/local/site-detail (H3/H4), no encounter rolling per hex (H1's generator does that on demand).

---

## File structure

**New:** `lib/engine/hexcrawl_map.dart`, `test/hexcrawl_map_test.dart`, `test/hexcrawl_mapnotifier_test.dart`.
**Edit:** `lib/engine/models.dart` (`HexCell.site`), `lib/state/providers.dart` (`crawlHexcrawl`, `generateRegion`), `lib/features/map_screen.dart` (`hexcrawlTerrainHues` + painter + controls), `test/map_state_test.dart` (or models test for the `site` round-trip).

---

### Task 1: `HexCell.site` field

**Files:** Modify `lib/engine/models.dart`; Test `test/hexcrawl_map_test.dart` (model round-trip lives here for cohesion).

- [ ] **Step 1: Write the failing test** — create `test/hexcrawl_map_test.dart` with just the model test for now:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('HexCell.site round-trips and is omitted from JSON when null', () {
    const withSite = HexCell(col: 1, row: 2, envRow: 1, terrain: 'forest', site: 'Cave or grotto');
    final back = HexCell.maybeFromJson(withSite.toJson())!;
    expect(back.site, 'Cave or grotto');
    expect(back.terrain, 'forest');
    const bare = HexCell(col: 0, row: 0, envRow: 1);
    expect(bare.toJson().containsKey('site'), isFalse);
    expect(HexCell.maybeFromJson(bare.toJson())!.site, isNull);
  });
}
```

- [ ] **Step 2: Run it** — Run: `flutter test test/hexcrawl_map_test.dart` → FAIL (`site` not a parameter).

- [ ] **Step 3: Add `site` to `HexCell`** — in `lib/engine/models.dart`, in `class HexCell`:

Add to the constructor (after `this.pois = const [],`):
```dart
    this.site,
```
Add the field (after `final List<int> pois;`):
```dart
  final String? site; // hexcrawl site-type on this hex; null = none
```
Update `copyWith` — add `String? site, bool clearSite = false,` to its params and `site: clearSite ? null : (site ?? this.site),` to the returned `HexCell`.
Update `toJson` — add after the `pois` line:
```dart
        if (site != null) 'site': site,
```
Update `maybeFromJson` — add to the returned `HexCell`:
```dart
      site: j['site'] as String?,
```

- [ ] **Step 4: Run it** — Run: `flutter test test/hexcrawl_map_test.dart` → PASS.

- [ ] **Step 5: Commit**
```bash
git add lib/engine/models.dart test/hexcrawl_map_test.dart
git commit -m "feat(hexcrawl): HexCell.site field (H2)"
```

---

### Task 2: Region/crawl generation engine

**Files:** Create `lib/engine/hexcrawl_map.dart`; extend `test/hexcrawl_map_test.dart`.

- [ ] **Step 1: Write the failing test** — append to `test/hexcrawl_map_test.dart` (add imports at top: `dart:convert`, `dart:io`, `dart:math`, `package:juice_oracle/engine/dice.dart`, `package:juice_oracle/engine/hexcrawl_data.dart`, `package:juice_oracle/engine/hexcrawl_map.dart`, `package:juice_oracle/engine/map_builder.dart`):

```dart
  final data = HexcrawlData(
      jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
          as Map<String, dynamic>);
  final terrainKeys = data.terrains.map((t) => t.key).toSet();

  test('growRegion yields N connected hexes with defined terrain', () {
    final region = growRegion(
        data: data, climate: 'temperate', count: 12, dice: Dice(Random(5)));
    expect(region.length, 12);
    final coords = {for (final g in region) (g.col, g.row)};
    expect(coords.length, 12); // no duplicate cells
    for (final g in region) {
      expect(terrainKeys, contains(g.terrain));
      if (g.site != null) expect(data.siteTypes, contains(g.site));
    }
    // Connected: every non-origin hex has a neighbour in the region.
    for (final g in region) {
      if (g.col == 0 && g.row == 0) continue;
      final hasNeighbour = hexNeighbors(g.col, g.row)
          .any((n) => coords.contains((n.col, n.row)));
      expect(hasNeighbour, isTrue, reason: 'hex ${g.col},${g.row} is isolated');
    }
  });

  test('growRegion is deterministic per seed and handles count<=0', () {
    final a = growRegion(data: data, climate: 'hot', count: 8, dice: Dice(Random(1)));
    final b = growRegion(data: data, climate: 'hot', count: 8, dice: Dice(Random(1)));
    expect(a.map((g) => '${g.col},${g.row},${g.terrain}'),
        b.map((g) => '${g.col},${g.row},${g.terrain}'));
    expect(growRegion(data: data, climate: 'hot', count: 0, dice: Dice(Random(1))),
        isEmpty);
  });

  test('rollCrawlHex returns a defined neighbour terrain', () {
    final r = rollCrawlHex(data, 'forest', Dice(Random(3)));
    expect(terrainKeys, contains(r.terrain));
    if (r.site != null) expect(data.siteTypes, contains(r.site));
  });
```

- [ ] **Step 2: Run it** — Run: `flutter test test/hexcrawl_map_test.dart` → FAIL (URI doesn't exist).

- [ ] **Step 3: Write `lib/engine/hexcrawl_map.dart`**

```dart
/// Region + crawl terrain/site generation for the Hexcrawl toolkit (H2). Pure,
/// no Flutter. Reuses H1's pick engine and the existing odd-q [hexNeighbors].
library;

import 'dice.dart';
import 'hexcrawl.dart';
import 'hexcrawl_data.dart';
import 'map_builder.dart' show hexNeighbors;

/// One generated hex, relative to the region origin (0,0).
class GenHex {
  const GenHex(
      {required this.col, required this.row, required this.terrain, this.site});
  final int col;
  final int row;
  final String terrain;
  final String? site;
}

/// A site on ~1/3 of hexes (d6 <= 2), drawn from the generic site types.
String? _rollSite(HexcrawlData data, Dice dice) =>
    dice.dN(6) <= 2 ? rollFrom(data.siteTypes, dice) : null;

/// A single crawl hex: terrain rolled from [fromTerrain] via neighbouring
/// terrain, plus an optional site.
({String terrain, String? site}) rollCrawlHex(
    HexcrawlData data, String fromTerrain, Dice dice) {
  final t = rollNeighbour(data, fromTerrain, dice);
  return (terrain: t?.key ?? fromTerrain, site: _rollSite(data, dice));
}

/// Grow a connected region of [count] hexes from a climate-seeded start at
/// (0,0). Each new hex is an empty neighbour of a placed hex; its terrain is
/// rolled from an adjacent placed hex. Deterministic for a given [dice].
List<GenHex> growRegion(
    {required HexcrawlData data,
    required String climate,
    required int count,
    required Dice dice}) {
  if (count <= 0) return const [];
  final start = rollTerrain(data, climate, dice);
  final startKey = start?.key ?? data.terrains.first.key;
  final placed = <(int, int), GenHex>{
    (0, 0): GenHex(col: 0, row: 0, terrain: startKey, site: _rollSite(data, dice)),
  };
  while (placed.length < count) {
    final candidates = <(int, int)>{};
    for (final h in placed.values) {
      for (final n in hexNeighbors(h.col, h.row)) {
        if (!placed.containsKey((n.col, n.row))) candidates.add((n.col, n.row));
      }
    }
    if (candidates.isEmpty) break;
    final list = candidates.toList();
    final pick = list[dice.dN(list.length) - 1];
    final adj = hexNeighbors(pick.$1, pick.$2)
        .where((n) => placed.containsKey((n.col, n.row)))
        .toList();
    final from = adj[dice.dN(adj.length) - 1];
    final fromTerrain = placed[(from.col, from.row)]!.terrain;
    final t = rollNeighbour(data, fromTerrain, dice);
    placed[(pick.$1, pick.$2)] = GenHex(
        col: pick.$1,
        row: pick.$2,
        terrain: t?.key ?? fromTerrain,
        site: _rollSite(data, dice));
  }
  return placed.values.toList();
}
```

- [ ] **Step 4: Run it** — Run: `flutter test test/hexcrawl_map_test.dart` → PASS (4 tests).

- [ ] **Step 5: Commit**
```bash
git add lib/engine/hexcrawl_map.dart test/hexcrawl_map_test.dart
git commit -m "feat(hexcrawl): region + crawl generation engine (H2)"
```

---

### Task 3: `MapNotifier.crawlHexcrawl` + `generateRegion`

**Files:** Modify `lib/state/providers.dart`; Create `test/hexcrawl_mapnotifier_test.dart`.

- [ ] **Step 1: Write the failing test** — `test/hexcrawl_mapnotifier_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/state/providers.dart';

HexcrawlData _data() => HexcrawlData(
    jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('crawlHexcrawl adds a hex with terrain and advances current', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    final n = c.read(mapProvider.notifier);
    await c.read(mapProvider.future);

    await n.crawlHexcrawl(_data(), 'temperate', Dice(Random(2)));
    var s = await c.read(mapProvider.future);
    expect(s.hexes.length, 1);
    expect(s.hexes.single.terrain, isNotNull);

    await n.crawlHexcrawl(_data(), 'temperate', Dice(Random(4)));
    s = await c.read(mapProvider.future);
    expect(s.hexes.length, 2);
    expect(s.currentHexCol, isNotNull);
  });

  test('generateRegion populates N connected hexes with terrain', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    final n = c.read(mapProvider.notifier);
    await c.read(mapProvider.future);

    await n.generateRegion(_data(), 'hot', 10, Dice(Random(7)));
    final s = await c.read(mapProvider.future);
    expect(s.hexes.length, 10);
    expect(s.hexes.every((h) => h.terrain != null), isTrue);
  });
}
```

- [ ] **Step 2: Run it** — Run: `flutter test test/hexcrawl_mapnotifier_test.dart` → FAIL (`crawlHexcrawl` not defined).

- [ ] **Step 3: Add the methods to `MapNotifier`** — in `lib/state/providers.dart`, add the import beside the engine imports:
```dart
import '../engine/hexcrawl_map.dart';
```
and add these methods inside `class MapNotifier` (after `revealHexAt`):

```dart
  /// Hexcrawl crawl-reveal: the next hex's terrain is rolled from the current
  /// hex's terrain (or a climate seed), plus an optional site. Advances current.
  Future<void> crawlHexcrawl(
      HexcrawlData data, String climate, Dice dice) async {
    final s = await _ready;
    final pos = nextHexPosition(s.hexes, s.currentHexCol, s.currentHexRow, dice);
    if (pos.alreadyRevealed) {
      await save(s.copyWith(currentHexCol: pos.col, currentHexRow: pos.row));
      return;
    }
    HexCell? cur;
    for (final h in s.hexes) {
      if (h.col == s.currentHexCol && h.row == s.currentHexRow) cur = h;
    }
    final fromTerrain = cur?.terrain ??
        rollTerrain(data, climate, dice)?.key ??
        data.terrains.first.key;
    final rolled = rollCrawlHex(data, fromTerrain, dice);
    final cell = HexCell(
        col: pos.col,
        row: pos.row,
        envRow: 1,
        terrain: rolled.terrain,
        site: rolled.site);
    await save(s.copyWith(
        hexes: [...s.hexes, cell],
        currentHexCol: pos.col,
        currentHexRow: pos.row));
  }

  /// Hexcrawl full-region: place [count] connected hexes (terrain + sites),
  /// anchored at the current hex (or origin); existing hexes are not overwritten.
  Future<void> generateRegion(
      HexcrawlData data, String climate, int count, Dice dice) async {
    final s = await _ready;
    final region =
        growRegion(data: data, climate: climate, count: count, dice: dice);
    final ax = s.currentHexCol ?? 0;
    final ay = s.currentHexRow ?? 0;
    final existing = {for (final h in s.hexes) (h.col, h.row)};
    final added = <HexCell>[];
    for (final g in region) {
      final col = ax + g.col;
      final row = ay + g.row;
      if (existing.contains((col, row))) continue;
      added.add(HexCell(
          col: col, row: row, envRow: 1, terrain: g.terrain, site: g.site));
    }
    await save(s.copyWith(
        hexes: [...s.hexes, ...added], currentHexCol: ax, currentHexRow: ay));
  }
```

(`rollTerrain` comes from `hexcrawl.dart` — add `import '../engine/hexcrawl.dart';` if not already imported via `hexcrawl_map.dart`'s re-export; it is NOT re-exported, so add the import explicitly.)

- [ ] **Step 4: Run it** — Run: `flutter test test/hexcrawl_mapnotifier_test.dart` → PASS.

- [ ] **Step 5: Verify + commit** — Run: `dart analyze lib/state/providers.dart` → No issues.
```bash
git add lib/state/providers.dart test/hexcrawl_mapnotifier_test.dart
git commit -m "feat(hexcrawl): MapNotifier crawlHexcrawl + generateRegion (H2)"
```

---

### Task 4: Painter — hexcrawl palette + site marker

**Files:** Modify `lib/features/map_screen.dart`; Create `test/hexcrawl_palette_test.dart`.

- [ ] **Step 1: Write the failing test** — `test/hexcrawl_palette_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/features/map_screen.dart';

void main() {
  test('every hexcrawl terrain key has a hue', () {
    final data = HexcrawlData(
        jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
            as Map<String, dynamic>);
    for (final t in data.terrains) {
      expect(hexcrawlTerrainHues.containsKey(t.key), isTrue,
          reason: 'no hue for terrain ${t.key}');
    }
  });
}
```

- [ ] **Step 2: Run it** — Run: `flutter test test/hexcrawl_palette_test.dart` → FAIL (`hexcrawlTerrainHues` undefined).

- [ ] **Step 3: Add the palette + painter changes** — in `lib/features/map_screen.dart`, add this public const right after the `_verdantTerrainHues` map:

```dart
/// Fixed hues for the 12 generic hexcrawl terrain keys (used when a hex carries
/// a hexcrawl-generated terrain instead of a Juice envRow / Verdant terrain).
const Map<String, Color> hexcrawlTerrainHues = {
  'arctic': Color(0xFFB3E5FC),
  'coast': Color(0xFF80DEEA),
  'desert': Color(0xFFE0C068),
  'forest': Color(0xFF2E7D32),
  'hills': Color(0xFFA1887F),
  'jungle': Color(0xFF1B5E20),
  'marsh': Color(0xFF26A69A),
  'mountains': Color(0xFF78909C),
  'plains': Color(0xFF9CCC65),
  'taiga': Color(0xFF4DB6AC),
  'wastes': Color(0xFFBCAAA4),
  'water': Color(0xFF1E88E5),
};
```

In `_HexPainter.paint`, change the terrain-color line (the `_verdantTerrainHues[h.terrain] ?? scheme.surfaceContainerHighest`):
```dart
      final baseHue = hasTerrain
          ? (_verdantTerrainHues[h.terrain] ??
              hexcrawlTerrainHues[h.terrain] ??
              scheme.surfaceContainerHighest)
          : _envHues[h.envRow - 1];
```

After the `isCurrent` border block (after its closing `}`, before the label `TextPainter`), add the site marker:
```dart
      if (h.site != null) {
        canvas.drawCircle(c + Offset(0, -_hexSize * 0.45), 3,
            Paint()..color = scheme.primary);
      }
```

- [ ] **Step 4: Run it** — Run: `flutter test test/hexcrawl_palette_test.dart` → PASS. Run: `dart analyze lib/features/map_screen.dart` → No issues.

- [ ] **Step 5: Commit**
```bash
git add lib/features/map_screen.dart test/hexcrawl_palette_test.dart
git commit -m "feat(hexcrawl): map palette for hexcrawl terrains + site markers (H2)"
```

---

### Task 5: Gated hexcrawl controls on the World pane

**Files:** Modify `lib/features/map_screen.dart`; Create `test/hexcrawl_world_controls_test.dart`.

- [ ] **Step 1: Write the failing test** — `test/hexcrawl_world_controls_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/map_screen.dart';
import 'package:juice_oracle/state/providers.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));
HexcrawlData _hex() => HexcrawlData(
    jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
        as Map<String, dynamic>);

Future<void> _pump(WidgetTester t, {required bool hexcrawl}) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"M","systems":'
        '${hexcrawl ? '["juice","hexcrawl"]' : '["juice"]'}}]}',
  });
  await t.pumpWidget(ProviderScope(
    overrides: [hexcrawlDataProvider.overrideWith((ref) async => _hex())],
    child: MaterialApp(home: Scaffold(body: HexMapPane(oracle: _oracle()))),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('hexcrawl controls appear only when the flag is on', (t) async {
    await _pump(t, hexcrawl: true);
    expect(find.byKey(const Key('hexcrawl-generate-region')), findsOneWidget);

    await _pump(t, hexcrawl: false);
    expect(find.byKey(const Key('hexcrawl-generate-region')), findsNothing);
  });
}
```

- [ ] **Step 2: Run it** — Run: `flutter test test/hexcrawl_world_controls_test.dart` → FAIL (key not found).

- [ ] **Step 3: Add the gated controls** — in `lib/features/map_screen.dart`, in the World pane state (`HexMapPaneState`), add fields:
```dart
  String _hcClimate = 'temperate';
  int _hcCount = 10;
```
add helper methods to the state class:
```dart
  bool _hexcrawlOn() => (ref
              .watch(sessionsProvider)
              .valueOrNull
              ?.activeMeta
              .enabledSystems ??
          kAllSystems)
      .contains('hexcrawl');

  Future<void> _hcCrawl() async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref
        .read(mapProvider.notifier)
        .crawlHexcrawl(data, _hcClimate, ref.read(oracleProvider).valueOrNull?.dice ?? Dice());
  }

  Future<void> _hcRegion() async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref.read(mapProvider.notifier).generateRegion(
        data, _hcClimate, _hcCount, ref.read(oracleProvider).valueOrNull?.dice ?? Dice());
  }

  Widget _hexcrawlControls(BuildContext context) {
    final data = ref.watch(hexcrawlDataProvider).valueOrNull;
    if (data == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final c in data.climates)
                ChoiceChip(
                  label: Text(c),
                  selected: _hcClimate == c,
                  onSelected: (_) => setState(() => _hcClimate = c),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonal(
                key: const Key('hexcrawl-reveal'),
                onPressed: _hcCrawl,
                child: const Text('Reveal next (hexcrawl)'),
              ),
              FilledButton.tonal(
                key: const Key('hexcrawl-generate-region'),
                onPressed: _hcRegion,
                child: Text('Generate region ($_hcCount)'),
              ),
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: () =>
                    setState(() => _hcCount = (_hcCount - 5).clamp(5, 60)),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () =>
                    setState(() => _hcCount = (_hcCount + 5).clamp(5, 60)),
              ),
            ],
          ),
        ],
      ),
    );
  }
```
and render it under the existing controls — in the World pane `build`, immediately after the `_controls(context, s)` call in the column children, add:
```dart
            if (_hexcrawlOn()) _hexcrawlControls(context),
```
Ensure the imports `import '../engine/dice.dart';` and (if missing) `import '../engine/hexcrawl_data.dart';` are present in `map_screen.dart`; `oracleProvider`, `sessionsProvider`, `hexcrawlDataProvider`, `kAllSystems`, `mapProvider` come from existing `../state/providers.dart` / `../engine/models.dart` imports.

- [ ] **Step 4: Run it** — Run: `flutter test test/hexcrawl_world_controls_test.dart` → PASS. Run: `dart analyze lib/features/map_screen.dart` → No issues.

- [ ] **Step 5: Commit**
```bash
git add lib/features/map_screen.dart test/hexcrawl_world_controls_test.dart
git commit -m "feat(hexcrawl): gated crawl/region controls on the World map (H2)"
```

---

### Task 6: Full verification

- [ ] **Step 1: Full suite** — Run: `flutter test` → all pass.
- [ ] **Step 2: Analyze** — Run: `flutter analyze` → No issues found.

---

## Self-review

**Spec coverage:** `HexCell.site` (Task 1); `growRegion` + `rollCrawlHex` engine reusing `hexNeighbors` (Task 2); `MapNotifier.crawlHexcrawl` + `generateRegion` (Task 3); painter palette + site marker (Task 4); gated World controls climate+crawl+region (Task 5). Site chance d6≤2, region anchored at current hex, one terrain+site per hex, reuse `HexCell.terrain` — all in Tasks 2-3. Out of scope (H3/H4, per-hex encounters) — no task. ✓

**Placeholder scan:** none.

**Type consistency:** `GenHex{col,row,terrain,site?}`, `growRegion({data,climate,count,dice})→List<GenHex>`, `rollCrawlHex(HexcrawlData,String,Dice)→({terrain,site?})`, `HexCell.site`, `MapNotifier.crawlHexcrawl(HexcrawlData,String,Dice)` / `generateRegion(HexcrawlData,String,int,Dice)`, `hexcrawlTerrainHues`, reused `hexNeighbors` — consistent across tasks and matched against the real `HexCell`/`MapState`/`HexcrawlData`/engine APIs. The notifier `generateRegion` calls the engine `growRegion` (distinct names — no recursion/clash).
