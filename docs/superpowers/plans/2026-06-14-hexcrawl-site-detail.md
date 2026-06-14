# Hexcrawl H4b — Site Detail Card Implementation Plan

> **For agentic workers:** execute task-by-task, TDD, commit per task. Steps use `- [ ]`.

**Goal:** A landmark on a hex (`HexCell.site`, the type) gains a generated **writeup** —
occupant/state + hook + features — shown in the World-map hex detail card. Two paths: **Crawl**
(reveal one writeup line at a time, cap 5) and **Full** (the 4-line writeup at once). Gated by
`hexcrawl`; loggable to journal.

**Architecture:** Authored `siteOccupants`/`siteHooks`/`siteFeatures` → `HexCell.siteLines`
(`List<String>`) → pure `rollSiteLine`/`rollSiteDetail` → `MapNotifier.crawlSite`/`generateSite` →
the existing `_hexDetailCard` (from H4a) gains a site section. Reuses everything from H4a; adds no
new screen or painter.

**Tech Stack:** Dart, flutter_riverpod, shared_preferences, build_hexcrawl.py rail.

---

### Task 1: site detail content tables

**Files:** Modify `build_hexcrawl.py`; regenerate `assets/hexcrawl_data.json`.

- [ ] **Step 1:** Add the literals after `LOCAL_FEATURES`:

```python
SITE_OCCUPANTS = ["Unoccupied / abandoned", "A lone hermit or hold-out",
                  "A small band", "A territorial beast", "A larger warband",
                  "Scavengers", "A guardian", "Pilgrims or travellers",
                  "Something unnatural", "Recently emptied"]
SITE_HOOKS = ["Something valuable is hidden here", "A captive needs freeing",
              "A rival is also seeking it", "It guards a passage onward",
              "A curse or ill omen hangs over it",
              "It holds a clue to a larger mystery", "It is not what it appears",
              "A debt is owed here", "It is slowly being reclaimed",
              "An old promise binds it"]
SITE_FEATURES = ["A defensible approach", "Signs of a struggle", "A hidden cache",
                 "A source of fresh water", "Faded markings or writing",
                 "A collapsed section", "An unusual smell",
                 "Evidence of recent use", "A commanding view", "An uneasy quiet"]
```

- [ ] **Step 2:** Add to the `build()` dict: `"siteOccupants": SITE_OCCUPANTS,`,
  `"siteHooks": SITE_HOOKS,`, `"siteFeatures": SITE_FEATURES,`.
- [ ] **Step 3:** Add `"siteOccupants", "siteHooks", "siteFeatures"` to the `verify()` flat-table list.
- [ ] **Step 4:** `python3 build_hexcrawl.py`; copy to `assets/`; confirm in-sync
  (`python3 build_hexcrawl.py && diff -q hexcrawl_data.json assets/hexcrawl_data.json && rm hexcrawl_data.json`).
- [ ] **Step 5:** Commit: `feat(hexcrawl): site detail content tables (H4b)`.

---

### Task 2: `HexcrawlData` getters

**Files:** Modify `lib/engine/hexcrawl_data.dart`; Test `test/hexcrawl_data_test.dart`.

- [ ] **Step 1:** Add to the first test: `expect(data.siteOccupants, isNotEmpty); expect(data.siteHooks,
  isNotEmpty); expect(data.siteFeatures, isNotEmpty);`.
- [ ] **Step 2:** Run `flutter test test/hexcrawl_data_test.dart` → FAIL.
- [ ] **Step 3:** After the `localFeatures` getter add:

```dart
  List<String> get siteOccupants => _flat('siteOccupants');
  List<String> get siteHooks => _flat('siteHooks');
  List<String> get siteFeatures => _flat('siteFeatures');
```

- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit: `feat(hexcrawl): HexcrawlData site-detail getters (H4b)`.

---

### Task 3: `HexCell.siteLines` field

**Files:** Modify `lib/engine/models.dart`; Test `test/hexcrawl_site_test.dart` (new).

- [ ] **Step 1:** Write the failing round-trip test in `test/hexcrawl_site_test.dart`:

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
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

HexcrawlData _data() => HexcrawlData(jsonDecode(
    File('assets/hexcrawl_data.json').readAsStringSync()) as Map<String, dynamic>);

void main() {
  test('HexCell.siteLines round-trips and omits when empty', () {
    const h = HexCell(col: 1, row: 1, envRow: 1, site: 'Cave or grotto',
        siteLines: ['Held by: Scavengers']);
    final back = HexCell.maybeFromJson(h.toJson())!;
    expect(back.siteLines.single, 'Held by: Scavengers');
    expect(const HexCell(col: 0, row: 0, envRow: 1).toJson().containsKey('siteLines'), isFalse);
  });
}
```

- [ ] **Step 2:** Run → FAIL (no `siteLines`).
- [ ] **Step 3:** Add `siteLines` to `HexCell` — field (`final List<String> siteLines;`), ctor param
  (`this.siteLines = const []`), `copyWith` (`List<String>? siteLines, bool clearSiteLines = false`
  + `siteLines: clearSiteLines ? const [] : (siteLines ?? this.siteLines)`), `toJson`
  (`if (siteLines.isNotEmpty) 'siteLines': siteLines`), `maybeFromJson`
  (`siteLines: ((j['siteLines'] as List?) ?? const []).whereType<String>().toList()`).
- [ ] **Step 4:** Run → PASS. `flutter test` → all green.
- [ ] **Step 5:** Commit: `feat(hexcrawl): HexCell.siteLines field (H4b)`.

---

### Task 4: `rollSiteLine` + `rollSiteDetail` engine

**Files:** Modify `lib/engine/hexcrawl.dart`; Test `test/hexcrawl_site_test.dart`.

- [ ] **Step 1:** Append tests:

```dart
  test('rollSiteLine: labelled by index, body from the right table', () {
    final data = _data();
    final occ = rollSiteLine(data, 0, Dice(Random(1)));
    expect(occ.startsWith('Held by: '), isTrue);
    expect(data.siteOccupants, contains(occ.substring('Held by: '.length)));
    final hook = rollSiteLine(data, 1, Dice(Random(1)));
    expect(hook.startsWith('Hook: '), isTrue);
    final feat = rollSiteLine(data, 2, Dice(Random(1)));
    expect(feat.startsWith('Feature: '), isTrue);
  });

  test('rollSiteDetail returns 4 ordered lines', () {
    final lines = rollSiteDetail(_data(), Dice(Random(5)));
    expect(lines.length, 4);
    expect(lines[0].startsWith('Held by: '), isTrue);
    expect(lines[1].startsWith('Hook: '), isTrue);
    expect(lines[2].startsWith('Feature: '), isTrue);
    expect(lines[3].startsWith('Feature: '), isTrue);
  });
```

- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Append to `hexcrawl.dart`:

```dart
/// One line of a site writeup. index 0 = occupant, 1 = hook, >=2 = a feature.
String rollSiteLine(HexcrawlData data, int index, Dice dice) {
  if (index == 0) return 'Held by: ${rollFrom(data.siteOccupants, dice)}';
  if (index == 1) return 'Hook: ${rollFrom(data.siteHooks, dice)}';
  return 'Feature: ${rollFrom(data.siteFeatures, dice)}';
}

/// The full site writeup (occupant, hook, two features) for the Full path.
List<String> rollSiteDetail(HexcrawlData data, Dice dice) =>
    [for (var i = 0; i < 4; i++) rollSiteLine(data, i, dice)];
```

- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit: `feat(hexcrawl): rollSiteLine + rollSiteDetail engine (H4b)`.

---

### Task 5: `crawlSite` / `generateSite` notifier

**Files:** Modify `lib/state/providers.dart`; Test `test/hexcrawl_site_test.dart`.

- [ ] **Step 1:** Append a notifier test:

```dart
  test('crawlSite appends one line (cap 5); generateSite sets 4', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final data = _data();
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    final n = c.read(mapProvider.notifier);
    await c.read(mapProvider.future);
    // Seed a hex that has a site (region gen sets terrain; force a site via setHex path).
    await n.revealHexAt(0, 0, 1);
    await n.setHexSite(0, 0, 'Cave or grotto');

    await n.crawlSite(0, 0, data, Dice(Random(3)));
    var s = await c.read(mapProvider.future);
    expect(s.hexes.first.siteLines.length, 1);

    await n.generateSite(0, 0, data, Dice(Random(4)));
    s = await c.read(mapProvider.future);
    expect(s.hexes.first.siteLines.length, 4);
  });
```

  NOTE: this needs a `setHexSite` helper. If one doesn't exist, add it next to `setHexTerrain`:
  `Future<void> setHexSite(int col, int row, String site) async { ... copyWith(site: site) ... }`.

- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Add `setHexSite` (mirror `setHexTerrain`) and the two site methods after
  `generateLocal`:

```dart
  /// Set the hexcrawl site-type on an existing hex; no-op for unknown cells.
  Future<void> setHexSite(int col, int row, String site) async {
    final s = await _ready;
    if (!s.hexes.any((h) => h.col == col && h.row == row)) return;
    await save(s.copyWith(hexes: [
      for (final h in s.hexes)
        if (h.col == col && h.row == row) h.copyWith(site: site) else h
    ]));
  }

  /// Site crawl: append the next writeup line for the site at (col,row).
  /// No-op if the hex is absent, has no site, or already has 5 lines.
  Future<void> crawlSite(int col, int row, HexcrawlData data, Dice dice) async {
    final s = await _ready;
    final idx = s.hexes.indexWhere((h) => h.col == col && h.row == row);
    if (idx < 0) return;
    final h = s.hexes[idx];
    if (h.site == null || h.siteLines.length >= 5) return;
    final line = rollSiteLine(data, h.siteLines.length, dice);
    await save(s.copyWith(
        hexes: [...s.hexes]..[idx] = h.copyWith(siteLines: [...h.siteLines, line])));
  }

  /// Site full: set the 4-line writeup for the site at (col,row).
  Future<void> generateSite(
      int col, int row, HexcrawlData data, Dice dice) async {
    final s = await _ready;
    final idx = s.hexes.indexWhere((h) => h.col == col && h.row == row);
    if (idx < 0) return;
    final h = s.hexes[idx];
    if (h.site == null) return;
    await save(s.copyWith(
        hexes: [...s.hexes]..[idx] = h.copyWith(siteLines: rollSiteDetail(data, dice))));
  }
```

- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit: `feat(hexcrawl): setHexSite + crawlSite/generateSite notifier (H4b)`.

---

### Task 6: UI — site section in the detail card

**Files:** Modify `lib/features/map_screen.dart`; Test `test/hexcrawl_site_ui_test.dart` (new).

- [ ] **Step 1:** In `_hexDetailCard` (H4a), replace the bare `if (h.site != null) Text('Site: ...')`
  line with a site block: the type, the revealed `siteLines`, and a `Wrap` of gated buttons. Put the
  site `Wrap` alongside the existing Zoom-in `Wrap` (or extend it). The site buttons:

```dart
            if (h.site != null) ...[
              Text('Site: ${h.site}', style: theme.textTheme.bodyMedium),
              for (final line in h.siteLines)
                Text('• $line', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (h.terrain != null)
                FilledButton.tonal(
                  key: const Key('local-zoom-in'),
                  onPressed: () => setState(() => _zoom = _HexZoom.flower),
                  child: const Text('Zoom in'),
                ),
              if (h.site != null) ...[
                FilledButton.tonal(
                  key: const Key('site-crawl'),
                  onPressed: () => _siteCrawl(h),
                  child: const Text('Crawl site'),
                ),
                FilledButton.tonal(
                  key: const Key('site-full'),
                  onPressed: () => _siteFull(h),
                  child: const Text('Full site'),
                ),
                if (h.siteLines.isNotEmpty)
                  OutlinedButton(
                    key: const Key('site-log'),
                    onPressed: () => _log('Site: ${h.site}', h.siteLines.join('\n')),
                    child: const Text('Log'),
                  ),
              ],
            ]),
```

- [ ] **Step 2:** Add the handlers near `_localCrawl`/`_localFull`:

```dart
  Future<void> _siteCrawl(HexCell h) async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref.read(mapProvider.notifier).crawlSite(h.col, h.row, data, widget.oracle.dice);
  }

  Future<void> _siteFull(HexCell h) async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref.read(mapProvider.notifier).generateSite(h.col, h.row, data, widget.oracle.dice);
  }
```

- [ ] **Step 3:** `dart analyze lib/features/map_screen.dart` → no issues.
- [ ] **Step 4:** Widget test `test/hexcrawl_site_ui_test.dart` — mirror `hexcrawl_hex_detail_test.dart`
  but seed `_SeededMap` with `HexCell(col:0,row:0,envRow:1,terrain:'hills',site:'Cave or grotto')`.
  Reuse `_tapOriginHex`. Assert: hexcrawl on + tap → `site-crawl` + `site-full` found; tap `site-full`
  → a `• Held by: ` text appears (`find.textContaining('Held by:')` findsOneWidget) and `site-log`
  appears; hexcrawl off → no `hex-detail-card`.
- [ ] **Step 5:** `flutter test test/hexcrawl_site_ui_test.dart` → PASS.
- [ ] **Step 6:** Commit: `feat(hexcrawl): site writeup section in hex detail card (H4b)`.

---

### Task 7: Full verification + ship

- [ ] **Step 1:** `dart analyze` → No issues.
- [ ] **Step 2:** `flutter test` → all green.
- [ ] **Step 3:** Asset in-sync check.
- [ ] **Step 4:** Web-verify: build web --debug; preview_start; fetch the asset → assert
  `siteOccupants`/`siteHooks`/`siteFeatures` each `>= 10`, status 200; stop.
- [ ] **Step 5:** Reviewer pass on `git diff main..HEAD`; address findings.
- [ ] **Step 6:** Push, PR, watch CI, squash-merge, delete branch, sync `main`.

---

## Self-review notes
- `siteLines` stored on `HexCell`, not `MapState.rooms` — Dungeon tab untouched.
- Crawl cap 5 (occupant, hook, 3 features); Full = 4 (occupant, hook, 2 features) — deliberate.
- Site controls gated on `h.site != null`; Zoom-in still gated on `terrain != null` — independent.
- New buttons in the existing card `Wrap` (loose-constraint safe). No new screen/painter.
- `rollSiteLine` index→label is the single source for both crawl (incremental) and full.
