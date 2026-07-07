# Classic Dungeon P2 (Caves + A2 Effects + Multi-level) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete Roll 4 Ruin: the cave branch (tables D–F + I) with organic rendering, real A2/D2 dungeon-type effects (tier bump, treasure rolls, conditional stocking, crossover), and multi-level descent where depth drives the G2/G3/G4 monster tiers.

**Architecture:** Extends the shipped P1 rails in place — `build_dungeon.py` grows the cave/natural tables + `{lvl:*}` machine tokens; the pure engine (`lib/engine/dungeon/`) gains a `DungeonBranch`, depth→tier selection, a treasure roller, and level/crossover outputs; `MapState` gains `List<DungeonLevel>` with the P1 `rooms`/`corridors`/`currentRoomId` becoming views of the active level; the painter adds a deterministic wobbly-perimeter path for cave rooms.

**Tech Stack:** Dart/Flutter, `flutter_riverpod`, `shared_preferences`; Python 3 data rail. No new dependencies.

**Source spec:** `docs/superpowers/specs/2026-07-07-classic-dungeon-p2-caves-design.md`. P1 spec + plan live beside it (2026-07-06). Source PDF (cave tables pages 5–7, natural elements page 10):
`/Users/johntaylor/Library/Mobile Documents/com~apple~CloudDocs/Downloads/Roll4Ruin_2.1_NocturnalPeacock.pdf` — read with the `pages` parameter ONLY.

**P1 API facts (verified against merged code — do not re-derive):**
- `DungeonGenContext{level:int, effect:A2Type, tables, factions, roomId}` — P2 REPLACES `level` with `branch`/`depth`/`stone` (Task 4).
- `RoomResult{type, entryDoorKind, shapeFamily, detail, factions}` — P2 adds `levelDelta`, `crossoverTo`.
- `DungeonRoom{id,x,y,title,detail,status,footprint,doors,roomType}` (`models.dart:3126`); `roomType` currently `'corridor'|'chamber'|null`.
- `MapNotifier.addClassicRoom({fromRoomId, doorEdge, tables, effect, dice})` at `providers.dart:1020`; mints `id = _newId()` BEFORE `generateRoom`; persists via the notifier's public `save(MapState)`; `_ready` getter awaits state.
- `MapNotifier.resetDungeon()` clears rooms/corridors and the classic pane's reset also calls `dungeonFactionsProvider.notifier.reset()`.
- The classic pane (`lib/features/map_screen.dart`) holds the rolled `A2Type` in pane state `_effect` (P1 gap: ephemeral — P2 Task 5 persists it on the level and DELETES that pane state).
- Painter helpers: `cellRectFor(room, cell, minX, minY, cellSize)`, `doorMarkerCenter`, `doorEdgeAt`, `roomIdAt`; `_DungeonPainter` computes `_minX/_minY` over footprint extents.
- Conventions: `Dice.dN(n)`→1..n seeded via `Dice(Random(seed))`; format only files you edit; widget tests follow the rootBundle-hang recipe (override `oracleProvider`, `verdantDataProvider`, emulator/ruleset providers AND `dungeonDataProvider` with fixtures + `SharedPreferences.setMockInitialValues`).

---

## Task 1: Data rail — cave branch + `{lvl}` tokens + structured stocking effects

**Files:**
- Modify: `build_dungeon.py`
- Regenerate: `assets/dungeon_data.json`

- [ ] **Step 1: Transcribe the cave tables from PDF pages 5–7 + 10** into `build_dungeon.py`, same literal style as the dungeon tables:
  - `D1` (D12 cave entrance; row 12 = "Roll again" like A1's).
  - `D2` (2D6 cave type) — same structured-effect schema as A2. Encode: `"2" Crystal Caves`, `"3" Icy tubes`, `"4" Dungeon Entrance {"leads_to_dungeon": true}`, `"5" Old Mine`, `"6" Grotto`, `"7" Natural Cave`, `"8" Blooming Cavern`, `"9" Outpost {"monster_die": 20}`, `"10" Beast Lair {"tier_bump": 1, "vein_bonus": 3}`, `"11" Magma Tubes`, `"12" Alien Hive` (note-only). Per-type "on a 6" conditions use the `on_stock_6` mechanism below.
  - `E2`/`F2` (D6 stocking), `E3`/`F3`/`E4`/`F4` (D20), `E5` (D10 cavestone), `F5` (D6 re-stock).
  - `I1`–`I8` in full (secret cave, arcane occurrences, vein — 18 rows, cave curio, interventions, flora, liquid, gas). Remove the now-shipped ids from `LABEL_FALLBACKS` (keep only genuinely unshipped refs, e.g. `D1` if referenced).
  - `tunnel_families` / `cave_families`: d66 range maps whose family ids are EXACTLY the existing corridor/chamber family ids (tunnels reuse corridor footprints, caves reuse chamber footprints).
- [ ] **Step 2: Add `{lvl:...}` machine tokens** to the level-transition/crossover rows, replacing prose-only markers: `{lvl:down}` (one down), `{lvl:updown}` (D6 1–5 down/6 up — C3 stairs row, F3 slope row), `{lvl:chasm}` (down D4 — F4 chasm, C4 hole), `{lvl:cross}` (branch crossover — C4 "Door to cave-system", F4 "Doors to dungeon"). Keep the human text beside the token (the generator strips tokens from display).
- [ ] **Step 3: Restructure conditional type effects as `on_stock_6`.** A2/D2 entries whose PDF text is "if you roll a 6 on B2/C2/E2/F2 …" gain `"on_stock_6": "<row text with {ref}s>"` (e.g. A2-5 Overgrown ruins → `"D4 Flora {ref:I6} & fauna {ref:G7}"`, A2-6 Catacombs → `"D4 burial alcoves {ref:H1}"`, A2-8 Stronghold → `"A barricade"`, A2-9 Temple → `"1/6 chance: shrine {ref:H6}"` → encode as `"Shrine {ref:H6} (1/6 intact)"` — keep it a plain row, the 1/6 is flavor; A2-11 Transformed → `"{lvl:cross}Openings lead to caves"`, A2-12 Ancient → `"An obstacle {ref:E4}"`; D2 per its column). Keep the display `note` too (de-tokenized by the UI).
- [ ] **Step 4: Extend `verify()`**: D1=12; D2 keys 2..12; E2/F2/F5=6; E3/E4/F3/F4=20; E5=10; I-table row counts per the PDF (I3=18; count the others during transcription and assert what you shipped); `tunnel_families`/`cave_families` d66-covered AND every family id exists in the corridor/chamber family key sets; every `{lvl:X}` token has `X ∈ {down, updown, chasm, cross}` (regex scan over the whole data dict); the existing all-tables `{ref}` scan still passes.
- [ ] **Step 5: Run + ship**: `python3 build_dungeon.py` → `self-check OK`; `cp dungeon_data.json assets/`.
- [ ] **Step 6: Commit**
```bash
git add build_dungeon.py assets/dungeon_data.json
git commit -m "feat(dungeon): cave-branch tables D-F/I, {lvl} tokens, on_stock_6 effects"
```

## Task 2: Loader — cave getters + effect fields

**Files:**
- Modify: `lib/engine/dungeon/tables.dart`
- Test: `test/dungeon/tables_test.dart` (extend)

- [ ] **Step 1: Extend the failing test** in `test/dungeon/tables_test.dart`:
```dart
  test('parses the cave branch', () {
    final raw = File('assets/dungeon_data.json').readAsStringSync();
    final t = DungeonTables.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    expect(t.d1.length, 12);
    expect(t.d2['7']!.name, 'Natural Cave');
    expect(t.d2['10']!.tierBump, 1);
    expect(t.d2['10']!.veinBonus, 3);
    expect(t.d2['4']!.leadsToDungeon, isTrue);
    expect(t.e2.length, 6);
    expect(t.f2.length, 6);
    expect(t.cavestone.length, 10);
    expect(t.tunnelFamilies.keys.toSet(),
        t.corridorFamilies.keys.toSet()); // families reuse corridor ids
    expect(t.caveFamilies.keys.toSet(), t.chamberFamilies.keys.toSet());
    expect(t.a2['5']!.onStock6, contains('{ref:I6}'));
  });
```
- [ ] **Step 2: Run, expect FAIL** (`flutter test test/dungeon/tables_test.dart`).
- [ ] **Step 3: Implement.** In `A2Type` add `final String onStock6;` (JSON `on_stock_6`, default `''`), `final int veinBonus;` (`vein_bonus`, 0), `final bool leadsToDungeon;` (`leads_to_dungeon`, false), `final int monsterDie;` (`monster_die`, 0 = table default). D2 rows parse as `A2Type` too (one class serves both — rename NOT needed; add a doc note). `DungeonTables` gains `d1`, `d2` (Map<String,A2Type>), `e2`, `f2`, `cavestone` (E5), `tunnelFamilies`, `caveFamilies` — all parsed tolerantly like the P1 fields (`_strs`/`_fam` helpers exist).
- [ ] **Step 4: Run, expect PASS.** `flutter analyze lib/engine/dungeon/tables.dart` clean; `dart format` it.
- [ ] **Step 5: Commit**
```bash
git add lib/engine/dungeon/tables.dart test/dungeon/tables_test.dart
git commit -m "feat(dungeon): loader for cave tables + structured effect fields"
```

## Task 3: Treasure roller (pure)

**Files:**
- Create: `lib/engine/dungeon/treasure.dart`
- Test: `test/dungeon/treasure_test.dart`

- [ ] **Step 1: Write the failing test**
```dart
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/dungeon/treasure.dart';

void main() {
  const h8 = {
    'form_d4': ['Coins', 'Coins', 'D6 items', 'D4 gems'],
    'd10_plus_level': [
      'D6 SP', '2D6 SP', 'D6 GP', 'D6*5 GP', 'D6*10 GP', '2D6*10 GP',
      'D6*25 GP', '2D6*25 GP', 'D6*50 GP', 'Artifact +1 & 2D6*50 GP',
      'D6*100 GP', 'Artifact +1 & D6*100 GP', '2D6*100 GP',
      'Artifact +2 & D6*250 GP', 'D6*250 GP', 'Artifact +2 & D6*500 GP',
      '2D6*1000 GP', 'Artifact +3 & D6*5000 GP',
    ],
  };

  test('resolves dice notation to an amount, row picked by d10+depth-1+bonus',
      () {
    final r = rollTreasure(h8, depth: 1, bonus: 0, dice: Dice(Random(1)));
    // "Treasure: <N> GP/SP (<row text>, <form>)" — amount is numeric
    expect(r, matches(RegExp(r'Treasure: \d+ (GP|SP)')));
  });

  test('bonus shifts the row and the index clamps to the table', () {
    // depth 9 + bonus 30 forces past the end -> clamps to the last row
    final r = rollTreasure(h8, depth: 9, bonus: 30, dice: Dice(Random(2)));
    expect(r, contains('Artifact +3'));
  });

  test('unparseable row falls back to the raw text', () {
    const weird = {
      'form_d4': ['Coins', 'Coins', 'Coins', 'Coins'],
      'd10_plus_level': List<String>.filled(18, 'A mysterious boon'),
    };
    final r = rollTreasure(weird, depth: 1, bonus: 0, dice: Dice(Random(1)));
    expect(r, contains('A mysterious boon'));
  });
}
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement `lib/engine/dungeon/treasure.dart`:**
```dart
/// Rolls the H8 treasure table: d4 form + one row of the 18-row value ladder
/// at index `d10 + depth - 1 + bonus` (1-based, clamped), resolving embedded
/// `NdX(*k)` notation (e.g. "2D6*25 GP") to a concrete amount. Pure.
library;

import '../dice.dart';

final _dicePart = RegExp(r'^(\d*)[dD](\d+)(?:\*(\d+))?\s+(GP|SP)$');

String rollTreasure(Map<String, dynamic> h8,
    {required int depth, required int bonus, required Dice dice}) {
  final forms = (h8['form_d4'] as List? ?? const []);
  final rows = (h8['d10_plus_level'] as List? ?? const []);
  if (rows.isEmpty) return 'Treasure';
  final form = forms.isEmpty
      ? ''
      : forms[dice.dN(forms.length) - 1].toString();
  final idx = (dice.dN(10) + depth - 1 + bonus).clamp(1, rows.length);
  final row = rows[idx - 1].toString();

  // Try to resolve the trailing "<dice> GP" part; artifacts keep their prefix.
  final parts = row.split('&').map((p) => p.trim()).toList();
  final resolved = <String>[];
  var numeric = false;
  for (final p in parts) {
    final m = _dicePart.firstMatch(p);
    if (m == null) {
      resolved.add(p);
      continue;
    }
    final n = int.tryParse(m.group(1) ?? '') ?? 1;
    final sides = int.parse(m.group(2)!);
    final mult = int.tryParse(m.group(3) ?? '') ?? 1;
    var total = 0;
    for (var i = 0; i < n; i++) {
      total += dice.dN(sides);
    }
    resolved.add('${total * mult} ${m.group(4)}');
    numeric = true;
  }
  final suffix = form.isEmpty ? row : '$row, $form';
  return numeric
      ? 'Treasure: ${resolved.join(' & ')} ($suffix)'
      : 'Treasure: $row${form.isEmpty ? '' : ' ($form)'}';
}
```
- [ ] **Step 4: Run, expect PASS.** Analyze + format.
- [ ] **Step 5: Commit**
```bash
git add lib/engine/dungeon/treasure.dart test/dungeon/treasure_test.dart
git commit -m "feat(dungeon): pure H8 treasure roller (depth+bonus ladder, dice notation)"
```

## Task 4: Generator — branch, depth→tier, `{lvl}` tokens, crossover, `on_stock_6`, real treasure

**Files:**
- Modify: `lib/engine/dungeon/generator.dart`
- Test: `test/dungeon/generator_test.dart` (extend; update ALL existing `DungeonGenContext` call sites)

- [ ] **Step 1: Extend the failing tests.** Update the test fixture builder to add the cave keys (`D1`, `D2`, `E2`, `F2`, `E5`, `tunnel_families`, `cave_families`, `G3`, `G4` single-row monster tables) and change every existing `DungeonGenContext(level: 1, …)` to the new shape. New tests:
```dart
  test('cave branch: type die 1-3 tunnel / 4-6 cave, stocking from E2/F2', () {
    for (var s = 0; s < 30; s++) {
      final r = generateRoom(
          DungeonGenContext(
              branch: DungeonBranch.cave, depth: 1, stone: 'Basalt',
              roomId: 'r', effect: const A2Type(name: 'x'),
              tables: _tables(), factions: const FactionRegistry()),
          Dice(Random(s)));
      expect(r.type, anyOf(RoomType.tunnel, RoomType.cave));
    }
  });

  test('depth picks the tier: depth 3 rolls G3, tierBump caps at G4', () {
    // fixture G2/G3/G4 each hold one uniquely-named monster; force monster
    // stocking rows and assert the name matches the tier.
    // depth 3, bump 0 -> G3 monster name appears in detail.
    // depth 5, bump 1 -> still G4 (cap).
  });

  test('{lvl:updown} yields levelDelta ±1 and strips the token from detail', () {
    // fixture C3 single row "Stairs {lvl:updown}" + stocking forcing Feature C3
    // -> r.levelDelta is -1 or 1 (d6), detail contains "Stairs", not "{lvl:".
  });

  test('{lvl:cross} sets crossoverTo the other branch', () {
    // dungeon-branch room rolling the cross row -> r.crossoverTo == DungeonBranch.cave
  });

  test('on_stock_6: stocking 6 expands the type effect row', () {
    // effect A2Type(onStock6: 'D4 burial alcoves {ref:H1}'); loop seeds until
    // the stock die rolls 6 -> detail contains 'burial alcoves a coffin'
    // (H1 dict label), not 'Nothing'.
  });

  test('treasure stocking rolls real H8 GP', () {
    // C2 fixture row 'Treasure {ref:H8}' + full 18-row H8 fixture ->
    // detail matches RegExp(r'Treasure: \d+ (GP|SP)').
  });
```
Write these as REAL tests (the seed-loop pattern from the P1 suite — loop `s < 50`, assert on first hit, `fail()` if none).
- [ ] **Step 2: Run, expect FAIL** (missing `DungeonBranch`, new context shape).
- [ ] **Step 3: Implement in `generator.dart`:**
  - `enum DungeonBranch { dungeon, cave }`; `RoomType` gains `tunnel`, `cave`; `branchOfRoomType(String?)` helper (corridor/chamber/null → dungeon; tunnel/cave → cave).
  - `DungeonGenContext`: replace `level` with `required DungeonBranch branch`, `required int depth`, `String stone = ''`. (`roomId`, `effect`, `tables`, `factions` unchanged.)
  - Type die: dungeon branch as P1; cave branch maps 1–3 → `RoomType.tunnel`, 4–6 → `RoomType.cave` with the same door kinds. Family range map/catalog: tunnel → `tables.tunnelFamilies` + `kCorridorShapes`; cave → `tables.caveFamilies` + `kChamberShapes`. Stocking: tunnel → `tables.e2`, cave → `tables.f2` (dungeon unchanged b2/c2).
  - Tier: `List<MonsterRow> _tierFor(tables, depth, bump)` — tier index `((depth + 1) ~/ 2).clamp(1, 3) + bump` clamped 1..3 → G2/G3/G4 parsed from `raw['G3']`/`raw['G4']` with the same `MonsterRow.fromJson` (add `centralMonsters`/`deepMonsters` getters to `DungeonTables` OR parse from raw here — prefer loader getters, mirroring `upperMonsters`; add them in this task, they're 3 lines each). `effect.monsterDie` (Outpost/Forgotten-ruins) picks d12 vs d20 row range: roll `dice.dN(min(monsterDie == 0 ? rows.length : monsterDie, rows.length))`.
  - `{lvl:X}` handling: scan the EXPANDED stocking text for `RegExp(r'\{lvl:(down|updown|chasm|cross)\}')` (the token survives `_expand` — refs and lvl tokens are disjoint syntaxes); resolve: down → −1; updown → `dice.dN(6) == 6 ? 1 : -1`; chasm → `-dice.dN(4)`; cross → set `crossoverTo` = other branch. Strip all `{lvl:*}` tokens from the display text. Also honor `effect.leadsToCaves`/`effect.leadsToDungeon` + `onStock6` (below).
  - `on_stock_6`: when the stocking die rolled 6 AND `effect.onStock6.isNotEmpty`, expand `effect.onStock6` (through `_expand`, then `{lvl}` scan) instead of the "Nothing (or Type effect)" row.
  - Treasure: wherever the expanded stocking text still contains the H8 label path — change the `_dictRefLabels` H8 entry handling: in `_expand`, intercept `id == 'H8'` BEFORE the dict-label fallback and return `rollTreasure(t.raw['H8'] as Map<String, dynamic>, depth: _depth, bonus: _bonus, dice: dice)`. Thread depth/bonus via top-level fields set at `generateRoom` entry (file-private mutable statics are forbidden — instead make `_expand` a method of a small `_Expander` class holding `{tables, dice, depth, bonus}`; refactor the existing free function into it, keeping `stripRefTokens` top-level).
  - `RoomResult`: add `final int levelDelta;` (default 0) and `final DungeonBranch? crossoverTo;`.
- [ ] **Step 4: Run the full dungeon suite** (`flutter test test/dungeon/`), expect PASS incl. all P1 tests (updated call sites). Analyze + format.
- [ ] **Step 5: Commit**
```bash
git add lib/engine/dungeon/generator.dart lib/engine/dungeon/tables.dart test/dungeon/generator_test.dart
git commit -m "feat(dungeon): cave branch, depth tiers, lvl tokens, on_stock_6, real treasure"
```

## Task 5: Multi-level model — `DungeonLevel` + `MapState.levels`

**Files:**
- Modify: `lib/engine/models.dart` (`DungeonLevel` new class; `MapState` + `DungeonRoom`)
- Test: `test/dungeon/level_model_test.dart`

- [ ] **Step 1: Write the failing test**
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('P1-shape JSON (bare rooms) loads as one depth-1 dungeon level', () {
    final s = MapState.fromJson({
      'rooms': [
        {'id': 'a', 'x': 0, 'y': 0, 'title': 'T'}
      ],
      'corridors': <dynamic>[],
      'currentRoomId': 'a',
    });
    expect(s.levels, hasLength(1));
    expect(s.levels.first.depth, 1);
    expect(s.rooms.single.id, 'a'); // active-level view
    expect(s.currentRoomId, 'a');
  });

  test('levels round-trip with meta and active index', () {
    const lvl1 = DungeonLevel(
        depth: 1, branch: 'dungeon', typeName: 'Ruins', note: '', stone: '',
        rooms: [DungeonRoom(id: 'a', x: 0, y: 0, title: 'T')],
        corridors: [], currentRoomId: 'a');
    const lvl2 = DungeonLevel(
        depth: 2, branch: 'cave', typeName: 'Grotto', note: 'n', stone: 'Basalt',
        rooms: [], corridors: [], currentRoomId: null);
    final s = MapState(levels: const [lvl1, lvl2], activeLevel: 1);
    final back = MapState.fromJson(s.toJson());
    expect(back.levels[1].stone, 'Basalt');
    expect(back.activeLevel, 1);
    expect(back.rooms, isEmpty); // views follow the ACTIVE level (index 1)
    expect(back.levelAt(2)!.typeName, 'Grotto');
  });

  test('DungeonRoom levelDelta + crossTo round-trip and default off', () {
    const r = DungeonRoom(id: 'a', x: 0, y: 0, title: 'T');
    expect(DungeonRoom.fromJson(r.toJson()).levelDelta, 0);
    const d = DungeonRoom(
        id: 'b', x: 0, y: 0, title: 'S', levelDelta: -1, crossTo: 'cave');
    final back = DungeonRoom.fromJson(d.toJson());
    expect(back.levelDelta, -1);
    expect(back.crossTo, 'cave');
  });
}
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
  - `DungeonRoom`: add `final int levelDelta;` (default 0, JSON `ld`, omitted at 0) and `final String? crossTo;` (JSON `xt`, omitted when null); thread through `copyWith`/`toJson`/`fromJson`.
  - `DungeonLevel` (new, beside `MapState`): `{int depth, String branch, String typeName, String note, String stone, List<DungeonRoom> rooms, List<List<String>> corridors, String? currentRoomId}` + `copyWith` + tolerant JSON (`toJson`/`fromJson`).
  - `MapState`: replace the stored `rooms`/`corridors`/`currentRoomId` fields with `final List<DungeonLevel> levels; final int activeLevel;` and expose the P1 names as GETTERS over `levels.isEmpty ? const [] : levels[activeLevel.clamp(0, levels.length - 1)]`. `copyWith` keeps accepting `rooms`/`corridors`/`currentRoomId`/`clearCurrentRoomId` and applies them to the active level (creating a default depth-1 dungeon level when `levels` is empty) — so every P1 call site (`addRoom`, hexcrawl `crawlDungeon`, linger, status, resetDungeon) keeps compiling unchanged. Add `copyWith` params `levels`, `activeLevel`. `toJson`: emit `levels` + `activeLevel` (+ hex fields unchanged); `fromJson`: parse `levels` when present, else lift bare `rooms`/`corridors`/`currentRoomId` into a single `DungeonLevel(depth: 1, branch: 'dungeon', typeName: '', note: '', stone: '')`. Add `DungeonLevel? levelAt(int depth)`.
- [ ] **Step 4: Run the new test + the P1 suite** (`flutter test test/dungeon/ test/map_builder_test.dart` and any existing map tests — find them with `ls test/ | grep -i map`), expect PASS. Analyze + format.
- [ ] **Step 5: Commit**
```bash
git add lib/engine/models.dart test/dungeon/level_model_test.dart
git commit -m "feat(dungeon): DungeonLevel model — MapState levels with active-level views"
```

## Task 6: Notifier — level lifecycle + branch-aware `addClassicRoom`

**Files:**
- Modify: `lib/state/providers.dart` (`MapNotifier`)
- Test: `test/dungeon/level_notifier_test.dart`

- [ ] **Step 1: Write the failing test** (container + mock prefs + the shipped `dungeon_data.json`, same setup as `test/dungeon/add_classic_room_test.dart` — read that file and mirror its scaffolding):
  - `enterClassicDungeon(branch: cave)` creates level 1 with `branch 'cave'`, non-empty `typeName`, non-empty `stone`, one entrance room whose `roomType` is `tunnel|cave`.
  - `descendFrom(roomId)` on a room with `levelDelta: -1` creates depth 2 (same branch), switches `activeLevel`, rolls an entrance room; calling it again from depth 2's up-stairs room (levelDelta +1 fixture) switches BACK without creating a duplicate depth-1.
  - `switchLevel(depth)` flips `activeLevel` without mutating rooms.
  - `addClassicRoom` on a cave level produces tunnel/cave rooms; on a room with `crossTo: 'cave'`, the child generates on the cave branch (roomType tunnel/cave).
  - `resetDungeon()` clears `levels`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement in `MapNotifier`:**
  - `Future<void> enterClassicDungeon({required DungeonBranch branch, required DungeonTables tables, required Dice dice})` — rolls A1/A2 (dungeon) or D1/D2 (cave) + E5 stone for caves; creates `DungeonLevel(depth: 1, branch: branch.name, typeName: type.name, note: stripRefTokens(type.note), stone: …)`, sets `levels: [level], activeLevel: 0`, then generates + places the entrance room via the shared internals of `addClassicRoom` (extract the generate+place tail into a private `_placeClassicRoom({fromRoomId, doorEdge, tables, effect, dice})` both call; the effect for generation comes from the LEVEL's stored type — add a small `A2Type _effectOfLevel(DungeonLevel, DungeonTables)` resolving by typeName from `a2`/`d2`, falling back to `A2Type(name: typeName)`).
  - `addClassicRoom` drops its `effect` parameter (now level-derived) and gains nothing else; it reads the active level for `branch`/`depth`/`stone`, and the PARENT room's `crossTo` (when `fromRoomId` non-null) to flip the child branch. It stores `levelDelta`/`crossTo` (`crossoverTo?.name`) from `RoomResult` onto the new `DungeonRoom`.
  - `Future<void> descendFrom(String roomId, {required DungeonTables tables, required Dice dice})` — reads the room's `levelDelta`; target `depth = level.depth + delta` (min 1); if `levelAt(target)` exists → set `activeLevel` to its index; else create it (same branch; caves re-roll `stone`; `typeName`/`note` copied from the origin level — one dungeon, one type) + entrance room, and switch.
  - `Future<void> switchLevel(int depth)` — index lookup + `save(s.copyWith(activeLevel: i))`.
  - `resetDungeon()` → also `levels: const [], activeLevel: 0` (read its current body first; keep hex-preserving behavior).
  - Update the ONE existing `addClassicRoom` caller (`map_screen.dart`) mechanically so the tree compiles — full UI rework is Task 8; here just delete the `effect:` argument and route Enter through `enterClassicDungeon(branch: DungeonBranch.dungeon, …)`, deleting the pane `_effect` state and its A1/A2 rolling (now notifier-side).
- [ ] **Step 4: Run** `flutter test test/dungeon/` + `flutter analyze lib/` — PASS/clean. Format.
- [ ] **Step 5: Commit**
```bash
git add lib/state/providers.dart lib/features/map_screen.dart test/dungeon/level_notifier_test.dart
git commit -m "feat(dungeon): level lifecycle — enter/descend/switch, level-derived effects"
```

## Task 7: Organic cave paint (pure path + painter)

**Files:**
- Create: `lib/engine/dungeon/organic.dart`
- Modify: `lib/features/map_screen.dart` (`_DungeonPainter`)
- Test: `test/dungeon/organic_test.dart`

- [ ] **Step 1: Write the failing test**
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dungeon/organic.dart';

void main() {
  test('perimeter of a 2x1 footprint is a closed jittered loop', () {
    final pts = organicPerimeter(const [(0, 0), (0, 1)], seed: 42,
        cellSize: 56, jitter: 5);
    expect(pts.length, greaterThan(8)); // subdivided edges
    expect(pts.first, pts.last); // closed
  });

  test('deterministic for the same seed, different for another', () {
    final a = organicPerimeter(const [(0, 0)], seed: 7, cellSize: 56, jitter: 5);
    final b = organicPerimeter(const [(0, 0)], seed: 7, cellSize: 56, jitter: 5);
    final c = organicPerimeter(const [(0, 0)], seed: 8, cellSize: 56, jitter: 5);
    expect(a, b);
    expect(a, isNot(c));
  });

  test('jitter never exceeds the bound', () {
    final pts = organicPerimeter(const [(0, 0)], seed: 3, cellSize: 56, jitter: 4);
    for (final p in pts) {
      expect(p.$1, inInclusiveRange(-4.0, 60.0));
      expect(p.$2, inInclusiveRange(-4.0, 60.0));
    }
  });
}
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement `organic.dart`** (pure, no Flutter — emits `(double,double)` records; the painter converts to `Offset`/`Path`):
```dart
/// Deterministic wobbly perimeter for cave rooms: walks the outer boundary of
/// a fused cell footprint, subdivides each edge, and jitters interior points
/// with a seeded PRNG so repaints are stable. Pure.
library;

import 'dart:math';

/// Ordered closed loop (first == last) of jittered points around [cells]
/// (unit-cell offsets), scaled by [cellSize]. Corner points keep at most
/// [jitter]/2 displacement; midpoints up to [jitter].
List<(double, double)> organicPerimeter(List<(int, int)> cells,
    {required int seed, required double cellSize, required double jitter}) {
  final cellSet = cells.toSet();
  // Collect boundary edges as directed segments (cell side with no neighbor).
  final segs = <((int, int), (int, int))>[];
  for (final c in cellSet) {
    final (x, y) = c;
    if (!cellSet.contains((x, y - 1))) segs.add(((x, y), (x + 1, y)));
    if (!cellSet.contains((x + 1, y))) segs.add(((x + 1, y), (x + 1, y + 1)));
    if (!cellSet.contains((x, y + 1))) segs.add(((x + 1, y + 1), (x, y + 1)));
    if (!cellSet.contains((x - 1, y))) segs.add(((x, y + 1), (x, y)));
  }
  // Chain segments into a loop (grid corners as nodes).
  final byStart = {for (final s in segs) s.$1: s};
  final loop = <(int, int)>[];
  var cur = segs.first;
  do {
    loop.add(cur.$1);
    cur = byStart[cur.$2]!;
  } while (cur.$1 != segs.first.$1);
  loop.add(loop.first);

  final rng = Random(seed);
  double j(double range) => (rng.nextDouble() * 2 - 1) * range;
  final out = <(double, double)>[];
  for (var i = 0; i < loop.length - 1; i++) {
    final a = loop[i], b = loop[i + 1];
    final ax = a.$1 * cellSize, ay = a.$2 * cellSize;
    final bx = b.$1 * cellSize, by = b.$2 * cellSize;
    out.add((ax + j(jitter / 2), ay + j(jitter / 2)));
    for (final t in const [0.33, 0.66]) {
      out.add((ax + (bx - ax) * t + j(jitter), ay + (by - ay) * t + j(jitter)));
    }
  }
  out.add(out.first);
  return out;
}
```
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Wire the painter.** In `_DungeonPainter.paint`, when `r.roomType == 'tunnel' || r.roomType == 'cave'`: build a `Path` from `organicPerimeter(r.footprint, seed: r.id.hashCode, cellSize: _cell, jitter: _cell * 0.12)` translated to the room's canvas origin (same origin math as `cellRectFor(r, (0,0), …).topLeft` minus `_roomInset`), fill with a cave tint (`Color.lerp(scheme.surfaceContainerHighest, scheme.tertiaryContainer, isCurrent ? 0.9 : 0.5)` — pick tertiary-family so caves read green-ish under both themes), then draw door glyphs on top exactly as P1 (unchanged geometry). Dungeon rooms take the P1 path verbatim.
- [ ] **Step 6: Run existing painter/widget tests** (`flutter test test/dungeon/painter_geometry_test.dart test/dungeon/classic_pane_widget_test.dart`) — PASS (geometry helpers untouched). Analyze + format. Commit:
```bash
git add lib/engine/dungeon/organic.dart lib/features/map_screen.dart test/dungeon/organic_test.dart
git commit -m "feat(dungeon): organic cave paint — seeded wobbly perimeter"
```

## Task 8: UI — enter-cave, level header/switcher, descend, crossover note

**Files:**
- Modify: `lib/features/map_screen.dart`
- Test: `test/dungeon/classic_pane_widget_test.dart` (extend)

- [ ] **Step 1: Extend the failing widget tests** (same fixture recipe):
  - empty classic pane shows BOTH `classic-enter` and `classic-enter-cave`; tapping the cave one creates a level with `branch == 'cave'` and one tunnel/cave room.
  - after entering, the header shows `Depth 1 ·` + typeName (`Key('classic-level-header')`).
  - drive `descendFrom` via the notifier on a room given `levelDelta: -1` (inject by `replaceRoom`-style state edit or a seeded fixture room) → `classic-level-chip-2` appears; tapping `classic-level-chip-1` switches back.
  - a room with `levelDelta != 0` selected → detail card shows `Key('classic-descend')`; tapping it calls through (verify `levels.length == 2`).
  - base (non-classic) pane still shows neither button (regression).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement in the classic pane:**
  - Empty state: two buttons — "Enter the dungeon" (`classic-enter`) / "Enter a cave" (`classic-enter-cave`) → `enterClassicDungeon(branch: …)`; both `await ref.read(dungeonDataProvider.future)` (the P1 gotcha).
  - Header row (classic mode, levels non-empty): `Depth ${lvl.depth} · ${lvl.typeName}` + (cave) ` · ${lvl.stone}`; when `levels.length > 1`, a `Wrap` of `ChoiceChip`s (`classic-level-chip-<depth>`) → `switchLevel(depth)`.
  - Detail card: when the selected room's `levelDelta != 0`, add a `FilledButton.tonalIcon` (`classic-descend`, label "Descend"/"Ascend" by sign, stairs icon) → `descendFrom(room.id, …)`. When `crossTo != null`, a one-line caption "Openings lead to the ${crossTo == 'cave' ? 'caves' : 'dungeon'}".
  - Narrow-width care: buttons in the card go in the existing `Wrap` of actions (Linger / Set encounter) — same pattern, no new Row+Expanded (the loose-constraints gotcha).
- [ ] **Step 4: Run** the widget suite + `flutter analyze lib/` — PASS/clean. Format.
- [ ] **Step 5: Commit**
```bash
git add lib/features/map_screen.dart test/dungeon/classic_pane_widget_test.dart
git commit -m "feat(dungeon): cave entry, level header + switcher, descend/ascend UI"
```

## Task 9: Docs + full verification

**Files:**
- Modify: `CLAUDE.md` (extend the classic-dungeon bullet: caves D–F/I shipped, DungeonLevel/multi-level, organic paint, on_stock_6, treasure roller; P3 leftovers = interactive traps/harvest, alien-hive combos)
- Modify: `docs/superpowers/specs/2026-07-06-classic-dungeon-generator-design.md` (one line: P2 shipped, pointer to the P2 spec)

- [ ] **Step 1: Update both docs.**
- [ ] **Step 2: Full gate:** `python3 build_dungeon.py && flutter analyze && flutter test` — self-check OK, no issues, all green.
- [ ] **Step 3: Commit**
```bash
git add CLAUDE.md docs/
git commit -m "docs(dungeon): P2 caves/multi-level notes"
```
Device verification (enter cave → organic rooms → descend → switcher → dungeon crossover) happens after all tasks via the verify skill, per the P1 recipe.

---

## Self-review notes (author)

- **Spec coverage:** §1 rail → T1; loader → T2; treasure → T3; engine (branch/tier/lvl/crossover/on_stock_6/treasure hookup) → T4; §3 model → T5; lifecycle + level-derived effects (fixes ephemeral-A2) → T6; §4 organic paint → T7; §4 UI → T8; docs/tests → T9 + per-task tests. Error handling: clamps/fallbacks specified in T3/T4/T5.
- **Type consistency:** `DungeonBranch`, new `DungeonGenContext{branch,depth,stone,roomId,effect,tables,factions}`, `RoomResult{levelDelta,crossoverTo}`, `DungeonRoom{levelDelta,crossTo}`, `DungeonLevel{depth,branch,typeName,note,stone,…}`, `MapState{levels,activeLevel}` + view getters, notifier API `enterClassicDungeon`/`addClassicRoom`(effect param removed)/`descendFrom`/`switchLevel` — used identically across tasks.
- **Known risk, called out for the implementer:** T5's `MapState.copyWith` compatibility shim (rooms edits apply to the active level) is the highest-blast-radius change — run the FULL test suite in T5 step 4, not just dungeon tests.
