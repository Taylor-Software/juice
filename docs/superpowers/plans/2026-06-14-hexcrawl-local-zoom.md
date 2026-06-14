# Hexcrawl H4a — Local Zoom (7-hex flower) Implementation Plan

> **For agentic workers:** execute task-by-task, TDD, commit per task. Steps use `- [ ]`.

**Goal:** Expand one revealed, terrained hex into a 7-hex flower (center = parent terrain; 6 ring
sub-hexes rolled finer + a local feature), inline on the World map, both paths (Crawl = reveal one
ring sub-hex; Full = fill all 6).

**Architecture:** Authored `localFeatures` table → `HexCell.local` (`List<LocalCell>`) → pure
`rollLocalCell` → `MapNotifier.crawlLocal`/`generateLocal` → `HexMapPaneState` hex-select detail
card + flower canvas mode + `_FlowerPainter`. Gated by `hexcrawl`. Reuses existing hex geometry
(`hexCenterFor`, `hexNeighbors`, `hexcrawlTerrainHues`).

**Tech Stack:** Dart, flutter_riverpod, shared_preferences, build_hexcrawl.py rail.

---

### Task 1: `localFeatures` content table

**Files:** Modify `build_hexcrawl.py`; regenerate `assets/hexcrawl_data.json`.

- [ ] **Step 1:** Add the literal after `DUNGEON_DRESSING`:

```python
LOCAL_FEATURES = ["A trickling stream", "A rocky outcrop", "A dense thicket",
                  "A quiet clearing", "Fresh animal tracks", "A fallen tree",
                  "A muddy hollow", "A worn game trail", "An old fire-pit",
                  "A weathered marker"]
```

- [ ] **Step 2:** Add to the `build()` dict: `"localFeatures": LOCAL_FEATURES,`.
- [ ] **Step 3:** Add `"localFeatures"` to the `verify()` flat-table name list (the
  `for name in [...]` loop that asserts non-empty + no-dup).
- [ ] **Step 4:** Run `python3 build_hexcrawl.py`; expect `wrote hexcrawl_data.json: ...`. Copy:
  `cp hexcrawl_data.json assets/hexcrawl_data.json && rm hexcrawl_data.json`. Confirm in-sync:
  `python3 build_hexcrawl.py && diff -q hexcrawl_data.json assets/hexcrawl_data.json && rm hexcrawl_data.json`.
- [ ] **Step 5:** Commit: `feat(hexcrawl): localFeatures content table (H4a)`.

---

### Task 2: `HexcrawlData.localFeatures` getter

**Files:** Modify `lib/engine/hexcrawl_data.dart`; Test `test/hexcrawl_data_test.dart`.

- [ ] **Step 1:** In the first test of `hexcrawl_data_test.dart`, add: `expect(data.localFeatures, isNotEmpty);`.
- [ ] **Step 2:** Run `flutter test test/hexcrawl_data_test.dart` → FAIL (getter undefined).
- [ ] **Step 3:** After the `dungeonDressing` getter add: `List<String> get localFeatures => _flat('localFeatures');`.
- [ ] **Step 4:** Run the test → PASS.
- [ ] **Step 5:** Commit: `feat(hexcrawl): HexcrawlData.localFeatures getter (H4a)`.

---

### Task 3: `LocalCell` model + `HexCell.local` field

**Files:** Modify `lib/engine/models.dart`; Test `test/hexcrawl_local_test.dart` (new).

- [ ] **Step 1:** Write the failing round-trip test in `test/hexcrawl_local_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('HexCell.local round-trips and omits when empty', () {
    final h = HexCell(col: 1, row: 2, envRow: 1, terrain: 'forest', local: const [
      LocalCell(slot: 0, terrain: 'hills', feature: 'A rocky outcrop'),
    ]);
    final j = h.toJson();
    expect(j['local'], isNotNull);
    final back = HexCell.maybeFromJson(j)!;
    expect(back.local.single.slot, 0);
    expect(back.local.single.terrain, 'hills');
    expect(back.local.single.feature, 'A rocky outcrop');

    final empty = HexCell(col: 0, row: 0, envRow: 1).toJson();
    expect(empty.containsKey('local'), isFalse);
  });
}
```

- [ ] **Step 2:** Run `flutter test test/hexcrawl_local_test.dart` → FAIL (`LocalCell` undefined, no `local` param).
- [ ] **Step 3:** Add the `LocalCell` class above `HexCell` in `models.dart`:

```dart
/// One ring sub-hex of a local-zoom flower (H4a).
class LocalCell {
  const LocalCell(
      {required this.slot, required this.terrain, required this.feature});
  final int slot; // 0..5 ring position
  final String terrain; // hexcrawl terrain key
  final String feature; // a localFeatures entry

  Map<String, dynamic> toJson() =>
      {'slot': slot, 'terrain': terrain, 'feature': feature};

  static LocalCell? maybeFromJson(dynamic j) {
    if (j is! Map || j['slot'] is! int) return null;
    return LocalCell(
      slot: j['slot'] as int,
      terrain: (j['terrain'] as String?) ?? '',
      feature: (j['feature'] as String?) ?? '',
    );
  }
}
```

- [ ] **Step 4:** Add `local` to `HexCell` — the field, constructor param (`this.local = const []`),
  `copyWith` (add `List<LocalCell>? local, bool clearLocal = false` and
  `local: clearLocal ? const [] : (local ?? this.local)`), `toJson`
  (`if (local.isNotEmpty) 'local': local.map((e) => e.toJson()).toList()`), and `maybeFromJson`
  (`local: ((j['local'] as List?) ?? const []).map(LocalCell.maybeFromJson).whereType<LocalCell>().toList()`).
- [ ] **Step 5:** Run the test → PASS. Run `flutter test` (HexCell is widely used) → all green.
- [ ] **Step 6:** Commit: `feat(hexcrawl): LocalCell model + HexCell.local field (H4a)`.

---

### Task 4: `rollLocalCell` engine

**Files:** Modify `lib/engine/hexcrawl.dart`; Test `test/hexcrawl_local_test.dart`.

- [ ] **Step 1:** Append to `test/hexcrawl_local_test.dart` `main()` a test (add imports `dart:convert`,
  `dart:io`, `dart:math`, `hexcrawl.dart`, `hexcrawl_data.dart`, `dice.dart`):

```dart
  test('rollLocalCell: terrain is a defined key, feature from localFeatures', () {
    final data = HexcrawlData(jsonDecode(
        File('assets/hexcrawl_data.json').readAsStringSync()) as Map<String, dynamic>);
    final keys = data.terrains.map((t) => t.key).toSet();
    final c = rollLocalCell(data, 'forest', 3, Dice(Random(1)));
    expect(c.slot, 3);
    expect(keys, contains(c.terrain));
    expect(data.localFeatures, contains(c.feature));
  });
```

- [ ] **Step 2:** Run → FAIL (`rollLocalCell` undefined).
- [ ] **Step 3:** Append to `hexcrawl.dart` (import `models.dart` for `LocalCell`):

```dart
/// One ring sub-hex of a local-zoom flower: finer terrain (from the parent
/// terrain's neighbour table) + a local feature. [slot] is the ring position.
LocalCell rollLocalCell(
    HexcrawlData data, String centerTerrain, int slot, Dice dice) {
  final terrain = rollNeighbour(data, centerTerrain, dice)?.key ?? centerTerrain;
  return LocalCell(
      slot: slot, terrain: terrain, feature: rollFrom(data.localFeatures, dice));
}
```

- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit: `feat(hexcrawl): rollLocalCell engine (H4a)`.

---

### Task 5: `crawlLocal` / `generateLocal` notifier

**Files:** Modify `lib/state/providers.dart`; Test `test/hexcrawl_local_test.dart`.

- [ ] **Step 1:** Append a notifier test (imports `flutter_riverpod`, `shared_preferences`, `providers.dart`):

```dart
  test('crawlLocal adds one ring cell (cap 6); generateLocal fills 6', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final data = HexcrawlData(jsonDecode(
        File('assets/hexcrawl_data.json').readAsStringSync()) as Map<String, dynamic>);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    final n = c.read(mapProvider.notifier);
    await c.read(mapProvider.future);
    // Seed one terrained hex via the public region path.
    await n.generateRegion(data, 'temperate', 1, Dice(Random(2)));
    var s = await c.read(mapProvider.future);
    final h0 = s.hexes.first;

    await n.crawlLocal(h0.col, h0.row, data, Dice(Random(3)));
    s = await c.read(mapProvider.future);
    expect(s.hexes.firstWhere((h) => h.col == h0.col && h.row == h0.row).local.length, 1);

    await n.generateLocal(h0.col, h0.row, data, Dice(Random(4)));
    s = await c.read(mapProvider.future);
    expect(s.hexes.firstWhere((h) => h.col == h0.col && h.row == h0.row).local.length, 6);
  });
```

- [ ] **Step 2:** Run → FAIL (methods undefined). NB: if `generateRegion` ever yields a hex without
  terrain, the test's seed hex still has terrain (region cells always set terrain) — safe.
- [ ] **Step 3:** Add after `generateRegion` in `MapNotifier`:

```dart
  /// Local-zoom crawl: reveal the next ring sub-hex (0..5) of the hex at
  /// (col,row). No-op if the hex is absent, has no terrain, or is full.
  Future<void> crawlLocal(int col, int row, HexcrawlData data, Dice dice) async {
    final s = await _ready;
    final idx = s.hexes.indexWhere((h) => h.col == col && h.row == row);
    if (idx < 0) return;
    final h = s.hexes[idx];
    if (h.terrain == null || h.local.length >= 6) return;
    final cell = rollLocalCell(data, h.terrain!, h.local.length, dice);
    await save(s.copyWith(
        hexes: [...s.hexes]..[idx] = h.copyWith(local: [...h.local, cell])));
  }

  /// Local-zoom full: fill all 6 ring sub-hexes of the hex at (col,row).
  Future<void> generateLocal(
      int col, int row, HexcrawlData data, Dice dice) async {
    final s = await _ready;
    final idx = s.hexes.indexWhere((h) => h.col == col && h.row == row);
    if (idx < 0) return;
    final h = s.hexes[idx];
    if (h.terrain == null) return;
    final cells = [
      for (var i = 0; i < 6; i++) rollLocalCell(data, h.terrain!, i, dice)
    ];
    await save(s.copyWith(hexes: [...s.hexes]..[idx] = h.copyWith(local: cells)));
  }
```

- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit: `feat(hexcrawl): crawlLocal/generateLocal notifier (H4a)`.

---

### Task 6: UI — hex selection, detail card, flower canvas mode

**Files:** Modify `lib/features/map_screen.dart`; Test `test/hexcrawl_hex_detail_test.dart` (new).

- [ ] **Step 1:** Add state to `HexMapPaneState` (near `_hcCount`):

```dart
  int? _selCol, _selRow; // selected revealed hex (null = none)
  _HexZoom _zoom = _HexZoom.region;
```
  and a top-level enum near the class: `enum _HexZoom { region, flower }`.

- [ ] **Step 2:** Selected-hex helper in `HexMapPaneState`:

```dart
  HexCell? _selectedHex(MapState s) => _selCol == null
      ? null
      : s.hexes
          .where((h) => h.col == _selCol && h.row == _selRow)
          .firstOrNull;
```

- [ ] **Step 3:** In `_canvas`'s `onTapUp`, replace the inert revealed branch
  (`if (revealed.contains((hit.col, hit.row))) return;`) with select:

```dart
            if (revealed.contains((hit.col, hit.row))) {
              setState(() {
                _selCol = hit.col;
                _selRow = hit.row;
                _zoom = _HexZoom.region;
              });
              return;
            }
```

- [ ] **Step 4:** In `build`'s `data:` Column, swap the `Expanded` line and add the detail card.
  Compute `final sel = _selectedHex(s);` at the top of the builder. Replace the `Expanded(...)` with:

```dart
            Expanded(
              child: _zoom == _HexZoom.flower && sel != null
                  ? _flowerView(context, sel)
                  : (s.hexes.isEmpty ? _empty(context) : _canvas(s)),
            ),
            if (_hexcrawlOn() && sel != null && _zoom == _HexZoom.region)
              _hexDetailCard(context, sel),
```

- [ ] **Step 5:** Add the detail card + flower view + flower painter. The card (region mode) shows
  terrain + a gated "Zoom in" (only when terrain present):

```dart
  Widget _hexDetailCard(BuildContext context, HexCell h) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('hex-detail-card'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hex (${h.col}, ${h.row})', style: theme.textTheme.titleSmall),
            if (h.terrain != null) Text(h.terrain!, style: theme.textTheme.bodyMedium),
            if (h.site != null) Text('Site: ${h.site}', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (h.terrain != null)
                FilledButton.tonal(
                  key: const Key('local-zoom-in'),
                  onPressed: () => setState(() => _zoom = _HexZoom.flower),
                  child: const Text('Zoom in'),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _localCrawl(HexCell h) async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref.read(mapProvider.notifier).crawlLocal(h.col, h.row, data, widget.oracle.dice);
  }

  Future<void> _localFull(HexCell h) async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref.read(mapProvider.notifier).generateLocal(h.col, h.row, data, widget.oracle.dice);
  }

  Widget _flowerView(BuildContext context, HexCell h) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton(
              key: const Key('local-back'),
              onPressed: () => setState(() => _zoom = _HexZoom.region),
              child: const Text('Back'),
            ),
            FilledButton.tonal(
              key: const Key('local-reveal'),
              onPressed: () => _localCrawl(h),
              child: const Text('Reveal sub-hex'),
            ),
            FilledButton.tonal(
              key: const Key('local-fill'),
              onPressed: () => _localFull(h),
              child: const Text('Fill hex'),
            ),
          ]),
        ),
        Expanded(
          child: InteractiveViewer(
            constrained: false,
            boundaryMargin: const EdgeInsets.all(200),
            minScale: 0.5,
            maxScale: 3,
            child: SizedBox(
              width: 360,
              height: 360,
              child: CustomPaint(
                key: const Key('flower-canvas'),
                size: const Size(360, 360),
                painter: _FlowerPainter(centerTerrain: h.terrain ?? '', ring: h.local, scheme: scheme),
              ),
            ),
          ),
        ),
        if (h.local.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 96),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final lc in h.local)
                    Text('• ${lc.terrain}: ${lc.feature}',
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
```

  And the painter (center at flower origin + the 6 `hexNeighbors(0,0)`, slot i → neighbour i):

```dart
class _FlowerPainter extends CustomPainter {
  _FlowerPainter({required this.centerTerrain, required this.ring, required this.scheme});
  final String centerTerrain;
  final List<LocalCell> ring;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final neighbours = hexNeighbors(0, 0); // 6, fixed order = slot order
    final cells = <({int col, int row, String terrain, bool center})>[
      (col: 0, row: 0, terrain: centerTerrain, center: true),
      for (final lc in ring)
        if (lc.slot >= 0 && lc.slot < 6)
          (col: neighbours[lc.slot].col, row: neighbours[lc.slot].row, terrain: lc.terrain, center: false),
    ];
    final minCol = cells.map((c) => c.col).reduce(math.min);
    final minRow = cells.map((c) => c.row).reduce(math.min);
    final origin = Offset(size.width / 2, size.height / 2);
    final ref0 = hexCenterFor(0, 0, minCol, minRow, _hexSize);
    for (final cell in cells) {
      final c = origin + (hexCenterFor(cell.col, cell.row, minCol, minRow, _hexSize) - ref0);
      final path = _FlowerPainter._hexPath(c, _hexSize - 1);
      final base = _verdantTerrainHues[cell.terrain] ??
          hexcrawlTerrainHues[cell.terrain] ?? scheme.surfaceContainerHighest;
      canvas.drawPath(path, Paint()
        ..color = Color.alphaBlend(base.withValues(alpha: 0.5), scheme.surfaceContainerHighest));
      canvas.drawPath(path, Paint()
        ..color = cell.center ? scheme.primary : scheme.outlineVariant
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell.center ? 3 : 1);
      final label = cell.terrain.isEmpty ? '?' : cell.terrain[0].toUpperCase();
      final tp = TextPainter(
        text: TextSpan(text: label, style: TextStyle(color: scheme.onSurface, fontSize: 18, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  static Path _hexPath(Offset center, double size) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 3 * i;
      final v = center + Offset(size * math.cos(a), size * math.sin(a));
      i == 0 ? path.moveTo(v.dx, v.dy) : path.lineTo(v.dx, v.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_FlowerPainter old) =>
      old.centerTerrain != centerTerrain || old.ring != ring || old.scheme != scheme;
}
```

- [ ] **Step 6:** `dart analyze lib/features/map_screen.dart` → no issues.
- [ ] **Step 7:** Widget test `test/hexcrawl_hex_detail_test.dart` — mirror
  `hexcrawl_dungeon_controls_test.dart` (oracle + hex fixtures, `_FixedSessions`,
  `hexcrawlDataProvider` + `mapProvider` overrides). Seed `mapProvider` with one terrained revealed
  hex via a `_SeededMap extends MapNotifier` override (`build()` returns a `MapState` with one
  `HexCell(col:0,row:0,envRow:1,terrain:'forest')` and `currentHexCol/Row = 0`). Tap the hex center
  on the `hex-canvas` (`tester.tapAt(tester.getCenter(find.byKey(const Key('hex-canvas'))))`), pump,
  assert `hex-detail-card` + `local-zoom-in` are found when `hexcrawl` on; tap `local-zoom-in`,
  pump, assert `local-fill` + `flower-canvas` appear. Negative: with `hexcrawl` off the card is
  absent. (If the canvas tap proves flaky in execution, fall back to asserting card gating via a
  test-only initial selection; keep the notifier behaviour covered by Task 5.)
- [ ] **Step 8:** `flutter test test/hexcrawl_hex_detail_test.dart` → PASS.
- [ ] **Step 9:** Commit: `feat(hexcrawl): hex-select detail card + local-zoom flower UI (H4a)`.

---

### Task 7: Full verification + ship

- [ ] **Step 1:** `dart analyze` → No issues found.
- [ ] **Step 2:** `flutter test` → all green (≥ 746 + new).
- [ ] **Step 3:** Asset in-sync: `python3 build_hexcrawl.py && diff -q hexcrawl_data.json assets/hexcrawl_data.json && rm hexcrawl_data.json`.
- [ ] **Step 4:** Web-verify: `flutter build web --debug`; `preview_start flutter-web`; `preview_eval`
  fetch `/assets/assets/hexcrawl_data.json` → assert `localFeatures.length >= 10`, status 200; stop.
- [ ] **Step 5:** Reviewer pass (`caveman:cavecrew-reviewer`) on `git diff main..HEAD`; address findings.
- [ ] **Step 6:** Push, open PR, watch CI, squash-merge, delete branch, sync `main`.

---

## Self-review notes
- Types consistent: `LocalCell{slot,terrain,feature}` used identically in model/engine/notifier/painter.
- Flower center derived from `h.terrain` (not stored); Zoom-in guarded to `terrain != null` (matches spec).
- Interior stored on `HexCell.local`, never `MapState.rooms` — Dungeon tab untouched.
- No modal: flower replaces the canvas via `_zoom`, one InteractiveViewer (loose-constraint safe).
- All new buttons in `Wrap` (bounded width).
