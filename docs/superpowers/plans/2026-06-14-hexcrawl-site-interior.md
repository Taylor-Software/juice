# Hexcrawl H4c — Site Interior ("Enter") Implementation Plan

> **For agentic workers:** execute task-by-task, TDD, commit per task. Steps use `- [ ]`.

**Goal:** The site detail card (H4b) gains an **Enter** button → a small interior **area map** for
the site, inline on the World map. Two paths: **Crawl** (reveal one area at a time) and **Full**
(generate a fresh N-area interior, clamp 3..12). Areas stored on the hex (`HexCell.siteAreas`),
NEVER `MapState.rooms`. Final slice of the Hexcrawl toolkit.

**Architecture:** Authored `siteAreaTypes` → `HexCell.siteAreas` (`List<SiteArea>`) → pure
`rollSiteArea` + `nextSiteAreaPosition` (a small grid-placement parallel to `nextRoomPosition`,
reusing the shared `_roomDirs`) → `MapNotifier.crawlSiteArea`/`generateSiteInterior` → an `interior`
`_HexZoom` mode that renders `siteAreas` through the **existing `_DungeonPainter`** (areas mapped to
synthetic `DungeonRoom`s, no corridors). Gated by `hexcrawl`.

**Tech Stack:** Dart, flutter_riverpod, shared_preferences, build_hexcrawl.py rail.

---

### Task 1: `siteAreaTypes` content

**Files:** Modify `build_hexcrawl.py`; regenerate `assets/hexcrawl_data.json`.

- [ ] **Step 1:** Add after `SITE_FEATURES`:

```python
SITE_AREA_TYPES = ["Entrance", "Antechamber", "Main hall", "Storeroom",
                   "Inner sanctum", "Collapsed section", "Hidden alcove",
                   "Well or shaft", "Living quarters", "Lookout"]
```

- [ ] **Step 2:** `build()` dict: `"siteAreaTypes": SITE_AREA_TYPES,`.
- [ ] **Step 3:** Add `"siteAreaTypes"` to the `verify()` flat-table list.
- [ ] **Step 4:** Regenerate, copy to `assets/`, confirm in-sync.
- [ ] **Step 5:** Commit: `feat(hexcrawl): siteAreaTypes content table (H4c)`.

---

### Task 2: `HexcrawlData.siteAreaTypes` getter

**Files:** Modify `lib/engine/hexcrawl_data.dart`; Test `test/hexcrawl_data_test.dart`.

- [ ] **Step 1:** Add to the first test: `expect(data.siteAreaTypes, contains('Entrance'));`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** After the `siteFeatures` getter add: `List<String> get siteAreaTypes => _flat('siteAreaTypes');`.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit: `feat(hexcrawl): HexcrawlData.siteAreaTypes getter (H4c)`.

---

### Task 3: `SiteArea` model + `HexCell.siteAreas`

**Files:** Modify `lib/engine/models.dart`; Test `test/hexcrawl_interior_test.dart` (new).

- [ ] **Step 1:** Failing round-trip test in `test/hexcrawl_interior_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/hexcrawl.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/engine/map_builder.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

HexcrawlData _data() => HexcrawlData(jsonDecode(
    File('assets/hexcrawl_data.json').readAsStringSync()) as Map<String, dynamic>);

void main() {
  test('HexCell.siteAreas round-trips and omits when empty', () {
    const h = HexCell(col: 0, row: 0, envRow: 1, site: 'Ruined structure',
        siteAreas: [SiteArea(x: 0, y: 0, name: 'Entrance')]);
    final back = HexCell.maybeFromJson(h.toJson())!;
    expect(back.siteAreas.single.name, 'Entrance');
    expect(const HexCell(col: 0, row: 0, envRow: 1).toJson().containsKey('siteAreas'), isFalse);
  });
}
```

- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Add `SiteArea` above `HexCell` in `models.dart`:

```dart
/// One interior area of a site (H4c). A minimal grid cell — no corridors.
class SiteArea {
  const SiteArea({required this.x, required this.y, required this.name});
  final int x;
  final int y;
  final String name; // a siteAreaTypes entry

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'name': name};

  static SiteArea? maybeFromJson(dynamic j) {
    if (j is! Map || j['x'] is! int || j['y'] is! int) return null;
    return SiteArea(
        x: j['x'] as int, y: j['y'] as int, name: (j['name'] as String?) ?? '');
  }
}
```

- [ ] **Step 4:** Add `siteAreas` to `HexCell` — field (`final List<SiteArea> siteAreas;`), ctor
  (`this.siteAreas = const []`), `copyWith` (`List<SiteArea>? siteAreas, bool clearSiteAreas = false`
  + `siteAreas: clearSiteAreas ? const [] : (siteAreas ?? this.siteAreas)`), `toJson`
  (`if (siteAreas.isNotEmpty) 'siteAreas': siteAreas.map((e) => e.toJson()).toList()`),
  `maybeFromJson` (`siteAreas: ((j['siteAreas'] as List?) ?? const []).map(SiteArea.maybeFromJson).whereType<SiteArea>().toList()`).
- [ ] **Step 5:** Run → PASS. `flutter test` → all green.
- [ ] **Step 6:** Commit: `feat(hexcrawl): SiteArea model + HexCell.siteAreas field (H4c)`.

---

### Task 4: `rollSiteArea` engine + `nextSiteAreaPosition` placement

**Files:** Modify `lib/engine/hexcrawl.dart`, `lib/engine/map_builder.dart`; Test `test/hexcrawl_interior_test.dart`.

- [ ] **Step 1:** Append tests:

```dart
  test('rollSiteArea is a defined area type', () {
    final data = _data();
    expect(data.siteAreaTypes, contains(rollSiteArea(data, Dice(Random(1)))));
  });

  test('nextSiteAreaPosition: first at origin, then non-overlapping', () {
    final dice = Dice(Random(7));
    final areas = <SiteArea>[];
    final occupied = <(int, int)>{};
    for (var i = 0; i < 8; i++) {
      final p = nextSiteAreaPosition(areas, dice);
      expect(occupied.contains((p.x, p.y)), isFalse);
      occupied.add((p.x, p.y));
      areas.add(SiteArea(x: p.x, y: p.y, name: 'A'));
    }
    expect(areas.first.x, 0);
    expect(areas.first.y, 0);
  });
```

- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Append to `hexcrawl.dart`:

```dart
/// A site interior area type (H4c).
String rollSiteArea(HexcrawlData data, Dice dice) =>
    rollFrom(data.siteAreaTypes, dice);
```

  Append to `map_builder.dart` (reuses the shared `_roomDirs`):

```dart
/// Next free grid cell for a site interior area (H4c): a free 4-neighbor of a
/// random existing area, BFS-walking if boxed in. First area -> (0,0). Mirrors
/// [nextRoomPosition] but carries no ids/corridors (site interiors are simple).
({int x, int y}) nextSiteAreaPosition(List<SiteArea> areas, Dice dice) {
  if (areas.isEmpty) return (x: 0, y: 0);
  final occupied = {for (final a in areas) (a.x, a.y)};
  final visited = <int>{0};
  final queue = <SiteArea>[areas.first];
  while (queue.isNotEmpty) {
    final a = queue.removeAt(0);
    final free = [
      for (final d in _roomDirs)
        if (!occupied.contains((a.x + d.$1, a.y + d.$2)))
          (x: a.x + d.$1, y: a.y + d.$2),
    ];
    if (free.isNotEmpty) return free[dice.dN(free.length) - 1];
    for (var i = 0; i < areas.length; i++) {
      if (visited.contains(i)) continue;
      final r = areas[i];
      if (_roomDirs.any((d) => r.x == a.x + d.$1 && r.y == a.y + d.$2)) {
        visited.add(i);
        queue.add(r);
      }
    }
  }
  throw StateError('nextSiteAreaPosition: no free cell found');
}
```

- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit: `feat(hexcrawl): rollSiteArea + nextSiteAreaPosition (H4c)`.

---

### Task 5: `crawlSiteArea` / `generateSiteInterior` notifier

**Files:** Modify `lib/state/providers.dart`; Test `test/hexcrawl_interior_test.dart`.

- [ ] **Step 1:** Append a notifier test:

```dart
  test('crawlSiteArea adds one area; generateSiteInterior sets N (clamped)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final data = _data();
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    final n = c.read(mapProvider.notifier);
    await c.read(mapProvider.future);
    await n.revealHexAt(0, 0, 1);
    await n.setHexSite(0, 0, 'Ruined structure');

    await n.crawlSiteArea(0, 0, data, Dice(Random(2)));
    var s = await c.read(mapProvider.future);
    expect(s.hexes.first.siteAreas.length, 1);

    await n.generateSiteInterior(0, 0, 5, data, Dice(Random(3)));
    s = await c.read(mapProvider.future);
    expect(s.hexes.first.siteAreas.length, 5);

    await n.generateSiteInterior(0, 0, 99, data, Dice(Random(4))); // clamp 12
    s = await c.read(mapProvider.future);
    expect(s.hexes.first.siteAreas.length, 12);

    // No-op without a site.
    await n.revealHexAt(2, 0, 1);
    await n.crawlSiteArea(2, 0, data, Dice(Random(5)));
    s = await c.read(mapProvider.future);
    expect(s.hexes.firstWhere((h) => h.col == 2).siteAreas, isEmpty);
  });
```

- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Add after `generateSite` in `MapNotifier`:

```dart
  /// Site interior crawl: append one area to the site at (col,row).
  Future<void> crawlSiteArea(
      int col, int row, HexcrawlData data, Dice dice) async {
    final s = await _ready;
    final idx = s.hexes.indexWhere((h) => h.col == col && h.row == row);
    if (idx < 0) return;
    final h = s.hexes[idx];
    if (h.site == null) return;
    final pos = nextSiteAreaPosition(h.siteAreas, dice);
    final area = SiteArea(x: pos.x, y: pos.y, name: rollSiteArea(data, dice));
    await save(s.copyWith(
        hexes: [...s.hexes]
          ..[idx] = h.copyWith(siteAreas: [...h.siteAreas, area])));
  }

  /// Site interior full: generate a fresh [count]-area interior (clamp 3..12)
  /// for the site at (col,row).
  Future<void> generateSiteInterior(
      int col, int row, int count, HexcrawlData data, Dice dice) async {
    final s = await _ready;
    final idx = s.hexes.indexWhere((h) => h.col == col && h.row == row);
    if (idx < 0) return;
    final h = s.hexes[idx];
    if (h.site == null) return;
    final n = count.clamp(3, 12);
    final areas = <SiteArea>[];
    for (var i = 0; i < n; i++) {
      final pos = nextSiteAreaPosition(areas, dice);
      areas.add(SiteArea(x: pos.x, y: pos.y, name: rollSiteArea(data, dice)));
    }
    await save(
        s.copyWith(hexes: [...s.hexes]..[idx] = h.copyWith(siteAreas: areas)));
  }
```

- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit: `feat(hexcrawl): crawlSiteArea/generateSiteInterior notifier (H4c)`.

---

### Task 6: UI — Enter button + interior canvas mode

**Files:** Modify `lib/features/map_screen.dart`; Test `test/hexcrawl_interior_ui_test.dart` (new).

- [ ] **Step 1:** Extend the enum: `enum _HexZoom { region, flower, interior }`. Add state to
  `HexMapPaneState`: `int _hcInteriorCount = 6;`.
- [ ] **Step 2:** In `build`, extend the `Expanded` to handle interior mode:

```dart
            Expanded(
              child: sel != null && _zoom == _HexZoom.flower
                  ? _flowerView(context, sel)
                  : sel != null && _zoom == _HexZoom.interior
                      ? _interiorView(context, sel)
                      : (s.hexes.isEmpty ? _empty(context) : _canvas(s)),
            ),
```

  (The detail card line already shows only in `_HexZoom.region` — unchanged.)
- [ ] **Step 3:** Add an **Enter** button to the site block in `_hexDetailCard`'s `Wrap`, after
  `site-full`:

```dart
                FilledButton.tonal(
                  key: const Key('site-enter'),
                  onPressed: () => setState(() => _zoom = _HexZoom.interior),
                  child: const Text('Enter'),
                ),
```

- [ ] **Step 4:** Add handlers + the interior view near `_siteFull`:

```dart
  Future<void> _interiorCrawl(HexCell h) async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref.read(mapProvider.notifier).crawlSiteArea(h.col, h.row, data, widget.oracle.dice);
  }

  Future<void> _interiorFull(HexCell h) async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref.read(mapProvider.notifier)
        .generateSiteInterior(h.col, h.row, _hcInteriorCount, data, widget.oracle.dice);
  }

  Widget _interiorView(BuildContext context, HexCell h) {
    final scheme = Theme.of(context).colorScheme;
    // Render site areas through the existing dungeon painter (no corridors).
    final rooms = [
      for (var i = 0; i < h.siteAreas.length; i++)
        DungeonRoom(
            id: '$i',
            x: h.siteAreas[i].x,
            y: h.siteAreas[i].y,
            title: h.siteAreas[i].name),
    ];
    Widget canvas;
    if (rooms.isEmpty) {
      canvas = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No areas yet. Reveal or generate the interior.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    } else {
      final minX = rooms.map((r) => r.x).reduce(math.min);
      final minY = rooms.map((r) => r.y).reduce(math.min);
      final maxX = rooms.map((r) => r.x).reduce(math.max);
      final maxY = rooms.map((r) => r.y).reduce(math.max);
      final width = math.max((maxX - minX + 1) * _cell + _cell, 360.0);
      final height = math.max((maxY - minY + 1) * _cell + _cell, 360.0);
      canvas = InteractiveViewer(
        constrained: false,
        boundaryMargin: const EdgeInsets.all(400),
        minScale: 0.5,
        maxScale: 3,
        child: SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            key: const Key('interior-canvas'),
            size: Size(width, height),
            painter: _DungeonPainter(
                rooms: rooms,
                corridors: const [],
                currentRoomId: null,
                scheme: scheme),
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                key: const Key('interior-back'),
                onPressed: () => setState(() => _zoom = _HexZoom.region),
                child: const Text('Back'),
              ),
              FilledButton.tonal(
                key: const Key('interior-reveal'),
                onPressed: () => _interiorCrawl(h),
                child: const Text('Reveal area'),
              ),
              FilledButton.tonal(
                key: const Key('interior-generate'),
                onPressed: () => _interiorFull(h),
                child: Text('Generate interior ($_hcInteriorCount)'),
              ),
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: () => setState(
                    () => _hcInteriorCount = (_hcInteriorCount - 1).clamp(3, 12)),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => setState(
                    () => _hcInteriorCount = (_hcInteriorCount + 1).clamp(3, 12)),
              ),
            ],
          ),
        ),
        Expanded(child: canvas),
        const SizedBox(height: 8),
      ],
    );
  }
```

- [ ] **Step 5:** `dart analyze lib/features/map_screen.dart` → no issues.
- [ ] **Step 6:** Widget test `test/hexcrawl_interior_ui_test.dart` — mirror `hexcrawl_site_ui_test.dart`
  (prefs-seed a hex with `site: 'Ruined structure'`, `terrain: 'hills'`, current 0,0; reuse
  `_tapOriginHex`). Asserts: hexcrawl on + tap → `site-enter` found; tap `site-enter` →
  `interior-reveal` + `interior-generate` + `interior-back` found; tap `interior-generate` →
  `interior-canvas` appears (`find.byKey(Key('interior-canvas'))` findsOneWidget). Negative: hexcrawl
  off → no `hex-detail-card`.
- [ ] **Step 7:** `flutter test test/hexcrawl_interior_ui_test.dart` → PASS.
- [ ] **Step 8:** Commit: `feat(hexcrawl): site interior Enter + area-map UI (H4c)`.

---

### Task 7: Full verification + ship + toolkit wrap-up

- [ ] **Step 1:** `dart analyze` → No issues.
- [ ] **Step 2:** `flutter test` → all green.
- [ ] **Step 3:** Asset in-sync check.
- [ ] **Step 4:** Web-verify: build web --debug; preview_start; fetch asset → `siteAreaTypes >= 10`, status 200; stop.
- [ ] **Step 5:** Reviewer pass on `git diff main..HEAD`; address findings.
- [ ] **Step 6:** Update `CLAUDE.md` — note H4 completes the hexcrawl toolkit (local-zoom + site
  detail + site interior shipped); the `build_hexcrawl.py` note's "H4 local+site" forward-reference
  is now done.
- [ ] **Step 7:** Push, PR, watch CI, squash-merge, delete branch, sync `main`.

---

## Self-review notes
- `siteAreas` on `HexCell`, never `MapState.rooms` — Dungeon tab untouched. Rendered through the
  existing `_DungeonPainter` via synthetic `DungeonRoom`s (no corridors, no current).
- `nextSiteAreaPosition` mirrors `nextRoomPosition` and reuses `_roomDirs`; dungeon code untouched.
- Crawl appends one area; Full regenerates a fresh clamped (3..12) interior — consistent with
  generateLocal/generateSite. Both no-op when `h.site == null`.
- Enter gated on `h.site != null`; `_HexZoom` now {region, flower, interior}; only one mode renders.
- All new buttons in `Wrap` (loose-constraint safe).
