# Hexcrawl H3 — Dungeon Map Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate dungeon rooms with generic, system-agnostic content on the existing room grid, two paths (crawl one room; full N-room dungeon), when `hexcrawl` is on.

**Architecture:** Author 3 generic dungeon tables into the hexcrawl asset; a pure `rollDungeonRoom` builds a room's title/detail; `MapNotifier.crawlDungeon`/`generateDungeon` reuse the existing `addRoom` (4-neighbor placement + corridors); gated controls on the Dungeon pane.

**Tech Stack:** Python 3, Dart/Flutter, flutter_riverpod, package:flutter_test.

**Scope guard (H3):** generic dungeon content + crawl/full on the existing grid. No H4, no per-room encounters, no game-specific monsters.

---

## File structure

**New:** `test/hexcrawl_dungeon_test.dart`.
**Edit:** `build_hexcrawl.py` + `assets/hexcrawl_data.json`, `lib/engine/hexcrawl_data.dart`, `lib/engine/hexcrawl.dart`, `lib/state/providers.dart`, `lib/features/map_screen.dart`, `test/hexcrawl_data_test.dart`.

---

### Task 1: Generic dungeon content in the asset

**Files:** Modify `build_hexcrawl.py`, `assets/hexcrawl_data.json`.

- [ ] **Step 1: Add the three tables** — in `build_hexcrawl.py`, after the `ENCOUNTER_CATEGORIES` list, add:

```python
DUNGEON_ROOM_TYPES = ["Chamber", "Corridor junction", "Great hall", "Cave",
                      "Vault", "Shrine", "Cell block", "Pit", "Stairway",
                      "Flooded room"]
DUNGEON_CONTENTS = ["Empty", "Monster lair", "Trap", "Treasure",
                    "Puzzle / mechanism", "Denizen / NPC", "Hazard",
                    "Curious feature"]
DUNGEON_DRESSING = ["Rubble-strewn floor", "Dripping water", "Old bones",
                    "Claw marks on the walls", "A faint draft",
                    "A mouldering tapestry", "A cold spot", "Scattered coins",
                    "A strange smell", "Flickering shadows"]
```
In `build()`, add to the returned dict (after `"encounterCategories": ENCOUNTER_CATEGORIES,`):
```python
        "dungeonRoomTypes": DUNGEON_ROOM_TYPES,
        "dungeonContents": DUNGEON_CONTENTS,
        "dungeonDressing": DUNGEON_DRESSING,
```
In `verify()`, extend the final flat-table loop name list to include the new tables:
```python
    for name in ["weather", "hazards", "siteTypes", "regionFeatures",
                 "encounterCategories", "dungeonRoomTypes", "dungeonContents",
                 "dungeonDressing"]:
```

- [ ] **Step 2: Rebuild + copy** — Run: `python3 build_hexcrawl.py && cp hexcrawl_data.json assets/hexcrawl_data.json`
Expected: prints the `wrote hexcrawl_data.json…` line, no assertion error.

- [ ] **Step 3: Commit**
```bash
git add build_hexcrawl.py assets/hexcrawl_data.json
git commit -m "feat(hexcrawl): generic dungeon content tables (H3)"
```

---

### Task 2: `HexcrawlData` dungeon getters

**Files:** Modify `lib/engine/hexcrawl_data.dart`, `test/hexcrawl_data_test.dart`.

- [ ] **Step 1: Write the failing test** — append inside the first `test(...)` in `test/hexcrawl_data_test.dart` (after `expect(data.encounterCategories, contains('Nothing of note'));`):
```dart
    expect(data.dungeonRoomTypes, contains('Vault'));
    expect(data.dungeonContents, contains('Treasure'));
    expect(data.dungeonDressing, isNotEmpty);
```

- [ ] **Step 2: Run it** — Run: `flutter test test/hexcrawl_data_test.dart` → FAIL (`dungeonRoomTypes` not defined).

- [ ] **Step 3: Add the getters** — in `lib/engine/hexcrawl_data.dart`, after `List<String> get encounterCategories => _flat('encounterCategories');`:
```dart
  List<String> get dungeonRoomTypes => _flat('dungeonRoomTypes');
  List<String> get dungeonContents => _flat('dungeonContents');
  List<String> get dungeonDressing => _flat('dungeonDressing');
```

- [ ] **Step 4: Run it** — Run: `flutter test test/hexcrawl_data_test.dart` → PASS.

- [ ] **Step 5: Commit**
```bash
git add lib/engine/hexcrawl_data.dart test/hexcrawl_data_test.dart
git commit -m "feat(hexcrawl): HexcrawlData dungeon getters (H3)"
```

---

### Task 3: `rollDungeonRoom` engine

**Files:** Modify `lib/engine/hexcrawl.dart`; Create `test/hexcrawl_dungeon_test.dart`.

- [ ] **Step 1: Write the failing test** — `test/hexcrawl_dungeon_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/hexcrawl.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';

void main() {
  final data = HexcrawlData(
      jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
          as Map<String, dynamic>);

  test('rollDungeonRoom: title is a room type; detail has content + dressing',
      () {
    final r = rollDungeonRoom(data, Dice(Random(4)));
    expect(data.dungeonRoomTypes, contains(r.title));
    expect(data.dungeonContents.any((c) => r.detail.contains(c)), isTrue);
    expect(data.dungeonDressing.any((d) => r.detail.contains(d)), isTrue);
  });
}
```

- [ ] **Step 2: Run it** — Run: `flutter test test/hexcrawl_dungeon_test.dart` → FAIL (`rollDungeonRoom` not defined).

- [ ] **Step 3: Add `rollDungeonRoom` to `lib/engine/hexcrawl.dart`** — at the end of the file:
```dart
/// A generic dungeon room: a room type (title) plus content + dressing (detail).
({String title, String detail}) rollDungeonRoom(HexcrawlData data, Dice dice) {
  final type = rollFrom(data.dungeonRoomTypes, dice);
  final content = rollFrom(data.dungeonContents, dice);
  final dressing = rollFrom(data.dungeonDressing, dice);
  return (title: type, detail: '$content. $dressing.');
}
```

- [ ] **Step 4: Run it** — Run: `flutter test test/hexcrawl_dungeon_test.dart` → PASS.

- [ ] **Step 5: Commit**
```bash
git add lib/engine/hexcrawl.dart test/hexcrawl_dungeon_test.dart
git commit -m "feat(hexcrawl): rollDungeonRoom generic content (H3)"
```

---

### Task 4: `MapNotifier.crawlDungeon` + `generateDungeon`

**Files:** Modify `lib/state/providers.dart`; extend `test/hexcrawl_dungeon_test.dart`.

- [ ] **Step 1: Write the failing test** — append to `test/hexcrawl_dungeon_test.dart` (add imports: `package:flutter_riverpod/flutter_riverpod.dart`, `package:shared_preferences/shared_preferences.dart`, `package:juice_oracle/state/providers.dart`, and add `TestWidgetsFlutterBinding.ensureInitialized();` as the first line of `main`):

```dart
  test('crawlDungeon adds a room; generateDungeon adds N rooms', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    final n = c.read(mapProvider.notifier);
    await c.read(mapProvider.future);

    await n.crawlDungeon(data, Dice(Random(2)));
    var s = await c.read(mapProvider.future);
    expect(s.rooms.length, 1);
    expect(s.rooms.single.title, isNotEmpty);

    await n.generateDungeon(data, 5, Dice(Random(8)));
    s = await c.read(mapProvider.future);
    expect(s.rooms.length, 6); // 1 + 5
  });
```

- [ ] **Step 2: Run it** — Run: `flutter test test/hexcrawl_dungeon_test.dart` → FAIL (`crawlDungeon` not defined).

- [ ] **Step 3: Add the methods to `MapNotifier`** — in `lib/state/providers.dart`, immediately after the `addRoom` method's closing `}`, add:
```dart
  /// Hexcrawl crawl: add one room with generic content.
  Future<void> crawlDungeon(HexcrawlData data, Dice dice) async {
    final r = rollDungeonRoom(data, dice);
    await addRoom(title: r.title, detail: r.detail, dice: dice);
  }

  /// Hexcrawl full dungeon: add [count] connected rooms with generic content.
  Future<void> generateDungeon(HexcrawlData data, int count, Dice dice) async {
    for (var i = 0; i < count; i++) {
      final r = rollDungeonRoom(data, dice);
      await addRoom(title: r.title, detail: r.detail, dice: dice);
    }
  }
```
(`rollDungeonRoom` comes from the already-imported `hexcrawl.dart`.)

- [ ] **Step 4: Run it** — Run: `flutter test test/hexcrawl_dungeon_test.dart` → PASS. Run: `dart analyze lib/state/providers.dart` → No issues.

- [ ] **Step 5: Commit**
```bash
git add lib/state/providers.dart test/hexcrawl_dungeon_test.dart
git commit -m "feat(hexcrawl): MapNotifier crawlDungeon + generateDungeon (H3)"
```

---

### Task 5: Gated Dungeon-pane controls

**Files:** Modify `lib/features/map_screen.dart`; Create `test/hexcrawl_dungeon_controls_test.dart`.

- [ ] **Step 1: Write the failing test** — `test/hexcrawl_dungeon_controls_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/engine/models.dart';
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

class _FixedSessions extends SessionsNotifier {
  _FixedSessions(this.systems);
  final List<String> systems;
  @override
  Future<SessionsState> build() async => SessionsState(
        active: 'default',
        sessions: [SessionMeta(id: 'default', name: 'M', systems: systems)],
      );
}

Future<void> _pump(WidgetTester t, {required bool hexcrawl}) async {
  SharedPreferences.setMockInitialValues({});
  await t.pumpWidget(ProviderScope(
    overrides: [
      hexcrawlDataProvider.overrideWith((ref) async => _hex()),
      sessionsProvider.overrideWith(
          () => _FixedSessions(hexcrawl ? ['juice', 'hexcrawl'] : ['juice'])),
    ],
    child: MaterialApp(home: Scaffold(body: DungeonMapPane(oracle: _oracle()))),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('dungeon hexcrawl controls appear when the flag is on', (t) async {
    await _pump(t, hexcrawl: true);
    expect(find.byKey(const Key('hexcrawl-generate-dungeon')), findsOneWidget);
  });

  testWidgets('dungeon hexcrawl controls hidden when the flag is off',
      (t) async {
    await _pump(t, hexcrawl: false);
    expect(find.byKey(const Key('hexcrawl-generate-dungeon')), findsNothing);
  });
}
```

- [ ] **Step 2: Run it** — Run: `flutter test test/hexcrawl_dungeon_controls_test.dart` → FAIL (key not found).

- [ ] **Step 3: Add the controls to `DungeonMapPaneState`** — in `lib/features/map_screen.dart`, add fields to `DungeonMapPaneState`:
```dart
  int _hcDungeonCount = 8;
```
add helper methods to the class:
```dart
  bool _hexcrawlOn() => (ref
              .watch(sessionsProvider)
              .valueOrNull
              ?.activeMeta
              .enabledSystems ??
          kAllSystems)
      .contains('hexcrawl');

  Future<void> _hcRoom() async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref.read(mapProvider.notifier).crawlDungeon(data, widget.oracle.dice);
  }

  Future<void> _hcDungeon() async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref
        .read(mapProvider.notifier)
        .generateDungeon(data, _hcDungeonCount, widget.oracle.dice);
  }

  Widget _hexcrawlDungeonControls(BuildContext context) {
    if (ref.watch(hexcrawlDataProvider).valueOrNull == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.tonal(
            key: const Key('hexcrawl-new-room'),
            onPressed: _hcRoom,
            child: const Text('New room (hexcrawl)'),
          ),
          FilledButton.tonal(
            key: const Key('hexcrawl-generate-dungeon'),
            onPressed: _hcDungeon,
            child: Text('Generate dungeon ($_hcDungeonCount)'),
          ),
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: () =>
                setState(() => _hcDungeonCount = (_hcDungeonCount - 2).clamp(4, 30)),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () =>
                setState(() => _hcDungeonCount = (_hcDungeonCount + 2).clamp(4, 30)),
          ),
        ],
      ),
    );
  }
```
and render it after `_controls(context, s)` in the Dungeon pane build:
```dart
            _controls(context, s),
            if (_hexcrawlOn()) _hexcrawlDungeonControls(context),
            Expanded(child: s.rooms.isEmpty ? _empty(context) : _canvas(s)),
```
(`kAllSystems`, `sessionsProvider`, `hexcrawlDataProvider`, `mapProvider`, `widget.oracle` are already available in `map_screen.dart`.)

- [ ] **Step 4: Run it** — Run: `flutter test test/hexcrawl_dungeon_controls_test.dart` → PASS. Run: `dart analyze lib/features/map_screen.dart` → No issues.

- [ ] **Step 5: Commit**
```bash
git add lib/features/map_screen.dart test/hexcrawl_dungeon_controls_test.dart
git commit -m "feat(hexcrawl): gated dungeon crawl/generate controls (H3)"
```

---

### Task 6: Full verification

- [ ] **Step 1: Full suite** — Run: `flutter test` → all pass.
- [ ] **Step 2: Analyze** — Run: `flutter analyze` → No issues found.

---

## Self-review

**Spec coverage:** 3 generic dungeon tables + self-verify (Task 1); `HexcrawlData` getters (Task 2); `rollDungeonRoom` (Task 3); `MapNotifier.crawlDungeon`/`generateDungeon` reusing `addRoom` (Task 4); gated Dungeon controls climate-free crawl + generate + size (Task 5). Out of scope (H4, encounters, game monsters) — no task. ✓

**Placeholder scan:** none.

**Type consistency:** `dungeonRoomTypes`/`dungeonContents`/`dungeonDressing` getters, `rollDungeonRoom(HexcrawlData, Dice) → ({title, detail})`, `MapNotifier.crawlDungeon(HexcrawlData, Dice)` / `generateDungeon(HexcrawlData, int, Dice)`, `_hexcrawlOn()`, `widget.oracle.dice`, keys `hexcrawl-new-room` / `hexcrawl-generate-dungeon` — consistent across tasks and matched to the real `addRoom`/`HexcrawlData`/`MapNotifier` APIs. (`DungeonMapPaneState` already has its own `_lonelogOn` from P4b — the new `_hexcrawlOn` is a distinct method; verify no name clash during execution and rename to `_hcOn` if needed.)
