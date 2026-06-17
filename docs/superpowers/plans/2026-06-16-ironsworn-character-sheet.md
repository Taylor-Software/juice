# Pre-made Classic Ironsworn Character Sheet — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bespoke Classic Ironsworn player-character sheet (stats, condition meters, signed momentum, debilities, XP, bonds, vows, datasworn assets) over the existing generic `Character` model, created pre-filled in one tap.

**Architecture:** One optional typed sub-object `IronswornSheet` on `Character` (mirrors the existing `CharacterEmulation` pattern — additive, tolerant parse, no schema bump). A new `IronswornSheetView` widget renders when `character.ironsworn != null`, replacing the generic editor for that character. Asset definitions are emitted into `ruleset_*.json` by `build_datasworn.py` and read at runtime via the existing `rulesetDataProvider`.

**Tech Stack:** Dart/Flutter, flutter_riverpod, shared_preferences (mock in tests), Python 3 (build script). TDD with `flutter test` + `dart analyze`.

**Spec:** `docs/superpowers/specs/2026-06-16-ironsworn-character-sheet-design.md`

**Conventions to honor (verified in-repo):**
- Optional typed field on `Character`: see `CharacterEmulation` at `lib/engine/models.dart:619-705` and its wiring at `:717,:728,:740-751,:757-766,:768-783`.
- Tolerant parse uses local `intOr`/`strings` helpers + `whereType` filtering; null/empty omitted from `toJson`.
- A `.dart` edit auto-runs `dart format` (hook). Keep lines ≤ 80 cols where the file already does.
- **Widget tests must never call `*.load()` / hit `rootBundle`** — override `rulesetDataProvider(...)` and use `SharedPreferences.setMockInitialValues`.

---

## Task 1: `ProgressRank` enum + `ProgressTrack` model

**Files:**
- Modify: `lib/engine/models.dart` (add after `CharTrack`, i.e. after line 247)
- Test: `test/character_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/character_sheet_test.dart` inside `void main() { ... }`:

```dart
  group('ProgressTrack', () {
    test('marks advance ticks by rank size and clamp at 40', () {
      const t = ProgressTrack(name: 'Vow', rank: ProgressRank.formidable);
      expect(t.markTicks, 4); // convenience getter on the track
      final once = t.marked(1);
      expect(once.ticks, 4);
      expect(once.boxes, 1);
      expect(t.marked(20).ticks, 40); // clamped
      expect(t.marked(-1).ticks, 0); // clamped
    });

    test('round-trips and tolerates junk', () {
      const t =
          ProgressTrack(name: 'Avenge', rank: ProgressRank.epic, ticks: 7);
      final back = ProgressTrack.maybeFromJson(t.toJson())!;
      expect(back.name, 'Avenge');
      expect(back.rank, ProgressRank.epic);
      expect(back.ticks, 7);
      expect(ProgressTrack.maybeFromJson('nope'), isNull);
      final j = ProgressTrack.maybeFromJson(
          {'name': 42, 'rank': 'bogus', 'ticks': 99})!;
      expect(j.name, '');
      expect(j.rank, ProgressRank.dangerous); // default
      expect(j.ticks, 40); // clamped
    });
  });
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `flutter test test/character_sheet_test.dart`
Expected: FAIL — `ProgressRank`/`ProgressTrack` undefined.

- [ ] **Step 3: Implement**

Insert into `lib/engine/models.dart` immediately after `CharTrack` (after line 247):

```dart
/// Progress-track rank; mark size (ticks per progress mark) per Ironsworn.
enum ProgressRank { troublesome, dangerous, formidable, extreme, epic }

extension ProgressRankX on ProgressRank {
  /// Ticks added per progress mark (4 ticks = one filled box).
  int get markTicks => switch (this) {
        ProgressRank.troublesome => 12,
        ProgressRank.dangerous => 8,
        ProgressRank.formidable => 4,
        ProgressRank.extreme => 2,
        ProgressRank.epic => 1,
      };

  /// Capitalised display label ('Dangerous').
  String get label => name[0].toUpperCase() + name.substring(1);
}

ProgressRank _progressRankFromName(String? s) => ProgressRank.values
    .firstWhere((r) => r.name == s, orElse: () => ProgressRank.dangerous);

/// A named progress track (vow, later: legacy track). 10 boxes × 4 ticks = 40.
class ProgressTrack {
  const ProgressTrack({
    required this.name,
    this.rank = ProgressRank.dangerous,
    this.ticks = 0,
  });
  final String name;
  final ProgressRank rank;
  final int ticks; // 0..40

  int get boxes => ticks ~/ 4; // filled boxes 0..10
  int get markTicks => rank.markTicks;

  /// New track with [marks] progress marks applied (negative un-marks).
  ProgressTrack marked(int marks) =>
      copyWith(ticks: ticks + marks * rank.markTicks);

  ProgressTrack copyWith({String? name, ProgressRank? rank, int? ticks}) =>
      ProgressTrack(
        name: name ?? this.name,
        rank: rank ?? this.rank,
        ticks: (ticks ?? this.ticks).clamp(0, 40),
      );

  Map<String, dynamic> toJson() =>
      {'name': name, 'rank': rank.name, 'ticks': ticks};

  static ProgressTrack? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    return ProgressTrack(
      name: j['name'] is String ? j['name'] as String : '',
      rank: _progressRankFromName(j['rank'] is String ? j['rank'] as String : null),
      ticks: ((j['ticks'] is int ? j['ticks'] as int : 0)).clamp(0, 40),
    );
  }
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/character_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/character_sheet_test.dart
git commit -m "feat(ironsworn): ProgressRank + ProgressTrack model"
```

---

## Task 2: `AssetState` model (persisted asset on a sheet)

**Files:**
- Modify: `lib/engine/models.dart` (add after `ProgressTrack`)
- Test: `test/character_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
  group('AssetState', () {
    test('round-trips with ability flags', () {
      const a = AssetState(
        assetId: 'classic/assets/combat_talent/swordmaster',
        name: 'Swordmaster',
        category: 'Combat Talent',
        enabledAbilities: [true, false, false],
      );
      final back = AssetState.maybeFromJson(a.toJson())!;
      expect(back.assetId, a.assetId);
      expect(back.name, 'Swordmaster');
      expect(back.category, 'Combat Talent');
      expect(back.enabledAbilities, [true, false, false]);
    });

    test('rejects entries with no id; coerces junk flags', () {
      expect(AssetState.maybeFromJson({'name': 'x'}), isNull);
      final a = AssetState.maybeFromJson({
        'assetId': 'id/assets/x/y',
        'enabledAbilities': [1, true, 'no'],
      })!;
      expect(a.name, '');
      expect(a.enabledAbilities, [false, true, false]);
    });
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_test.dart`
Expected: FAIL — `AssetState` undefined.

- [ ] **Step 3: Implement** (insert after `ProgressTrack` in `models.dart`)

```dart
/// A persisted asset on an Ironsworn sheet. [enabledAbilities] parallels the
/// asset definition's abilities[]; only the toggled-on flags are play state.
class AssetState {
  const AssetState({
    required this.assetId,
    required this.name,
    this.category = '',
    this.enabledAbilities = const [],
  });
  final String assetId; // datasworn _id
  final String name;
  final String category;
  final List<bool> enabledAbilities;

  AssetState copyWith({List<bool>? enabledAbilities}) => AssetState(
        assetId: assetId,
        name: name,
        category: category,
        enabledAbilities: enabledAbilities ?? this.enabledAbilities,
      );

  Map<String, dynamic> toJson() => {
        'assetId': assetId,
        'name': name,
        if (category.isNotEmpty) 'category': category,
        'enabledAbilities': enabledAbilities,
      };

  static AssetState? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    final id = j['assetId'];
    if (id is! String || id.isEmpty) return null;
    return AssetState(
      assetId: id,
      name: j['name'] is String ? j['name'] as String : '',
      category: j['category'] is String ? j['category'] as String : '',
      enabledAbilities: j['enabledAbilities'] is List
          ? (j['enabledAbilities'] as List).map((e) => e == true).toList()
          : const [],
    );
  }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/character_sheet_test.dart
git commit -m "feat(ironsworn): AssetState model"
```

---

## Task 3: `IronswornSheet` model + `kIronswornDebilities`

**Files:**
- Modify: `lib/engine/models.dart` (add after `AssetState`)
- Test: `test/character_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
  group('IronswornSheet', () {
    test('premade defaults match the standard starting sheet', () {
      final s = IronswornSheet.premade();
      expect([s.edge, s.heart, s.iron, s.shadow, s.wits], [3, 2, 2, 1, 1]);
      expect([s.health, s.spirit, s.supply], [5, 5, 5]);
      expect(s.momentum, 2);
      expect(s.momentumMax, 10);
      expect(s.momentumReset, 2);
    });

    test('debilities lower max + reset and re-clamp momentum via copyWith', () {
      final s = const IronswornSheet(momentum: 10)
          .copyWith(debilities: {'wounded', 'shaken'});
      expect(s.momentumMax, 8);
      expect(s.momentumReset, 0);
      expect(s.momentum, 8); // re-clamped down to the new max
    });

    test('values are clamped to legal ranges', () {
      final s = const IronswornSheet().copyWith(
        edge: 9, health: 99, supply: -2, momentum: 99, bonds: 50, xpSpent: -3,
      );
      expect(s.edge, 3);
      expect(s.health, 5);
      expect(s.supply, 0);
      expect(s.momentum, 10);
      expect(s.bonds, 10);
      expect(s.xpSpent, 0);
    });

    test('round-trips with vows, assets, debilities', () {
      const s = IronswornSheet(
        edge: 3, heart: 2, iron: 2, shadow: 1, wits: 1,
        health: 4, spirit: 3, supply: 5, momentum: -2,
        xpEarned: 6, xpSpent: 4, bonds: 3,
        debilities: {'shaken'},
        vows: [ProgressTrack(name: 'Avenge', rank: ProgressRank.dangerous, ticks: 8)],
        assets: [AssetState(assetId: 'a/assets/b/c', name: 'Wolf')],
      );
      final back = IronswornSheet.maybeFromJson(s.toJson())!;
      expect(back.health, 4);
      expect(back.momentum, -2);
      expect(back.debilities, {'shaken'});
      expect(back.vows.single.ticks, 8);
      expect(back.assets.single.name, 'Wolf');
      expect(back.momentumMax, 9);
    });

    test('tolerates junk and unknown debility ids', () {
      expect(IronswornSheet.maybeFromJson('x'), isNull);
      final s = IronswornSheet.maybeFromJson({
        'edge': 'three',
        'momentum': 'fast',
        'debilities': ['wounded', 'bogus', 7],
        'vows': ['junk'],
        'assets': 'nope',
      })!;
      expect(s.edge, 1); // default
      expect(s.momentum, 2); // default
      expect(s.debilities, {'wounded'}); // unknown id dropped
      expect(s.vows, isEmpty);
      expect(s.assets, isEmpty);
    });
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_test.dart`
Expected: FAIL — `IronswornSheet`/`kIronswornDebilities` undefined.

- [ ] **Step 3: Implement** (insert after `AssetState` in `models.dart`)

```dart
/// Classic Ironsworn debilities (conditions, banes, burdens). Each marked
/// debility lowers max momentum and the burn-reset value by 1.
const kIronswornDebilities = <String, String>{
  'wounded': 'Wounded',
  'shaken': 'Shaken',
  'unprepared': 'Unprepared',
  'encumbered': 'Encumbered',
  'maimed': 'Maimed',
  'corrupted': 'Corrupted',
  'cursed': 'Cursed',
  'tormented': 'Tormented',
};

/// Bespoke Classic Ironsworn sheet. Additive on [Character] like
/// [CharacterEmulation]: null until "New Ironsworn character" writes it.
class IronswornSheet {
  const IronswornSheet({
    this.edge = 1,
    this.heart = 1,
    this.iron = 1,
    this.shadow = 1,
    this.wits = 1,
    this.health = 5,
    this.spirit = 5,
    this.supply = 5,
    this.momentum = 2,
    this.xpEarned = 0,
    this.xpSpent = 0,
    this.bonds = 0,
    this.debilities = const {},
    this.vows = const [],
    this.assets = const [],
  });

  final int edge, heart, iron, shadow, wits; // 1..3
  final int health, spirit, supply; // 0..5
  final int momentum; // -6..momentumMax
  final int xpEarned, xpSpent; // >=0
  final int bonds; // 0..10 progress boxes
  final Set<String> debilities; // ids from kIronswornDebilities
  final List<ProgressTrack> vows;
  final List<AssetState> assets;

  int get momentumMax => 10 - debilities.length;
  int get momentumReset => (2 - debilities.length).clamp(0, 2);

  /// Standard pre-made starting character (3/2/2/1/1, full meters, +2 momentum).
  factory IronswornSheet.premade() => const IronswornSheet(
        edge: 3, heart: 2, iron: 2, shadow: 1, wits: 1,
        health: 5, spirit: 5, supply: 5, momentum: 2,
      );

  IronswornSheet copyWith({
    int? edge, int? heart, int? iron, int? shadow, int? wits,
    int? health, int? spirit, int? supply,
    int? momentum, int? xpEarned, int? xpSpent, int? bonds,
    Set<String>? debilities,
    List<ProgressTrack>? vows,
    List<AssetState>? assets,
  }) {
    final dbs = debilities ?? this.debilities;
    final maxM = 10 - dbs.length;
    return IronswornSheet(
      edge: (edge ?? this.edge).clamp(1, 3),
      heart: (heart ?? this.heart).clamp(1, 3),
      iron: (iron ?? this.iron).clamp(1, 3),
      shadow: (shadow ?? this.shadow).clamp(1, 3),
      wits: (wits ?? this.wits).clamp(1, 3),
      health: (health ?? this.health).clamp(0, 5),
      spirit: (spirit ?? this.spirit).clamp(0, 5),
      supply: (supply ?? this.supply).clamp(0, 5),
      momentum: (momentum ?? this.momentum).clamp(-6, maxM),
      xpEarned: (xpEarned ?? this.xpEarned).clamp(0, 1 << 31),
      xpSpent: (xpSpent ?? this.xpSpent).clamp(0, 1 << 31),
      bonds: (bonds ?? this.bonds).clamp(0, 10),
      debilities: dbs,
      vows: vows ?? this.vows,
      assets: assets ?? this.assets,
    );
  }

  Map<String, dynamic> toJson() => {
        'edge': edge, 'heart': heart, 'iron': iron, 'shadow': shadow,
        'wits': wits, 'health': health, 'spirit': spirit, 'supply': supply,
        'momentum': momentum, 'xpEarned': xpEarned, 'xpSpent': xpSpent,
        'bonds': bonds,
        if (debilities.isNotEmpty) 'debilities': debilities.toList(),
        if (vows.isNotEmpty) 'vows': vows.map((v) => v.toJson()).toList(),
        if (assets.isNotEmpty) 'assets': assets.map((a) => a.toJson()).toList(),
      };

  static IronswornSheet? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    int intOr(dynamic v, int d) => v is int ? v : d;
    final dbs = j['debilities'] is List
        ? (j['debilities'] as List)
            .whereType<String>()
            .where(kIronswornDebilities.containsKey)
            .toSet()
        : <String>{};
    final maxM = 10 - dbs.length;
    return IronswornSheet(
      edge: intOr(j['edge'], 1).clamp(1, 3),
      heart: intOr(j['heart'], 1).clamp(1, 3),
      iron: intOr(j['iron'], 1).clamp(1, 3),
      shadow: intOr(j['shadow'], 1).clamp(1, 3),
      wits: intOr(j['wits'], 1).clamp(1, 3),
      health: intOr(j['health'], 5).clamp(0, 5),
      spirit: intOr(j['spirit'], 5).clamp(0, 5),
      supply: intOr(j['supply'], 5).clamp(0, 5),
      momentum: intOr(j['momentum'], 2).clamp(-6, maxM),
      xpEarned: intOr(j['xpEarned'], 0).clamp(0, 1 << 31),
      xpSpent: intOr(j['xpSpent'], 0).clamp(0, 1 << 31),
      bonds: intOr(j['bonds'], 0).clamp(0, 10),
      debilities: dbs,
      vows: j['vows'] is List
          ? (j['vows'] as List)
              .map(ProgressTrack.maybeFromJson)
              .whereType<ProgressTrack>()
              .toList()
          : const [],
      assets: j['assets'] is List
          ? (j['assets'] as List)
              .map(AssetState.maybeFromJson)
              .whereType<AssetState>()
              .toList()
          : const [],
    );
  }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/character_sheet_test.dart
git commit -m "feat(ironsworn): IronswornSheet model + debilities"
```

---

## Task 4: Wire `IronswornSheet` into `Character`

**Files:**
- Modify: `lib/engine/models.dart` (the `Character` class, lines 709-784)
- Test: `test/character_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
  group('Character.ironsworn', () {
    test('round-trips and is omitted when null', () {
      const plain = Character(id: 'p', name: 'Plain');
      expect(plain.toJson().containsKey('ironsworn'), isFalse);
      expect(Character.fromJson(plain.toJson()).ironsworn, isNull);

      final c = Character(
          id: 'i', name: 'Ulla', ironsworn: IronswornSheet.premade());
      final back = Character.fromJson(c.toJson());
      expect(back.ironsworn!.edge, 3);
      expect(back.ironsworn!.momentum, 2);
    });

    test('copyWith sets and clears ironsworn', () {
      const c = Character(id: 'i2', name: 'L');
      final set = c.copyWith(ironsworn: IronswornSheet.premade());
      expect(set.ironsworn, isNotNull);
      expect(set.copyWith().ironsworn, isNotNull);
      expect(set.copyWith(clearIronsworn: true).ironsworn, isNull);
    });

    test('junk ironsworn block is tolerated as null', () {
      final c = Character.fromJson(
          {'id': 'i3', 'name': 'J', 'ironsworn': 'junk'});
      expect(c.ironsworn, isNull);
    });
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_test.dart`
Expected: FAIL — `Character` has no `ironsworn`.

- [ ] **Step 3: Implement** — four edits to the `Character` class:

(a) Constructor — add after `this.emulation,` (line 717):
```dart
    this.ironsworn,
```
(b) Field — add after the `emulation` field (after line 728):
```dart
  /// Bespoke Classic Ironsworn sheet; null unless this is an Ironsworn PC.
  final IronswornSheet? ironsworn;
```
(c) `copyWith` — add params after `bool clearEmulation = false,` (line 741):
```dart
    IronswornSheet? ironsworn,
    bool clearIronsworn = false,
```
and add to the returned `Character(...)` after the `emulation:` line (line 751):
```dart
        ironsworn: clearIronsworn ? null : (ironsworn ?? this.ironsworn),
```
(d) `toJson` — add after the `emulation` line (line 764):
```dart
        if (ironsworn != null) 'ironsworn': ironsworn!.toJson(),
```
(e) `fromJson` — add after the `emulation:` line (line 781):
```dart
        ironsworn: IronswornSheet.maybeFromJson(j['ironsworn']),
```

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/character_sheet_test.dart
git commit -m "feat(ironsworn): wire IronswornSheet onto Character"
```

---

## Task 5: `IronswornAssetDef.listFromRuleset` (read asset defs from ruleset map)

**Files:**
- Modify: `lib/engine/models.dart` (add after `IronswornSheet`)
- Test: `test/character_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
  group('IronswornAssetDef.listFromRuleset', () {
    test('flattens asset_collections and seeds default ability flags', () {
      final ruleset = {
        'asset_collections': [
          {
            'name': 'Combat Talent',
            'assets': [
              {
                'id': 'classic/assets/combat_talent/swordmaster',
                'name': 'Swordmaster',
                'category': 'Combat Talent',
                'abilities': [
                  {'text': 'A', 'enabled': true},
                  {'text': 'B', 'enabled': false},
                ],
              },
            ],
          },
          {'name': 'Junk', 'assets': 'not a list'},
        ],
      };
      final defs = IronswornAssetDef.listFromRuleset(ruleset);
      expect(defs, hasLength(1));
      expect(defs.single.name, 'Swordmaster');
      expect(defs.single.abilities, ['A', 'B']);
      expect(defs.single.abilityEnabled, [true, false]);
      final st = defs.single.toState();
      expect(st.assetId, 'classic/assets/combat_talent/swordmaster');
      expect(st.enabledAbilities, [true, false]);
    });

    test('returns empty for a map with no asset_collections', () {
      expect(IronswornAssetDef.listFromRuleset({'meta': {}}), isEmpty);
    });
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_test.dart`
Expected: FAIL — `IronswornAssetDef` undefined.

- [ ] **Step 3: Implement** (insert after `IronswornSheet` in `models.dart`)

```dart
/// Read-only asset definition parsed from a loaded ruleset map's
/// `asset_collections` block (emitted by build_datasworn.py).
class IronswornAssetDef {
  const IronswornAssetDef({
    required this.id,
    required this.name,
    required this.category,
    required this.abilities,
    required this.abilityEnabled,
  });
  final String id;
  final String name;
  final String category;
  final List<String> abilities; // ability text
  final List<bool> abilityEnabled; // default-on flags

  /// A fresh persisted [AssetState] with the definition's default flags.
  AssetState toState() => AssetState(
        assetId: id,
        name: name,
        category: category,
        enabledAbilities: List<bool>.of(abilityEnabled),
      );

  static List<IronswornAssetDef> listFromRuleset(Map<String, dynamic> ruleset) {
    final out = <IronswornAssetDef>[];
    final colls = ruleset['asset_collections'];
    if (colls is! List) return out;
    for (final coll in colls) {
      if (coll is! Map) continue;
      final assets = coll['assets'];
      if (assets is! List) continue;
      final collName = coll['name'] is String ? coll['name'] as String : '';
      for (final a in assets) {
        if (a is! Map) continue;
        final id = a['id'];
        final name = a['name'];
        if (id is! String || name is! String) continue;
        final abilities = <String>[];
        final enabled = <bool>[];
        if (a['abilities'] is List) {
          for (final ab in a['abilities'] as List) {
            if (ab is! Map) continue;
            abilities.add(ab['text'] is String ? ab['text'] as String : '');
            enabled.add(ab['enabled'] == true);
          }
        }
        out.add(IronswornAssetDef(
          id: id,
          name: name,
          category: a['category'] is String ? a['category'] as String : collName,
          abilities: abilities,
          abilityEnabled: enabled,
        ));
      }
    }
    return out;
  }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/character_sheet_test.dart
git commit -m "feat(ironsworn): parse asset defs from ruleset data"
```

---

## Task 6: Emit `asset_collections` from `build_datasworn.py`

**Files:**
- Modify: `build_datasworn.py`
- Regenerate: `assets/ruleset_classic.json`, `ruleset_starforged.json`, `ruleset_delve.json`, `ruleset_sundered_isles.json`

- [ ] **Step 1: Add the transform** — insert after `flatten_oracles` (after line 79):

```python
def transform_assets(assets):
    """Flatten datasworn asset collections into [{name, assets:[...]}].

    Captures options/controls verbatim for forward-compat (the UI ignores
    them this phase); ability `enabled` is the default-on flag.
    """
    colls = []
    for coll in assets.values():
        entries = []
        for a in (coll.get("contents") or {}).values():
            abilities = [
                {"text": ab.get("text", ""),
                 "enabled": bool(ab.get("enabled", False))}
                for ab in (a.get("abilities") or [])
            ]
            entry = {
                "id": a["_id"],
                "name": a["name"],
                "category": a.get("category", coll["name"]),
                "requirement": a.get("requirement") or "",
                "abilities": abilities,
            }
            if a.get("options"):
                entry["options"] = a["options"]
            if a.get("controls"):
                entry["controls"] = a["controls"]
            entries.append(entry)
        if entries:
            colls.append({"name": coll["name"], "assets": entries})
    return colls
```

- [ ] **Step 2: Verify assets** — inside `verify()`, before `return failures` (line 101), add:

```python
    for coll in data["asset_collections"]:
        for a in coll["assets"]:
            if not a["id"] or "/assets/" not in a["id"]:
                failures.append(f"{ruleset_id}: bad asset id {a['id']!r}")
            if not a["name"]:
                failures.append(f"{ruleset_id}: unnamed asset")
            for ab in a["abilities"]:
                if not ab["text"]:
                    failures.append(
                        f"{ruleset_id}: empty ability text in {a['name']}")
```

- [ ] **Step 3: Emit + count** — in `main()`:

Add to the `data = {...}` dict (after the `oracle_collections` line, line 118):
```python
            "asset_collections": transform_assets(src.get("assets") or {}),
```
Replace the print line (line 124-126) with:
```python
        n_moves = sum(len(c["moves"]) for c in data["move_categories"])
        n_tables = sum(len(c["tables"]) for c in data["oracle_collections"])
        n_assets = sum(len(c["assets"]) for c in data["asset_collections"])
        print(f"{out}: {n_moves} moves, {n_tables} oracle tables, "
              f"{n_assets} assets")
```

- [ ] **Step 4: Run the build, verify output + classic count**

Run: `python3 build_datasworn.py`
Expected: ends with `All datasworn verifications passed.` and the classic line reads `assets/ruleset_classic.json: ... 78 assets`.

- [ ] **Step 5: Confirm the key landed**

Run: `python3 -c "import json;d=json.load(open('assets/ruleset_classic.json'));print(len(d['asset_collections']),'collections',sum(len(c['assets']) for c in d['asset_collections']),'assets')"`
Expected: `4 collections 78 assets`

- [ ] **Step 6: Commit**

```bash
git add build_datasworn.py assets/ruleset_classic.json assets/ruleset_starforged.json assets/ruleset_delve.json assets/ruleset_sundered_isles.json
git commit -m "feat(ironsworn): emit asset_collections from build_datasworn"
```

---

## Task 7: `CharacterNotifier.addIronsworn()` provider method

**Files:**
- Modify: `lib/state/providers.dart` (`CharacterNotifier`, after `addReturningId`, line 232)
- Test: `test/character_provider_test.dart` (new)

- [ ] **Step 1: Write the failing test** — create `test/character_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('addIronsworn prepends a premade Ironsworn character', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(charactersProvider.future);
    final id = await c.read(charactersProvider.notifier).addIronsworn();
    final chars = await c.read(charactersProvider.future);
    expect(chars.first.id, id);
    expect(chars.first.ironsworn, isNotNull);
    expect(chars.first.ironsworn!.edge, 3);
  });
}
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_provider_test.dart`
Expected: FAIL — `addIronsworn` undefined.

- [ ] **Step 3: Implement** — add to `CharacterNotifier` after `addReturningId` (after line 232):

```dart
  /// Creates a pre-made Classic Ironsworn PC at the top and returns its id.
  Future<String> addIronsworn() async {
    final id = _newId();
    await _persist([
      Character(
          id: id,
          name: 'New Ironsworn character',
          ironsworn: IronswornSheet.premade()),
      ...await _ready,
    ]);
    return id;
  }
```

Ensure `models.dart` is imported in `providers.dart` (it already is, via `Character`).

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/character_provider_test.dart
git commit -m "feat(ironsworn): addIronsworn notifier method"
```

---

## Task 8: `IronswornSheetView` core widget + render branch + create flow

Builds the bespoke sheet (header/rename, stats, condition meters, momentum + Burn, debilities, XP, bonds), wires it into `CharactersPane`, and adds the "New Ironsworn character" create path.

**Files:**
- Create: `lib/features/ironsworn_sheet.dart`
- Modify: `lib/features/tracker_screen.dart`
- Test: `test/character_sheet_ui_test.dart`

- [ ] **Step 1: Write the failing tests** — add to `test/character_sheet_ui_test.dart` (inside `main`, reuse the existing imports; they already import tracker_screen, providers, theme, shared_preferences):

```dart
  // A character that already carries an Ironsworn sheet (skips create flow).
  Future<ProviderContainer> pumpIronsworn(WidgetTester tester,
      {String iron = '{"edge":3,"heart":2,"iron":2,"shadow":1,"wits":1,'
          '"health":5,"spirit":5,"supply":5,"momentum":2,'
          '"xpEarned":0,"xpSpent":0,"bonds":0}'}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.characters.v1.default':
          '[{"id":"iw","name":"Ulla","note":"","stats":[],"tracks":[],'
              '"tags":[],"ironsworn":$iron}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  testWidgets('opening an Ironsworn character shows the bespoke sheet',
      (tester) async {
    await pumpIronsworn(tester);
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ironsworn-sheet')), findsOneWidget);
    expect(find.text('EDGE'), findsOneWidget);
    expect(find.text('Health'), findsOneWidget);
  });

  testWidgets('meter and momentum steppers adjust and persist', (tester) async {
    final c = await pumpIronsworn(tester);
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-health-minus')));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.ironsworn!.health, 4);
    await tester.tap(find.byKey(const Key('iw-mom-minus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.ironsworn!.momentum, 1);
  });

  testWidgets('Burn sets momentum to reset; debility lowers max', (tester) async {
    final c = await pumpIronsworn(tester,
        iron: '{"edge":3,"heart":2,"iron":2,"shadow":1,"wits":1,"health":5,'
            '"spirit":5,"supply":5,"momentum":9,"xpEarned":0,"xpSpent":0,'
            '"bonds":0}');
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-burn')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.ironsworn!.momentum, 2);
    // Mark a debility: max drops to 9.
    await tester.tap(find.byKey(const Key('iw-deb-shaken')));
    await tester.pumpAndSettle();
    final s = (await c.read(charactersProvider.future)).single.ironsworn!;
    expect(s.debilities, {'shaken'});
    expect(s.momentumMax, 9);
  });

  testWidgets('create flow makes a pre-made Ironsworn character', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.characters.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-ironsworn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ironsworn-sheet')), findsOneWidget);
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.ironsworn!.edge, 3);
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: FAIL — `ironsworn-sheet` key not found / `new-ironsworn` not found.

- [ ] **Step 3: Create `lib/features/ironsworn_sheet.dart`** (core sheet; vows + assets added in later tasks):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';

/// Bespoke Classic Ironsworn character sheet. Renders for characters whose
/// [Character.ironsworn] is non-null; edits persist via charactersProvider.
class IronswornSheetView extends ConsumerWidget {
  const IronswornSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  IronswornSheet get _s => character.ironsworn!;

  void _save(WidgetRef ref, IronswornSheet next) =>
      ref.read(charactersProvider.notifier).replace(
          character.copyWith(ironsworn: next));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;
    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(t, style: theme.textTheme.titleMedium),
        );
    return ListView(
      key: const Key('ironsworn-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(
            key: const Key('sheet-back'),
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(character.name,
                style: theme.textTheme.titleLarge,
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
            onPressed: () => _rename(context, ref),
          ),
        ]),
        Text('Ironsworn · Classic', style: theme.textTheme.labelSmall),

        section('Stats'),
        Row(children: [
          _stat(ref, 'EDGE', s.edge, (v) => _save(ref, s.copyWith(edge: v))),
          _stat(ref, 'HEART', s.heart, (v) => _save(ref, s.copyWith(heart: v))),
          _stat(ref, 'IRON', s.iron, (v) => _save(ref, s.copyWith(iron: v))),
          _stat(ref, 'SHADOW', s.shadow,
              (v) => _save(ref, s.copyWith(shadow: v))),
          _stat(ref, 'WITS', s.wits, (v) => _save(ref, s.copyWith(wits: v))),
        ]),

        section('Condition Meters'),
        _meter(ref, 'Health', 'health', s.health,
            (v) => _save(ref, s.copyWith(health: v))),
        _meter(ref, 'Spirit', 'spirit', s.spirit,
            (v) => _save(ref, s.copyWith(spirit: v))),
        _meter(ref, 'Supply', 'supply', s.supply,
            (v) => _save(ref, s.copyWith(supply: v))),

        section('Momentum'),
        Row(children: [
          IconButton(
            key: const Key('iw-mom-minus'),
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => _save(ref, s.copyWith(momentum: s.momentum - 1)),
          ),
          Text(s.momentum >= 0 ? '+${s.momentum}' : '${s.momentum}',
              style: theme.textTheme.titleLarge),
          IconButton(
            key: const Key('iw-mom-plus'),
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _save(ref, s.copyWith(momentum: s.momentum + 1)),
          ),
          const Spacer(),
          Text('max +${s.momentumMax} · reset +${s.momentumReset}',
              style: theme.textTheme.bodySmall),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('iw-burn'),
            onPressed: () => _save(ref, s.copyWith(momentum: s.momentumReset)),
            child: const Text('Burn'),
          ),
        ]),

        section('Debilities'),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final e in kIronswornDebilities.entries)
            FilterChip(
              key: Key('iw-deb-${e.key}'),
              label: Text(e.value),
              selected: s.debilities.contains(e.key),
              onSelected: (on) {
                final d = {...s.debilities};
                if (on) {
                  d.add(e.key);
                } else {
                  d.remove(e.key);
                }
                _save(ref, s.copyWith(debilities: d));
              },
            ),
        ]),

        section('Experience & Bonds'),
        Row(children: [
          const Text('XP earned'),
          _intStepper(ref, 'xpEarned', s.xpEarned,
              (v) => _save(ref, s.copyWith(xpEarned: v))),
          const SizedBox(width: 16),
          const Text('spent'),
          _intStepper(ref, 'xpSpent', s.xpSpent,
              (v) => _save(ref, s.copyWith(xpSpent: v))),
        ]),
        Row(children: [
          const Text('Bonds'),
          _intStepper(ref, 'bonds', s.bonds,
              (v) => _save(ref, s.copyWith(bonds: v))),
          Text('/ 10', style: theme.textTheme.bodySmall),
        ]),

        section('Notes'),
        Text(character.note.isEmpty ? '—' : character.note),
      ],
    );
  }

  Widget _stat(WidgetRef ref, String label, int value, ValueChanged<int> set) =>
      Expanded(
        child: Column(children: [
          Text('$value', style: const TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 10)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              key: Key('iw-stat-${label.toLowerCase()}-minus'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove, size: 16),
              onPressed: () => set(value - 1),
            ),
            IconButton(
              key: Key('iw-stat-${label.toLowerCase()}-plus'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add, size: 16),
              onPressed: () => set(value + 1),
            ),
          ]),
        ]),
      );

  Widget _meter(WidgetRef ref, String label, String key, int value,
          ValueChanged<int> set) =>
      Row(children: [
        SizedBox(width: 64, child: Text(label)),
        IconButton(
          key: Key('iw-$key-minus'),
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => set(value - 1),
        ),
        Text('$value / 5'),
        IconButton(
          key: Key('iw-$key-plus'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => set(value + 1),
        ),
      ]);

  Widget _intStepper(
          WidgetRef ref, String key, int value, ValueChanged<int> set) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: Key('iw-$key-minus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => set(value - 1),
        ),
        Text('$value'),
        IconButton(
          key: Key('iw-$key-plus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => set(value + 1),
        ),
      ]);

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: character.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          key: const Key('iw-name'),
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(charactersProvider.notifier)
        .replace(character.copyWith(name: name.trim()));
  }
}
```

- [ ] **Step 4: Wire the render branch** — in `lib/features/tracker_screen.dart`:

Add the import near the top with the other `package:`/relative imports:
```dart
import 'ironsworn_sheet.dart';
```
Replace the `else { return _buildSheet(context, match.first); }` branch (lines 136-138) with:
```dart
            } else {
              final c = match.first;
              if (c.ironsworn != null) {
                return IronswornSheetView(
                  character: c,
                  onBack: () => setState(() => _editingId = null),
                );
              }
              return _buildSheet(context, c);
            }
```

- [ ] **Step 5: Add the create-flow chooser** — in `tracker_screen.dart`:

Change the FAB `onPressed` (line 183) from `() => _addCharacter(context)` to `() => _onAdd(context)`.

Add these two methods to `CharactersPaneState` (next to `_addCharacter`, after line 210). They reference `sessionsProvider`, `rulesetsProvider`, `kAllSystems` — `providers.dart` and `models.dart` are already imported by this file:

```dart
  Future<void> _onAdd(BuildContext context) async {
    final systems = ref
            .read(sessionsProvider)
            .valueOrNull
            ?.activeMeta
            .enabledSystems ??
        kAllSystems;
    if (!systems.contains('ironsworn')) {
      await _addCharacter(context);
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New character'),
        content: const Text('Choose a sheet type.'),
        actions: [
          TextButton(
            key: const Key('new-generic'),
            onPressed: () => Navigator.pop(context, 'generic'),
            child: const Text('Generic'),
          ),
          FilledButton(
            key: const Key('new-ironsworn'),
            onPressed: () => Navigator.pop(context, 'ironsworn'),
            child: const Text('Ironsworn'),
          ),
        ],
      ),
    );
    if (choice == 'generic') {
      await _addCharacter(context);
    } else if (choice == 'ironsworn') {
      await _newIronsworn();
    }
  }

  Future<void> _newIronsworn() async {
    // Ensure a base Ironsworn ruleset is active so the asset picker has data.
    final rs = ref.read(rulesetsProvider).valueOrNull ?? const <String>{};
    if (!rs.contains('classic') && !rs.contains('starforged')) {
      await ref.read(rulesetsProvider.notifier).setRuleset('classic', true);
    }
    final id = await ref.read(charactersProvider.notifier).addIronsworn();
    if (mounted) setState(() => _editingId = id);
  }
```

Confirm `sessionsProvider` resolves: it is exported from `providers.dart` and exposes `activeMeta` on its value. If `tracker_screen.dart` does not yet import it, it is the same `providers.dart` already imported — no new import needed.

- [ ] **Step 6: Run, verify pass**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: PASS (all sheet + create-flow tests green; existing generic tests still pass).

- [ ] **Step 7: Commit**

```bash
git add lib/features/ironsworn_sheet.dart lib/features/tracker_screen.dart test/character_sheet_ui_test.dart
git commit -m "feat(ironsworn): bespoke sheet core + render branch + create flow"
```

---

## Task 9: Vows section (add + advance + rank)

**Files:**
- Modify: `lib/features/ironsworn_sheet.dart`
- Test: `test/character_sheet_ui_test.dart`

- [ ] **Step 1: Write the failing test** — add to `character_sheet_ui_test.dart`:

```dart
  testWidgets('add a vow then mark progress', (tester) async {
    final c = await pumpIronsworn(tester);
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-add-vow')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vow-name')), 'Avenge');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Avenge'), findsOneWidget);
    // Mark one progress (default rank dangerous => +8 ticks => 2 boxes).
    await tester.tap(find.byKey(const Key('iw-vow-0-mark')));
    await tester.pumpAndSettle();
    final vow =
        (await c.read(charactersProvider.future)).single.ironsworn!.vows.single;
    expect(vow.name, 'Avenge');
    expect(vow.ticks, 8);
    expect(vow.boxes, 2);
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: FAIL — `iw-add-vow` not found.

- [ ] **Step 3: Implement** — in `ironsworn_sheet.dart`, insert a Vows section into the `children:` list, immediately **before** `section('Notes')`:

```dart
        section('Vows'),
        for (var i = 0; i < s.vows.length; i++)
          _vowRow(context, ref, s, i),
        OutlinedButton.icon(
          key: const Key('iw-add-vow'),
          icon: const Icon(Icons.add),
          label: const Text('Add vow'),
          onPressed: () => _addVow(context, ref),
        ),
```

Add these methods to the `IronswornSheetView` class:

```dart
  Widget _vowRow(
      BuildContext context, WidgetRef ref, IronswornSheet s, int i) {
    final v = s.vows[i];
    IronswornSheet withVows(List<ProgressTrack> vows) => s.copyWith(vows: vows);
    void replaceVow(ProgressTrack nv) =>
        _save(ref, withVows([...s.vows]..[i] = nv));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(v.name,
                style: const TextStyle(fontWeight: FontWeight.bold))),
            DropdownButton<ProgressRank>(
              key: Key('iw-vow-$i-rank'),
              value: v.rank,
              underline: const SizedBox.shrink(),
              items: [
                for (final r in ProgressRank.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (r) => replaceVow(v.copyWith(rank: r)),
            ),
            IconButton(
              key: Key('iw-vow-$i-unmark'),
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Un-mark',
              onPressed: () => replaceVow(v.marked(-1)),
            ),
            IconButton(
              key: Key('iw-vow-$i-mark'),
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Mark progress',
              onPressed: () => replaceVow(v.marked(1)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  _save(ref, withVows([...s.vows]..removeAt(i))),
            ),
          ]),
          Text('${v.boxes}/10 boxes · ${v.rank.label}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }

  Future<void> _addVow(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    var rank = ProgressRank.dangerous;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Add vow'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const Key('vow-name'),
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Vow'),
            ),
            const SizedBox(height: 12),
            DropdownButton<ProgressRank>(
              key: const Key('vow-rank'),
              value: rank,
              isExpanded: true,
              items: [
                for (final r in ProgressRank.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (r) => setLocal(() => rank = r ?? rank),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, ctrl.text),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    _save(
        ref,
        _s.copyWith(vows: [
          ..._s.vows,
          ProgressTrack(name: name.trim(), rank: rank),
        ]));
  }
```

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/ironsworn_sheet.dart test/character_sheet_ui_test.dart
git commit -m "feat(ironsworn): vows section (add, rank, mark progress)"
```

---

## Task 10: Assets section (datasworn picker + ability toggles)

**Files:**
- Modify: `lib/features/ironsworn_sheet.dart`
- Test: `test/character_sheet_ui_test.dart`

- [ ] **Step 1: Write the failing test** — add to `character_sheet_ui_test.dart`. This test overrides `rulesetDataProvider('classic')` with a fixture (NO rootBundle):

```dart
  testWidgets('pick an asset from the ruleset and toggle an ability',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.rulesets.v1': '["classic"]',
      'juice.characters.v1.default':
          '[{"id":"iw","name":"Ulla","note":"","stats":[],"tracks":[],'
              '"tags":[],"ironsworn":{"edge":3,"heart":2,"iron":2,"shadow":1,'
              '"wits":1,"health":5,"spirit":5,"supply":5,"momentum":2,'
              '"xpEarned":0,"xpSpent":0,"bonds":0}}]',
    });
    final fixture = {
      'asset_collections': [
        {
          'name': 'Combat Talent',
          'assets': [
            {
              'id': 'classic/assets/combat_talent/swordmaster',
              'name': 'Swordmaster',
              'category': 'Combat Talent',
              'abilities': [
                {'text': 'Strike harder', 'enabled': true},
                {'text': 'Press the attack', 'enabled': false},
              ],
            },
          ],
        },
      ],
    };
    final c = ProviderContainer(overrides: [
      rulesetDataProvider('classic').overrideWith((ref) async => fixture),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-add-asset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
        const Key('pick-asset-classic/assets/combat_talent/swordmaster')));
    await tester.pumpAndSettle();
    expect(find.text('Swordmaster'), findsOneWidget);
    var asset =
        (await c.read(charactersProvider.future)).single.ironsworn!.assets.single;
    expect(asset.enabledAbilities, [true, false]);
    // Toggle the second ability on.
    await tester.tap(find.byKey(const Key('iw-asset-0-ability-1')));
    await tester.pumpAndSettle();
    asset =
        (await c.read(charactersProvider.future)).single.ironsworn!.assets.single;
    expect(asset.enabledAbilities, [true, true]);
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: FAIL — `iw-add-asset` not found.

- [ ] **Step 3: Implement** — in `ironsworn_sheet.dart`:

Compute the active asset ruleset id at the top of `build` (after `final s = _s;`):
```dart
    final rs = ref.watch(rulesetsProvider).valueOrNull ?? const <String>{};
    final assetRid = rs.contains('starforged') ? 'starforged' : 'classic';
```

Insert an Assets section into the `children:` list, immediately **before** `section('Notes')`:
```dart
        section('Assets'),
        for (var i = 0; i < s.assets.length; i++) _assetCard(ref, s, i),
        OutlinedButton.icon(
          key: const Key('iw-add-asset'),
          icon: const Icon(Icons.add),
          label: const Text('Add asset'),
          onPressed: () => _addAsset(context, ref, assetRid),
        ),
```

Add these methods to the class:
```dart
  Widget _assetCard(WidgetRef ref, IronswornSheet s, int i) {
    final a = s.assets[i];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${a.name}  ·  ${a.category}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  _save(ref, s.copyWith(assets: [...s.assets]..removeAt(i))),
            ),
          ]),
          for (var k = 0; k < a.enabledAbilities.length; k++)
            CheckboxListTile(
              key: Key('iw-asset-$i-ability-$k'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: a.enabledAbilities[k],
              title: Text('Ability ${k + 1}'),
              onChanged: (on) {
                final flags = [...a.enabledAbilities]..[k] = on ?? false;
                final assets = [...s.assets]
                  ..[i] = a.copyWith(enabledAbilities: flags);
                _save(ref, s.copyWith(assets: assets));
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _addAsset(
      BuildContext context, WidgetRef ref, String rulesetId) async {
    final data = await ref.read(rulesetDataProvider(rulesetId).future);
    final defs = IronswornAssetDef.listFromRuleset(data);
    if (!context.mounted) return;
    final def = await showDialog<IronswornAssetDef>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add asset'),
        children: [
          SizedBox(
            width: 320,
            height: 420,
            child: ListView(children: [
              for (final d in defs)
                ListTile(
                  key: Key('pick-asset-${d.id}'),
                  title: Text(d.name),
                  subtitle: Text(d.category),
                  onTap: () => Navigator.pop(context, d),
                ),
            ]),
          ),
        ],
      ),
    );
    if (def == null) return;
    _save(ref, _s.copyWith(assets: [..._s.assets, def.toState()]));
  }
```

Note: ability rows are labelled "Ability N" to avoid rendering raw datasworn Markdown this phase (see spec risks); the toggle state is what matters.

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/ironsworn_sheet.dart test/character_sheet_ui_test.dart
git commit -m "feat(ironsworn): assets section (picker + ability toggles)"
```

---

## Task 11: Full verification + docs

**Files:**
- Modify: `CLAUDE.md` (the `build_datasworn.py` bullet)

- [ ] **Step 1: Run static analysis**

Run: `flutter analyze`
Expected: `No issues found!` (fix any analyzer findings before continuing).

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: all tests pass. (If any pre-existing test imports `ruleset_classic.json` shape, confirm the added `asset_collections` key did not break it — it is additive.)

- [ ] **Step 3: Re-run the build script self-verify**

Run: `python3 build_datasworn.py`
Expected: `All datasworn verifications passed.`

- [ ] **Step 4: Update the CLAUDE.md note** — edit the `build_datasworn.py` bullet so it reads (append the asset clause):

> Ironsworn/Starforged ruleset assets (`assets/ruleset_*.json`) are generated by `build_datasworn.py` from vendored Datasworn JSON in `data/datasworn/`. Regenerate with `python3 build_datasworn.py`; self-verifies roll types, oracle row ranges, **and asset entries (well-formed ids + non-empty ability text)**. Like `build_oracle.py`, this is the source of truth — edit the script, not the generated JSON. The emitted `asset_collections` block backs the bespoke Ironsworn character sheet (`lib/features/ironsworn_sheet.dart`).

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note asset_collections in build_datasworn rail"
```

---

## Self-Review (completed during planning)

**Spec coverage:**
- IronswornSheet model + Character wiring → Tasks 1-4. ✓
- Asset data from datasworn (build script) → Task 6; runtime parse → Task 5. ✓
- Momentum signed + max/reset from debilities + Burn → Tasks 3, 8. ✓
- Stats/meters/XP/bonds → Task 8. ✓
- Vows as progress tracks → Task 9. ✓
- Assets pick + ability toggles (meters/inputs deferred) → Task 10. ✓
- Render branch + gated create flow (pre-filled) → Tasks 7, 8. ✓
- Generic character unchanged → asserted in Task 8 (`opening an Ironsworn character` test pumps both; the existing `emulation summary` test already covers a non-Ironsworn character keeping the generic editor). ✓
- Export/import + no schema bump → covered by Character JSON round-trip (Task 4); export already serializes Character.toJson. ✓
- Testing rails incl. rootBundle override → Task 10 uses `rulesetDataProvider(...).overrideWith`; no test calls `.load()`. ✓

**Type consistency:** `IronswornSheet.copyWith` / `maybeFromJson` clamp ranges identically; `ProgressTrack.marked` used by Task 9; `AssetState.copyWith(enabledAbilities:)` used by Task 10; `IronswornAssetDef.toState()` used by Task 10; provider `addIronsworn()` defined in Task 7 and called in Task 8. Keys are unique and consistent across widget + tests.

**Placeholder scan:** none — every code step shows full code.

**Out of scope (unchanged):** LLM rules (Slice B), companion/asset meters + input fields, guided wizard, Starforged & derivatives sheets, D&D/Shadowdark.
