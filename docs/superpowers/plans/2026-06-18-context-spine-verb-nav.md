# Context Spine + Verb Nav Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a `PlayContext` play-state spine and replace the 5-tab nav (Journal/Maps/Party/Tracking/Oracles) with 5 consolidated verbs (Journal/Sheet/Ask/Map/Track), reparenting existing panes without rewriting them.

**Architecture:** A pure `PlayContext` model (active character/scene/location) + a session-scoped `PlayContextNotifier` (key `juice.context.v1.<sessionId>`) mirror the existing `CrawlNotifier` persistence pattern. A `resolveSystem()` helper (sibling of `resolveSystemPrimer`) yields the active system key. The `Destination` enum is renamed to the 5 verbs; `Sheet` gains a new `SheetTab` (CharactersPane + Moves), `Track` absorbs the old Party subtabs, and `Ask` (the old OraclesTab) drops Moves and opens a system-aware default tab. Backward compatibility is out of scope (pre-release).

**Tech Stack:** Flutter, `flutter_riverpod` (`AsyncNotifierProvider`), `shared_preferences`, `package:flutter_test`.

---

## File Structure

**Create:**
- `lib/state/play_context.dart` — `PlayContextNotifier` + `playContextProvider`.
- `lib/features/sheet_tab.dart` — `SheetTab` (CharactersPane + optional Moves).
- `test/play_context_test.dart` — `LocationRef` + `PlayContext` model + `resolveSystem`.
- `test/play_context_persist_test.dart` — notifier persistence.
- `test/verb_nav_test.dart` — nav verb structure + relevance.

**Modify:**
- `lib/engine/models.dart` — add `LocationRef`, `PlayContext`, `EncounterState.locationRef`.
- `lib/engine/system_primer.dart` — add `resolveSystem()`.
- `lib/state/providers.dart` — `resolvedSystemProvider`; register `'juice.context.v1'` in `sessionScopedKeys`.
- `lib/shared/destination.dart` — rename enum + meta + `toolLocation`.
- `lib/shared/subtab_host.dart` — add `initialTabIndex`.
- `lib/shared/home_shell.dart` — `_visibleDestinations`, `_root`, body wiring.
- `lib/features/oracles_tab.dart` — drop Moves, add system-aware `initialTabIndex`, `destination: Destination.ask`.
- `lib/features/maps_tab.dart` — `destination: Destination.map`.
- `lib/features/tracking_tab.dart` — drop `npcs`/CharactersPane; absorb Party subtabs; `destination: Destination.track`.
- `lib/features/tracker_screen.dart` — CharactersPane sets/auto-opens `activeCharacter`.
- `lib/features/journal_screen.dart` — update `goTo` deep links.
- `CLAUDE.md` — project-notes entry.

**Delete:**
- `lib/features/party_tab.dart` — content relocated into `TrackingTab`.

---

### Task 1: LocationRef model

A reference to a place on the session's single `MapState` — either a dungeon room (`roomId`) or a hex (`hexCol`,`hexRow`). There is one map per session, so no `mapId`.

**Files:**
- Modify: `lib/engine/models.dart` (add near `MapState`, ~line 1749)
- Test: `test/play_context_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  group('LocationRef', () {
    test('room ref round-trips', () {
      const r = LocationRef(roomId: 'room-3');
      final back = LocationRef.fromJson(r.toJson());
      expect(back.roomId, 'room-3');
      expect(back.hexCol, isNull);
      expect(back.isEmpty, isFalse);
    });

    test('hex ref round-trips', () {
      const r = LocationRef(hexCol: 2, hexRow: 5);
      final back = LocationRef.fromJson(r.toJson());
      expect(back.hexCol, 2);
      expect(back.hexRow, 5);
      expect(back.roomId, isNull);
    });

    test('empty ref is empty', () {
      expect(const LocationRef().isEmpty, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/play_context_test.dart`
Expected: FAIL — `LocationRef` is not defined.

- [ ] **Step 3: Write minimal implementation**

Add to `lib/engine/models.dart` (just above `class MapState {`):

```dart
/// A reference to a place on the session's single map: a dungeon room id,
/// or a hex by (col,row). Empty when none set.
class LocationRef {
  const LocationRef({this.roomId, this.hexCol, this.hexRow});
  final String? roomId;
  final int? hexCol;
  final int? hexRow;

  bool get isEmpty => roomId == null && hexCol == null && hexRow == null;

  Map<String, dynamic> toJson() => {
        if (roomId != null) 'roomId': roomId,
        if (hexCol != null) 'hexCol': hexCol,
        if (hexRow != null) 'hexRow': hexRow,
      };

  factory LocationRef.fromJson(Map<String, dynamic> j) => LocationRef(
        roomId: j['roomId'] as String?,
        hexCol: (j['hexCol'] as num?)?.toInt(),
        hexRow: (j['hexRow'] as num?)?.toInt(),
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/play_context_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/play_context_test.dart
git commit -m "feat(context): LocationRef model (room | hex)"
```

---

### Task 2: PlayContext model

**Files:**
- Modify: `lib/engine/models.dart` (after `LocationRef`)
- Test: `test/play_context_test.dart`

- [ ] **Step 1: Write the failing test** (append a new group to the file from Task 1)

```dart
  group('PlayContext', () {
    test('defaults are all null', () {
      const c = PlayContext();
      expect(c.activeCharacterId, isNull);
      expect(c.activeSceneId, isNull);
      expect(c.activeLocation, isNull);
    });

    test('round-trips full state', () {
      const c = PlayContext(
        activeCharacterId: 'c1',
        activeSceneId: 's1',
        activeLocation: LocationRef(roomId: 'r1'),
      );
      final back = PlayContext.fromJson(c.toJson());
      expect(back.activeCharacterId, 'c1');
      expect(back.activeSceneId, 's1');
      expect(back.activeLocation?.roomId, 'r1');
    });

    test('round-trips empty state', () {
      final back = PlayContext.fromJson(const PlayContext().toJson());
      expect(back.activeCharacterId, isNull);
      expect(back.activeLocation, isNull);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/play_context_test.dart`
Expected: FAIL — `PlayContext` is not defined.

- [ ] **Step 3: Write minimal implementation**

Add to `lib/engine/models.dart` (just below `LocationRef`):

```dart
/// The play-state spine: what's "current" in the active campaign. Pointers
/// are nullable; null means no focus (consumers fall back to defaults).
class PlayContext {
  const PlayContext({
    this.activeCharacterId,
    this.activeSceneId,
    this.activeLocation,
  });
  final String? activeCharacterId;
  final String? activeSceneId;
  final LocationRef? activeLocation;

  Map<String, dynamic> toJson() => {
        if (activeCharacterId != null) 'activeCharacterId': activeCharacterId,
        if (activeSceneId != null) 'activeSceneId': activeSceneId,
        if (activeLocation != null) 'activeLocation': activeLocation!.toJson(),
      };

  factory PlayContext.fromJson(Map<String, dynamic> j) => PlayContext(
        activeCharacterId: j['activeCharacterId'] as String?,
        activeSceneId: j['activeSceneId'] as String?,
        activeLocation: j['activeLocation'] == null
            ? null
            : LocationRef.fromJson(
                Map<String, dynamic>.from(j['activeLocation'] as Map)),
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/play_context_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/play_context_test.dart
git commit -m "feat(context): PlayContext model"
```

---

### Task 3: resolveSystem() + resolvedSystemProvider

Mirror `resolveSystemPrimer`'s priority, but return the system KEY instead of primer text. Drives the `Ask` default and is the spine's "active system."

**Files:**
- Modify: `lib/engine/system_primer.dart` (add beside `resolveSystemPrimer`, ~line 32)
- Modify: `lib/state/providers.dart` (add beside `systemPrimerProvider`)
- Test: `test/play_context_test.dart`

- [ ] **Step 1: Write the failing test** (append group)

```dart
  group('resolveSystem', () {
    test('dnd wins over everything', () {
      expect(resolveSystem({'dnd', 'ironsworn'}, {'classic'}), 'dnd');
    });
    test('shadowdark before ironsworn family', () {
      expect(resolveSystem({'shadowdark', 'ironsworn'}, {}), 'shadowdark');
    });
    test('ironsworn family refined by ruleset', () {
      expect(resolveSystem({'ironsworn'}, {'sundered_isles'}), 'sundered_isles');
      expect(resolveSystem({'ironsworn'}, {'starforged'}), 'starforged');
      expect(resolveSystem({'ironsworn'}, {'classic'}), 'ironsworn');
    });
    test('nothing covered returns empty', () {
      expect(resolveSystem({'juice', 'mythic'}, {}), '');
    });
  });
```

Add the import at the top of `test/play_context_test.dart`:

```dart
import 'package:juice_oracle/engine/system_primer.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/play_context_test.dart`
Expected: FAIL — `resolveSystem` is not defined.

- [ ] **Step 3: Write minimal implementation**

Add to `lib/engine/system_primer.dart` (directly below `resolveSystemPrimer`):

```dart
/// The active system KEY, by the same priority as [resolveSystemPrimer]:
/// dnd > shadowdark > Ironsworn-family (sundered_isles > starforged > ironsworn).
/// Empty when no covered system is enabled.
String resolveSystem(Set<String> systems, Set<String> rulesets) {
  if (systems.contains('dnd')) return 'dnd';
  if (systems.contains('shadowdark')) return 'shadowdark';
  if (systems.contains('ironsworn')) {
    if (rulesets.contains('sundered_isles')) return 'sundered_isles';
    if (rulesets.contains('starforged')) return 'starforged';
    return 'ironsworn';
  }
  return '';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/play_context_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Add the provider**

In `lib/state/providers.dart`, directly below the existing `systemPrimerProvider` declaration, add:

```dart
final resolvedSystemProvider = Provider<String>((ref) {
  final systems =
      ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
          kAllSystems;
  final rulesets = ref.watch(rulesetsProvider).valueOrNull ?? const <String>{};
  return resolveSystem(systems, rulesets);
});
```

- [ ] **Step 6: Verify analyze + commit**

Run: `flutter analyze lib/engine/system_primer.dart lib/state/providers.dart test/play_context_test.dart`
Expected: No issues found.

```bash
git add lib/engine/system_primer.dart lib/state/providers.dart test/play_context_test.dart
git commit -m "feat(context): resolveSystem() + resolvedSystemProvider"
```

---

### Task 4: PlayContextNotifier + playContextProvider

Mirrors `CrawlNotifier` (singular session-scoped state). Place in a new file to keep `providers.dart` focused.

**Files:**
- Create: `lib/state/play_context.dart`
- Modify: `lib/state/providers.dart` (add `'juice.context.v1'` to `sessionScopedKeys`, ~line 969)
- Test: `test/play_context_persist_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/play_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('sets and persists the active character per session', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);

    await c.read(playContextProvider.future);
    await c.read(playContextProvider.notifier).setActiveCharacter('c1');
    expect(c.read(playContextProvider).valueOrNull?.activeCharacterId, 'c1');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('juice.context.v1.default'), isNotNull);
  });

  test('reload restores persisted context', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.context.v1.default': '{"activeSceneId":"s9"}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ctx = await c.read(playContextProvider.future);
    expect(ctx.activeSceneId, 's9');
  });

  test('setActiveCharacter(null) clears only that pointer', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.context.v1.default': '{"activeCharacterId":"c1","activeSceneId":"s1"}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(playContextProvider.future);
    await c.read(playContextProvider.notifier).setActiveCharacter(null);
    final ctx = c.read(playContextProvider).valueOrNull!;
    expect(ctx.activeCharacterId, isNull);
    expect(ctx.activeSceneId, 's1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/play_context_persist_test.dart`
Expected: FAIL — `play_context.dart` / `playContextProvider` not found.

- [ ] **Step 3: Write minimal implementation**

Create `lib/state/play_context.dart`:

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/models.dart';
import 'providers.dart';

class PlayContextNotifier extends AsyncNotifier<PlayContext> {
  static const _baseKey = 'juice.context.v1';
  late String _scopedKey;

  @override
  Future<PlayContext> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey);
    if (raw == null || raw.isEmpty) return const PlayContext();
    return PlayContext.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<PlayContext> get _ready async => state.valueOrNull ?? await future;

  Future<void> _save(PlayContext c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, jsonEncode(c.toJson()));
    state = AsyncData(c);
  }

  Future<void> setActiveCharacter(String? id) async {
    final c = await _ready;
    await _save(PlayContext(
      activeCharacterId: id,
      activeSceneId: c.activeSceneId,
      activeLocation: c.activeLocation,
    ));
  }

  Future<void> setActiveScene(String? id) async {
    final c = await _ready;
    await _save(PlayContext(
      activeCharacterId: c.activeCharacterId,
      activeSceneId: id,
      activeLocation: c.activeLocation,
    ));
  }

  Future<void> setActiveLocation(LocationRef? loc) async {
    final c = await _ready;
    await _save(PlayContext(
      activeCharacterId: c.activeCharacterId,
      activeSceneId: c.activeSceneId,
      activeLocation: loc,
    ));
  }
}

final playContextProvider =
    AsyncNotifierProvider<PlayContextNotifier, PlayContext>(
        PlayContextNotifier.new);
```

- [ ] **Step 4: Register the key for session cleanup**

In `lib/state/providers.dart`, add `'juice.context.v1',` to the `sessionScopedKeys` list (after `'juice.settings.v1',`):

```dart
const sessionScopedKeys = [
  'juice.journal.v2',
  'juice.log.v1', // legacy; kept so v1 campaign imports round-trip
  'juice.threads.v1',
  'juice.characters.v1',
  'juice.crawl.v1',
  'juice.encounter.v1',
  'juice.map.v1',
  'juice.verdant.v1',
  'juice.rumors.v1',
  'juice.tracks.v1',
  'juice.inventory.v1',
  'juice.units.v1',
  'juice.settings.v1',
  'juice.context.v1',
];
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/play_context_persist_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/state/play_context.dart lib/state/providers.dart test/play_context_persist_test.dart
git commit -m "feat(context): session-scoped PlayContextNotifier"
```

---

### Task 5: EncounterState.locationRef

**Files:**
- Modify: `lib/engine/models.dart` (`EncounterState`, lines 1513-1552)
- Test: `test/play_context_test.dart` (append group)

- [ ] **Step 1: Write the failing test**

```dart
  group('EncounterState.locationRef', () {
    test('absent decodes to null', () {
      final e = EncounterState.fromJson({'combatants': [], 'round': 1});
      expect(e.locationRef, isNull);
    });
    test('round-trips a room location', () {
      const e = EncounterState(locationRef: LocationRef(roomId: 'r2'));
      final back = EncounterState.fromJson(e.toJson());
      expect(back.locationRef?.roomId, 'r2');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/play_context_test.dart`
Expected: FAIL — `EncounterState` has no `locationRef`.

- [ ] **Step 3: Write minimal implementation**

Edit `EncounterState` in `lib/engine/models.dart` to add the field, constructor arg, copyWith arg, and JSON. Replace the class body with:

```dart
class EncounterState {
  const EncounterState({
    this.combatants = const [],
    this.turnIndex = 0,
    this.round = 1,
    this.locationRef,
  });
  final List<Combatant> combatants;
  final int turnIndex;
  final int round;
  final LocationRef? locationRef;

  EncounterState copyWith(
          {List<Combatant>? combatants,
          int? turnIndex,
          int? round,
          LocationRef? locationRef}) =>
      EncounterState(
        combatants: combatants ?? this.combatants,
        turnIndex: turnIndex ?? this.turnIndex,
        round: round ?? this.round,
        locationRef: locationRef ?? this.locationRef,
      );

  Map<String, dynamic> toJson() => {
        'combatants': combatants.map((c) => c.toJson()).toList(),
        'turnIndex': turnIndex,
        'round': round,
        if (locationRef != null) 'locationRef': locationRef!.toJson(),
      };

  factory EncounterState.fromJson(Map<String, dynamic> j) {
    final combatants = ((j['combatants'] as List?) ?? const [])
        .map((e) =>
            e is Map ? Combatant.fromJson(Map<String, dynamic>.from(e)) : null)
        .whereType<Combatant>()
        .toList();
    final maxTurn = combatants.isEmpty ? 0 : combatants.length - 1;
    return EncounterState(
      combatants: combatants,
      turnIndex: ((j['turnIndex'] as int?) ?? 0).clamp(0, maxTurn),
      round: (j['round'] as int?) ?? 1,
      locationRef: j['locationRef'] == null
          ? null
          : LocationRef.fromJson(
              Map<String, dynamic>.from(j['locationRef'] as Map)),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/play_context_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/play_context_test.dart
git commit -m "feat(context): EncounterState.locationRef (map link)"
```

---

### Task 6: SubtabHost.initialTabIndex

Lets a tab open on a system-relevant subtab.

**Files:**
- Modify: `lib/shared/subtab_host.dart` (lines 15-36)
- Test: `test/subtab_host_test.dart` (append)

- [ ] **Step 1: Write the failing test** (append inside the existing `main()`)

```dart
  testWidgets('opens on initialTabIndex', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: SubtabHost(
          destination: Destination.track,
          initialTabIndex: 1,
          tabs: [SubtabDef('a', 'A'), SubtabDef('b', 'B')],
          children: [Text('PANE-A'), Text('PANE-B')],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final controller = DefaultTabController.maybeOf(
        tester.element(find.byType(SubtabHost)));
    expect(find.text('B'), findsOneWidget);
  });
```

(If the existing test file already imports `Destination`, reuse it; this uses `Destination.track` from Task 7 — run this test only after Task 7's enum rename, or temporarily use an existing value. Sequence: implement Step 3 now, run the assertion after Task 7. For an immediately-runnable check, the analyze in Step 4 suffices.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/subtab_host_test.dart -n "initialTabIndex"`
Expected: FAIL — `initialTabIndex` is not a parameter.

- [ ] **Step 3: Write minimal implementation**

In `lib/shared/subtab_host.dart`, add the parameter + field to the constructor (after `this.scrollable = false,`):

```dart
class SubtabHost extends ConsumerStatefulWidget {
  const SubtabHost({
    super.key,
    required this.destination,
    required this.tabs,
    required this.children,
    this.scrollable = false,
    this.initialTabIndex = 0,
  });

  final Destination destination;
  final List<SubtabDef> tabs;
  final List<Widget> children;
  final bool scrollable;
  final int initialTabIndex;
```

And initialize the controller with it (lines 35-36 and the `didUpdateWidget` rebuild):

```dart
  late TabController _controller = TabController(
      length: widget.tabs.length,
      vsync: this,
      initialIndex:
          widget.initialTabIndex.clamp(0, widget.tabs.length - 1));
```

In `didUpdateWidget`, mirror the clamp when rebuilding:

```dart
      _controller = TabController(
          length: widget.tabs.length,
          vsync: this,
          initialIndex:
              widget.initialTabIndex.clamp(0, widget.tabs.length - 1));
```

- [ ] **Step 4: Verify analyze + commit**

Run: `flutter analyze lib/shared/subtab_host.dart`
Expected: No issues found.

```bash
git add lib/shared/subtab_host.dart test/subtab_host_test.dart
git commit -m "feat(nav): SubtabHost.initialTabIndex"
```

---

### Task 7: Rename Destination enum to the 5 verbs

Pure rename + remap. `journal` stays; `maps→map`, `oracles→ask`, `tracking→track`; `party` is removed and `sheet` added. The compiler is the safety net here.

**Files:**
- Modify: `lib/shared/destination.dart` (whole file)
- Modify: all reference sites (enumerated in Step 3)
- Test: `test/destination_test.dart`, `test/shell_route_test.dart`, `test/subtab_host_test.dart`, `test/tool_search_sheet_test.dart`, `test/journal_payload_ui_test.dart`, `test/home_shell_test.dart`

- [ ] **Step 1: Rewrite `lib/shared/destination.dart`**

```dart
import 'package:flutter/material.dart';

/// Top-level verbs of the home shell.
enum Destination { journal, sheet, ask, map, track }

class DestinationMeta {
  const DestinationMeta(this.label, this.icon);
  final String label;
  final IconData icon;
}

const destinationMeta = <Destination, DestinationMeta>{
  Destination.journal: DestinationMeta('Journal', Icons.book_outlined),
  Destination.sheet: DestinationMeta('Sheet', Icons.person_outline),
  Destination.ask: DestinationMeta('Ask', Icons.casino_outlined),
  Destination.map: DestinationMeta('Map', Icons.map_outlined),
  Destination.track: DestinationMeta('Track', Icons.checklist_outlined),
};

/// Registry tool id -> (destination, subtab key). Tools absent here have no
/// tab home (e.g. 'dice' lives on the entry line; 'help' opens as a route).
const toolLocation = <String, (Destination, String)>{
  'maps': (Destination.map, 'world'),
  'verdant': (Destination.map, 'journey'),
  'hexcrawl': (Destination.map, 'hexcrawl'),
  'party-emulator': (Destination.track, 'emulator'),
  'sidekick-dialogue': (Destination.track, 'sidekick'),
  'behavior-tables': (Destination.track, 'behavior'),
  'threads-characters': (Destination.sheet, 'characters'),
  'encounter': (Destination.track, 'encounter'),
  'resources': (Destination.track, 'resources'),
  'battle': (Destination.track, 'battle'),
  'fate-check': (Destination.ask, 'oracle'),
  'roll-high': (Destination.ask, 'oracle'),
  'mythic': (Destination.ask, 'oracle'),
  'gen-story': (Destination.ask, 'generators'),
  'gen-npcs': (Destination.ask, 'generators'),
  'gen-exploration': (Destination.ask, 'generators'),
  'gen-encounters': (Destination.ask, 'generators'),
  'gen-details': (Destination.ask, 'generators'),
  'tables': (Destination.ask, 'tables'),
  'lonelog-ref': (Destination.ask, 'lonelog'),
  'moves': (Destination.sheet, 'moves'),
};
```

- [ ] **Step 2: Run analyze to find every broken reference**

Run: `flutter analyze`
Expected: errors at the reference sites listed in Step 3. Use this list as the worklist.

- [ ] **Step 3: Update each reference site**

- `lib/features/maps_tab.dart:20` → `destination: Destination.map,`
- `lib/features/oracles_tab.dart:42` → `destination: Destination.ask,`
- `lib/features/tracking_tab.dart:25` → `destination: Destination.track,`
- `lib/features/journal_screen.dart:1188` → `.goTo(Destination.sheet, subtab: 'characters')`
- `lib/features/journal_screen.dart:1603` → `.goTo(Destination.track, subtab: 'threads')`
- `lib/features/journal_screen.dart:1612` → `.goTo(Destination.sheet, subtab: 'characters')`
- `test/destination_test.dart:6` → expect `(Destination.map, 'journey')`
- `test/destination_test.dart:7` → expect `(Destination.track, 'encounter')`
- `test/destination_test.dart:8` → expect `(Destination.ask, 'tables')`
- `test/destination_test.dart:9` → expect `(Destination.ask, 'generators')`
- `test/shell_route_test.dart:18` → `Destination.map`
- `test/shell_route_test.dart:34-35` → `Destination.track`
- `test/subtab_host_test.dart:12,45,55` → `Destination.track`
- `test/tool_search_sheet_test.dart:37` → `Destination.map`
- `test/journal_payload_ui_test.dart:181` → `Destination.ask`
- `test/home_shell_test.dart:109` → `Destination.ask`

(`lib/features/party_tab.dart:15` is deleted in Task 9; `lib/shared/home_shell.dart:303-323` is rewritten in Task 8 — leave those for now; analyze will still flag them until then.)

- [ ] **Step 4: Commit (compile may still fail until Task 8 — that's expected)**

```bash
git add lib/shared/destination.dart lib/features/maps_tab.dart lib/features/oracles_tab.dart lib/features/tracking_tab.dart lib/features/journal_screen.dart test/destination_test.dart test/shell_route_test.dart test/subtab_host_test.dart test/tool_search_sheet_test.dart test/journal_payload_ui_test.dart test/home_shell_test.dart
git commit -m "refactor(nav): rename Destination enum to 5 verbs"
```

---

### Task 8: SheetTab + home_shell verb wiring

Build the `Sheet` verb and rewire the shell body. CharactersPane leaves Track (Task 9) and lives here; Moves moves here for Ironsworn-family.

**Files:**
- Create: `lib/features/sheet_tab.dart`
- Modify: `lib/shared/home_shell.dart` (lines 303-327)
- Test: `test/verb_nav_test.dart`

- [ ] **Step 1: Write SheetTab**

Create `lib/features/sheet_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import 'moves_screen.dart';
import 'tracker_screen.dart';

/// The Sheet verb: the character roster, plus Moves for Ironsworn-family
/// campaigns. With no family active it is just the roster.
class SheetTab extends ConsumerWidget {
  const SheetTab({super.key, required this.family});
  final List<String> family;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (family.isEmpty) return const CharactersPane();
    return SubtabHost(
      destination: Destination.sheet,
      tabs: const [
        SubtabDef('characters', 'Characters'),
        SubtabDef('moves', 'Moves'),
      ],
      children: [
        const CharactersPane(),
        MovesScreen(rulesetIds: family),
      ],
    );
  }
}
```

- [ ] **Step 2: Rewire home_shell `_visibleDestinations` + `_root`**

In `lib/shared/home_shell.dart`, replace `_visibleDestinations` (303-311) and `_root` (313-327):

```dart
List<Destination> _visibleDestinations(
        Set<String> systems, List<String> family) =>
    const [
      Destination.journal,
      Destination.sheet,
      Destination.ask,
      Destination.map,
      Destination.track,
    ];

Widget _root(Destination d, Set<String> systems, List<String> family) {
  switch (d) {
    case Destination.journal:
      return const JournalScreen();
    case Destination.sheet:
      return SheetTab(family: family);
    case Destination.ask:
      return OraclesTab(
          oracle: widget.oracle, family: family, systems: systems);
    case Destination.map:
      return MapsTab(oracle: widget.oracle, systems: systems);
    case Destination.track:
      return TrackingTab(systems: systems);
  }
}
```

Add the import near the other feature imports in `home_shell.dart`:

```dart
import '../features/sheet_tab.dart';
```

(Note: `TrackingTab` gains a `systems` parameter in Task 9. If implementing strictly in order, temporarily use `const TrackingTab()` here and switch to `TrackingTab(systems: systems)` in Task 9.)

- [ ] **Step 3: Write the failing test**

Create `test/verb_nav_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/sheet_tab.dart';
import 'package:juice_oracle/features/tracker_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('SheetTab with no family renders the roster only',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': '[]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: SheetTab(family: [])))));
    await tester.pumpAndSettle();
    expect(find.byType(CharactersPane), findsOneWidget);
    expect(find.text('Characters'), findsNothing); // no subtab bar
  });
}
```

- [ ] **Step 4: Run test + analyze**

Run: `flutter test test/verb_nav_test.dart`
Expected: PASS.
Run: `flutter analyze lib/features/sheet_tab.dart lib/shared/home_shell.dart`
Expected: No issues (Task 9 may still flag `TrackingTab(systems:)` — see note).

- [ ] **Step 5: Commit**

```bash
git add lib/features/sheet_tab.dart lib/shared/home_shell.dart test/verb_nav_test.dart
git commit -m "feat(nav): Sheet verb (roster + Moves) + shell wiring"
```

---

### Task 9: Fold Party into Track; drop CharactersPane from Track

Track absorbs the old Party subtabs (Emulator/Sidekick/Behavior, gated by `party`) and loses the `npcs`/CharactersPane subtab (now in Sheet). `PartyTab` is deleted.

**Files:**
- Modify: `lib/features/tracking_tab.dart`
- Delete: `lib/features/party_tab.dart`
- Modify: `lib/shared/home_shell.dart` (remove the now-unused `PartyTab` import)
- Test: `test/verb_nav_test.dart` (append)

- [ ] **Step 1: Rewrite `TrackingTab`**

Replace `lib/features/tracking_tab.dart` body with (adds a `systems` param, drops `npcs`/CharactersPane, adds party + lonelog conditionals):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import '../state/providers.dart';
import 'behavior_tables_screen.dart';
import 'encounter_screen.dart';
import 'party_emulator_screen.dart';
import 'rumors_pane.dart';
import 'scenes_pane.dart';
import 'sidekick_screen.dart';
import 'tracker_screen.dart';
import 'tracks_pane.dart';

class TrackingTab extends ConsumerWidget {
  const TrackingTab({super.key, this.systems = kAllSystems});
  final Set<String> systems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lonelog = systems.contains('lonelog');
    final party = systems.contains('party');
    return SubtabHost(
      destination: Destination.track,
      scrollable: true,
      tabs: [
        const SubtabDef('scenes', 'Scenes'),
        const SubtabDef('threads', 'Threads'),
        const SubtabDef('rumors', 'Rumors'),
        const SubtabDef('tracks', 'Tracks'),
        const SubtabDef('encounter', 'Encounter'),
        if (party) const SubtabDef('emulator', 'Emulator'),
        if (party) const SubtabDef('sidekick', 'Sidekick'),
        if (party) const SubtabDef('behavior', 'Behavior'),
        if (lonelog) const SubtabDef('resources', 'Resources'),
        if (lonelog) const SubtabDef('battle', 'Battle'),
      ],
      children: [
        const ScenesPane(),
        const ThreadsPane(),
        const RumorsPane(),
        const TracksPane(),
        const EncounterScreen(),
        if (party) const PartyEmulatorScreen(),
        if (party) const SidekickScreen(),
        if (party) const BehaviorTablesScreen(),
        if (lonelog) const ResourcesPane(),
        if (lonelog) const BattlePane(),
      ],
    );
  }
}
```

(Verify the import list against the original `tracking_tab.dart` imports — `ThreadsPane`, `ResourcesPane`, `BattlePane` come from `tracker_screen.dart`/their existing files; keep whatever the original file imported for those, and add `party_emulator_screen.dart`, `sidekick_screen.dart`, `behavior_tables_screen.dart`. Remove the `npcs`/`CharactersPane` entry — CharactersPane is now only used by SheetTab.)

- [ ] **Step 2: Delete PartyTab + its import**

```bash
git rm lib/features/party_tab.dart
```

In `lib/shared/home_shell.dart`, remove the line `import '../features/party_tab.dart';` (the `PartyTab` reference was already removed in Task 8).

- [ ] **Step 3: Write the failing test** (append to `test/verb_nav_test.dart`)

```dart
  testWidgets('Track shows party subtabs only when party system is on',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["party"]}]}',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
                body: TrackingTab(systems: {'party'})))));
    await tester.pumpAndSettle();
    expect(find.text('Emulator'), findsOneWidget);
    expect(find.text('Scenes'), findsOneWidget);
  });
```

Add the import to the test file:

```dart
import 'package:juice_oracle/features/tracking_tab.dart';
```

- [ ] **Step 4: Run test + analyze**

Run: `flutter test test/verb_nav_test.dart`
Expected: PASS.
Run: `flutter analyze`
Expected: No issues found (all Destination references now resolved).

- [ ] **Step 5: Commit**

```bash
git add lib/features/tracking_tab.dart lib/shared/home_shell.dart test/verb_nav_test.dart
git commit -m "feat(nav): Track absorbs Party subtabs; CharactersPane moves to Sheet"
```

---

### Task 10: Ask opens a system-aware default tab

D&D/Shadowdark land on `Tables` (dice); everyone else on `Oracle`. Moves is gone from Ask (now in Sheet).

**Files:**
- Modify: `lib/features/oracles_tab.dart` (build, lines 23-46)
- Test: `test/verb_nav_test.dart` (append)

- [ ] **Step 1: Write the failing test** (append)

```dart
  testWidgets('Ask defaults to Tables for D&D', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["dnd"]}]}',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
                body: OraclesTab(
                    oracle: testOracle, family: const [], systems: const {'dnd'})))));
    await tester.pumpAndSettle();
    // Tables tab is selected: its pane content is visible.
    expect(find.text('Tables'), findsOneWidget);
  });
```

(Use the project's existing test `Oracle` fixture — see how `oracle_interpretation_sheet_test.dart` or `fate_screen_test.dart` build an `Oracle` from file fixtures; reuse that helper as `testOracle`. Per the rootBundle-hang note, do not call asset `.load()` in tests — build the `Oracle` from a fixture map.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/verb_nav_test.dart -n "Ask defaults"`
Expected: FAIL — Ask opens on Oracle, not Tables.

- [ ] **Step 3: Modify `OraclesTab.build`**

Replace the build method in `lib/features/oracles_tab.dart` (drop the Moves tab/child; compute `initialTabIndex`):

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lonelog = systems.contains('lonelog');
    final tabs = <SubtabDef>[
      const SubtabDef('oracle', 'Oracle'),
      const SubtabDef('generators', 'Generators'),
      const SubtabDef('tables', 'Tables'),
      if (lonelog) const SubtabDef('lonelog', 'Lonelog'),
    ];
    final children = <Widget>[
      FateScreen(oracle: oracle, initialSection: FateSection.fateCheck),
      GeneratorsScreen(oracle: oracle),
      TablesScreen(oracle: oracle),
      if (lonelog) const LonelogReferenceScreen(),
    ];
    final dice = systems.contains('dnd') || systems.contains('shadowdark');
    final initial = dice
        ? tabs.indexWhere((t) => t.key == 'tables')
        : 0;
    return SubtabHost(
      destination: Destination.ask,
      tabs: tabs,
      children: children,
      initialTabIndex: initial < 0 ? 0 : initial,
    );
  }
```

(`MovesScreen` import in `oracles_tab.dart` is now unused — remove it. `family` stays on the constructor since `home_shell` passes it; it is no longer used to add a Moves tab here. If analyze flags `family` as unused, keep the param but reference it in a doc comment, or drop it from the call site in `home_shell._root` and the constructor together.)

- [ ] **Step 4: Run test + analyze**

Run: `flutter test test/verb_nav_test.dart`
Expected: PASS.
Run: `flutter analyze lib/features/oracles_tab.dart`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add lib/features/oracles_tab.dart test/verb_nav_test.dart
git commit -m "feat(nav): Ask opens a system-aware default tab; Moves removed"
```

---

### Task 11: CharactersPane consumes + sets the active character

Tapping a character sets `activeCharacterId`; returning clears it; opening the pane auto-opens the focused character.

**Files:**
- Modify: `lib/features/tracker_screen.dart` (lines 124-168, 203, 404)
- Test: `test/verb_nav_test.dart` (append)

- [ ] **Step 1: Write the failing test** (append)

```dart
  testWidgets('opening a character sets the active character in context',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"c1","name":"Ash","stats":[],"tracks":[],"tags":[]}]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    expect(c.read(playContextProvider).valueOrNull?.activeCharacterId, 'c1');
  });
```

Add imports to the test file:

```dart
import 'package:juice_oracle/state/play_context.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/verb_nav_test.dart -n "active character in context"`
Expected: FAIL — activeCharacterId stays null.

- [ ] **Step 3: Wire the setters in `tracker_screen.dart`**

At the tap site (line 203), set context alongside local state:

```dart
              onTap: () {
                ref.read(playContextProvider.notifier).setActiveCharacter(c.id);
                setState(() => _editingId = c.id);
              },
```

In each sheet `onBack` (lines 145/151/157/163 and the generic sheet back at line 404), clear it:

```dart
                onBack: () {
                  ref.read(playContextProvider.notifier)
                      .setActiveCharacter(null);
                  setState(() => _editingId = null);
                },
```

Ensure `tracker_screen.dart` imports the provider:

```dart
import '../state/play_context.dart';
```

(Auto-open on build is optional polish; the spec's focus consumption is satisfied by set/clear. If adding it: after the `data: (chars) {` callback resolves, read `ref.watch(playContextProvider).valueOrNull?.activeCharacterId` and seed `_editingId` once if null and the id resolves to a real character. Keep it guarded so the user can still back out to the list.)

- [ ] **Step 4: Run test + the existing sheet suite (no regressions)**

Run: `flutter test test/verb_nav_test.dart test/character_sheet_ui_test.dart`
Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add lib/features/tracker_screen.dart test/verb_nav_test.dart
git commit -m "feat(context): CharactersPane sets the active character"
```

---

### Task 12: Full verify + docs

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze`
Expected: No issues found.
Run: `flutter test`
Expected: All tests passed.

- [ ] **Step 2: Update CLAUDE.md project notes**

Add a bullet under "## Project notes":

```markdown
- The **PlayContext spine** (`lib/state/play_context.dart`, model in
  `lib/engine/models.dart`) holds per-campaign focus pointers
  (`activeCharacterId` / `activeSceneId` / `activeLocation` as a `LocationRef`),
  persisted at `juice.context.v1.<sessionId>`. `resolveSystem(systems,
  rulesets)` (sibling of `resolveSystemPrimer`) yields the active system key;
  `resolvedSystemProvider` exposes it. The home shell uses 5 verbs —
  `Destination { journal, sheet, ask, map, track }`: Sheet = roster + Moves,
  Ask = oracles/generators/tables (system-aware default tab, no Moves), Map =
  maps/hexcrawl/verdant, Track = scenes/threads/rumors/tracks/encounter +
  Party (emulator/sidekick/behavior, gated by `party`). See
  `docs/superpowers/specs/2026-06-18-context-spine-verb-nav-design.md`.
  Deferred follow-ups: contextual generator distribution, assistant rail,
  GM/Party mode-switch, journal-as-canvas, formal party grouping.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(nav): document PlayContext spine + verb nav"
```

---

## Self-Review

**1. Spec coverage:**
- PlayContext (derived + stored) → Tasks 2, 3, 4. ✓
- Stored pointers persisted per campaign → Task 4 (+ session-key registration). ✓
- 5-verb nav replaces 5-tab → Tasks 7, 8, 9. ✓
- Sheet = CharactersPane + Moves → Task 8. ✓
- Track = scenes/threads/rumors/tracks/encounter + party → Task 9. ✓
- Ask default by resolvedSystem → Task 10. ✓
- Sub-option gating by enabledSystems → already shipped (sheet picker) + Task 9 (party/lonelog gating). ✓
- Encounter locationRef → Task 5. ✓
- Focus consumption (Sheet opens/sets focus char) → Task 11. ✓
- No backward compat → honored (no migration tasks). ✓
- Tests green / no regressions → Task 12. ✓

Gap noted: `activeScene` pinning in Scenes and `activeLocation` set-from-map are defined in the model/notifier (Tasks 2/4) but their UI wiring is light here — `setActiveScene`/`setActiveLocation` exist and are tested, but the Scenes-pane pin and map-tap hookup are deferred to the fast-follow (they need ScenesPane/Map internals not in scope for this foundation). This matches the spec's "minimal viable" framing; the spine + setters exist for the assistant-rail thread to consume.

**2. Placeholder scan:** No "TBD"/"implement later". Parenthetical notes give concrete fallbacks (e.g., `testOracle` fixture, ordering caveats), not vague directives.

**3. Type consistency:** `LocationRef{roomId,hexCol,hexRow}`, `PlayContext{activeCharacterId,activeSceneId,activeLocation}`, `EncounterState.locationRef`, `resolveSystem(Set,Set)→String`, `playContextProvider`, `SubtabHost.initialTabIndex`, `Destination{journal,sheet,ask,map,track}`, `SheetTab(family:)`, `TrackingTab(systems:)` — names match across all tasks.

**Ordering caveat:** Tasks 7→8→9 leave the tree non-compiling between commits (enum renamed before shell rewrite). This is intentional bite-sizing; `flutter analyze` is green again only after Task 9. If each commit must compile, execute 7+8+9 as one unit and commit once after Task 9's analyze passes.
