# Content Library — Spells & Monsters + GM Quick-Reference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a unified, edition-aware content library of spells and monsters (flagship: D&D 5e SRD 5.1) surfaced through an always-available quick-reference (Ask tab + Run panel + slash commands), the encounter monster picker, and a D&D caster-sheet spell picker.

**Architecture:** Approach A — one pure `contentRegistry` aggregates bundled creature files, ruleset NPCs, the user bestiary, and new bundled spell files behind a single `searchContent` interface; every surface reads it. Monsters reuse `Creature`/`StatBlock` (enriched with optional D&D fields); spells use a new `SpellEntry`. New systems are data-only.

**Tech Stack:** Flutter + Riverpod, `shared_preferences`, bundled JSON assets, Python build-script rail (`build_dnd_content.py`), `package:flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-29-content-library-spells-monsters-design.md`

---

## File Structure

**Create:**
- `lib/engine/spell.dart` — `SpellEntry` value class (pure, no Flutter).
- `lib/engine/content_registry.dart` — `ContentType`, `ContentResults`, pure `searchContent`, `kContentAttributions`, `foeEntryToCreature` adapter.
- `lib/features/reference_view.dart` — `ReferenceView` (shared search/filter/glance) + `SpellCard`.
- `build_dnd_content.py` — transforms vendored SRD JSON → `assets/spells_dnd.json` + `assets/foes_dnd.json`.
- `data/dnd_srd/` — vendored CC-BY SRD source JSON (committed).
- `assets/spells_dnd.json`, `assets/foes_dnd.json` — generated.
- `test/spell_test.dart`, `test/content_registry_test.dart`, `test/reference_view_test.dart`.

**Modify:**
- `lib/engine/models.dart` — `StatTrait` (new), `StatBlock` enrichment, `Creature.edition`, `DndSheet.spellIds`.
- `lib/state/providers.dart` — `systemSpellsProvider`, `contentMonstersProvider`, `contentSpellsProvider`, `kContentSystemsWithFiles`.
- `lib/features/sheet_widgets.dart` — `StatBlockView` renders cr/type/size/abilities/traits.
- `lib/features/oracles_tab.dart` — add the "Reference" subtab.
- `lib/features/run_screen.dart` — `_ReferencePanel` (`run-panel-reference`).
- `lib/features/journal_screen.dart` — `/lookup` `/spell` `/monster` builtins + palette + dispatch.
- `lib/features/encounter_screen.dart` — "Add from reference" button.
- `lib/features/dnd_sheet.dart` — spell picker + glance.
- `lib/features/settings_sheet.dart` — "Sources & licenses" section.
- `pubspec.yaml` — register the two new assets.
- `CLAUDE.md` — document the content library.

---

## Task 1: `SpellEntry` model

**Files:**
- Create: `lib/engine/spell.dart`
- Test: `test/spell_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/spell_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/spell.dart';

void main() {
  test('round-trips through json', () {
    const s = SpellEntry(
      id: 'dnd-fireball', system: 'dnd', edition: '5.1', name: 'Fireball',
      level: 3, school: 'Evocation', castingTime: '1 action', range: '150 feet',
      components: 'V, S, M', duration: 'Instantaneous', concentration: false,
      ritual: false, classes: ['Sorcerer', 'Wizard'],
      description: 'A bright streak flashes...', higherLevels: 'At higher levels...',
    );
    final back = SpellEntry.maybeFromJson(s.toJson());
    expect(back, isNotNull);
    expect(back!.name, 'Fireball');
    expect(back.level, 3);
    expect(back.classes, ['Sorcerer', 'Wizard']);
    expect(back.edition, '5.1');
    expect(back.higherLevels, 'At higher levels...');
  });

  test('tolerant: missing id or name returns null', () {
    expect(SpellEntry.maybeFromJson({'name': 'X'}), isNull);
    expect(SpellEntry.maybeFromJson({'id': 'x'}), isNull);
    expect(SpellEntry.maybeFromJson('not a map'), isNull);
  });

  test('tolerant: defaults for absent optional fields', () {
    final s = SpellEntry.maybeFromJson({'id': 'a', 'name': 'A'})!;
    expect(s.level, 0);
    expect(s.classes, isEmpty);
    expect(s.concentration, isFalse);
    expect(s.edition, isNull);
    expect(s.higherLevels, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/spell_test.dart`
Expected: FAIL — `spell.dart` / `SpellEntry` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/engine/spell.dart
/// A bundled, reference-only spell entry. Facts + vendored SRD text under a
/// free license (attribution carried in kContentAttributions). Pure — no Flutter.
class SpellEntry {
  const SpellEntry({
    required this.id,
    required this.system,
    this.edition,
    required this.name,
    this.level = 0,
    this.school = '',
    this.castingTime = '',
    this.range = '',
    this.components = '',
    this.duration = '',
    this.concentration = false,
    this.ritual = false,
    this.classes = const [],
    this.description = '',
    this.higherLevels,
  });

  final String id;
  final String system;
  final String? edition; // "5.1" | "5.2" | null
  final String name;
  final int level; // 0 = cantrip
  final String school;
  final String castingTime, range, components, duration;
  final bool concentration, ritual;
  final List<String> classes;
  final String description;
  final String? higherLevels;

  Map<String, dynamic> toJson() => {
        'id': id,
        'system': system,
        if (edition != null) 'edition': edition,
        'name': name,
        if (level != 0) 'level': level,
        if (school.isNotEmpty) 'school': school,
        if (castingTime.isNotEmpty) 'castingTime': castingTime,
        if (range.isNotEmpty) 'range': range,
        if (components.isNotEmpty) 'components': components,
        if (duration.isNotEmpty) 'duration': duration,
        if (concentration) 'concentration': true,
        if (ritual) 'ritual': true,
        if (classes.isNotEmpty) 'classes': classes,
        if (description.isNotEmpty) 'description': description,
        if (higherLevels != null) 'higherLevels': higherLevels,
      };

  static SpellEntry? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    final id = j['id'] as String?;
    final name = j['name'] as String?;
    if (id == null || id.isEmpty || name == null || name.isEmpty) return null;
    return SpellEntry(
      id: id,
      system: (j['system'] as String?) ?? '',
      edition: j['edition'] as String?,
      name: name,
      level: (j['level'] as num?)?.toInt() ?? 0,
      school: (j['school'] as String?) ?? '',
      castingTime: (j['castingTime'] as String?) ?? '',
      range: (j['range'] as String?) ?? '',
      components: (j['components'] as String?) ?? '',
      duration: (j['duration'] as String?) ?? '',
      concentration: j['concentration'] == true,
      ritual: j['ritual'] == true,
      classes: ((j['classes'] as List?) ?? const []).cast<String>(),
      description: (j['description'] as String?) ?? '',
      higherLevels: j['higherLevels'] as String?,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/spell_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/spell.dart test/spell_test.dart
git commit -m "feat(content): SpellEntry model"
```

---

## Task 2: `StatTrait` + `StatBlock` enrichment + `Creature.edition`

**Files:**
- Modify: `lib/engine/models.dart` (Attack/StatBlock/Creature block, ~2757-2877)
- Test: `test/statblock_enrichment_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/statblock_enrichment_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('StatTrait round-trips', () {
    const t = StatTrait(name: 'Pack Tactics', text: 'Advantage when ally is near.');
    final back = StatTrait.fromJson(t.toJson());
    expect(back.name, 'Pack Tactics');
    expect(back.text, 'Advantage when ally is near.');
  });

  test('StatBlock carries the new optional D&D fields', () {
    const sb = StatBlock(
      ac: 17, cr: '5', creatureType: 'Dragon', size: 'Large',
      abilities: {'STR': 19, 'DEX': 10},
      traits: [StatTrait(name: 'Fire Breath', text: 'Cone of fire.')],
    );
    final back = StatBlock.maybeFromJson(sb.toJson())!;
    expect(back.cr, '5');
    expect(back.creatureType, 'Dragon');
    expect(back.size, 'Large');
    expect(back.abilities!['STR'], 19);
    expect(back.traits!.single.name, 'Fire Breath');
  });

  test('back-compat: a legacy stat block without new fields parses to null fields', () {
    final back = StatBlock.maybeFromJson({'ac': 13, 'notes': 'old'})!;
    expect(back.ac, 13);
    expect(back.cr, isNull);
    expect(back.abilities, isNull);
    expect(back.traits, isNull);
    expect(back.isEmpty, isFalse);
  });

  test('an empty enriched stat block is still isEmpty', () {
    expect(const StatBlock().isEmpty, isTrue);
  });

  test('Creature carries optional edition', () {
    final c = Creature.maybeFromJson(
        {'id': 'dnd-2024-goblin', 'name': 'Goblin', 'edition': '5.2'})!;
    expect(c.edition, '5.2');
    final legacy = Creature.maybeFromJson({'id': 'x', 'name': 'X'})!;
    expect(legacy.edition, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/statblock_enrichment_test.dart`
Expected: FAIL — `StatTrait` undefined; `cr`/`abilities`/`traits`/`edition` params don't exist.

- [ ] **Step 3: Add `StatTrait` above `StatBlock`**

Insert before `class StatBlock {` (line ~2775):

```dart
/// One named trait/action on a stat block (D&D traits, actions, legendary acts).
class StatTrait {
  const StatTrait({required this.name, this.text = ''});
  final String name;
  final String text;

  Map<String, dynamic> toJson() =>
      {'name': name, if (text.isNotEmpty) 'text': text};

  factory StatTrait.fromJson(dynamic j) => j is Map
      ? StatTrait(
          name: (j['name'] as String?) ?? '',
          text: (j['text'] as String?) ?? '')
      : const StatTrait(name: '');
}
```

- [ ] **Step 4: Enrich `StatBlock`**

Replace the `StatBlock` constructor + fields + `copyWith` + `toJson` + `maybeFromJson` so the new optional fields are threaded. Full replacement body:

```dart
class StatBlock {
  const StatBlock({
    this.ac = 0,
    this.attacks = const [],
    this.saves = '',
    this.speed = '',
    this.notes = '',
    this.cr,
    this.creatureType,
    this.size,
    this.abilities,
    this.traits,
  });
  final int ac;
  final List<Attack> attacks;
  final String saves, speed, notes;
  final String? cr;
  final String? creatureType;
  final String? size;
  final Map<String, int>? abilities;
  final List<StatTrait>? traits;

  bool get isEmpty =>
      ac == 0 &&
      attacks.isEmpty &&
      saves.isEmpty &&
      speed.isEmpty &&
      notes.isEmpty &&
      cr == null &&
      creatureType == null &&
      size == null &&
      (abilities == null || abilities!.isEmpty) &&
      (traits == null || traits!.isEmpty);

  StatBlock copyWith({
    int? ac,
    List<Attack>? attacks,
    String? saves,
    String? speed,
    String? notes,
    String? cr,
    String? creatureType,
    String? size,
    Map<String, int>? abilities,
    List<StatTrait>? traits,
  }) =>
      StatBlock(
        ac: ac ?? this.ac,
        attacks: attacks ?? this.attacks,
        saves: saves ?? this.saves,
        speed: speed ?? this.speed,
        notes: notes ?? this.notes,
        cr: cr ?? this.cr,
        creatureType: creatureType ?? this.creatureType,
        size: size ?? this.size,
        abilities: abilities ?? this.abilities,
        traits: traits ?? this.traits,
      );

  Map<String, dynamic> toJson() => {
        if (ac != 0) 'ac': ac,
        if (attacks.isNotEmpty)
          'attacks': attacks.map((a) => a.toJson()).toList(),
        if (saves.isNotEmpty) 'saves': saves,
        if (speed.isNotEmpty) 'speed': speed,
        if (notes.isNotEmpty) 'notes': notes,
        if (cr != null) 'cr': cr,
        if (creatureType != null) 'creatureType': creatureType,
        if (size != null) 'size': size,
        if (abilities != null && abilities!.isNotEmpty) 'abilities': abilities,
        if (traits != null && traits!.isNotEmpty)
          'traits': traits!.map((t) => t.toJson()).toList(),
      };

  /// Tolerant: non-map -> null; attack entries without a name are dropped.
  static StatBlock? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    final abil = j['abilities'];
    final trts = j['traits'];
    return StatBlock(
      ac: (j['ac'] as num?)?.toInt() ?? 0,
      attacks: ((j['attacks'] as List?) ?? const [])
          .map(Attack.fromJson)
          .where((a) => a.name.isNotEmpty)
          .toList(),
      saves: (j['saves'] as String?) ?? '',
      speed: (j['speed'] as String?) ?? '',
      notes: (j['notes'] as String?) ?? '',
      cr: j['cr'] as String?,
      creatureType: j['creatureType'] as String?,
      size: j['size'] as String?,
      abilities: abil is Map
          ? abil.map((k, v) =>
              MapEntry(k as String, (v as num?)?.toInt() ?? 0))
          : null,
      traits: trts is List
          ? trts.map(StatTrait.fromJson).where((t) => t.name.isNotEmpty).toList()
          : null,
    );
  }
}
```

- [ ] **Step 5: Add `edition` to `Creature`**

In `class Creature`, add the field + thread it through `copyWith`/`toJson`/`maybeFromJson`:

```dart
  const Creature({
    required this.id,
    required this.name,
    this.statBlock = const StatBlock(),
    this.maxHp = 0,
    this.edition,
  });
  final String id;
  final String name;
  final StatBlock statBlock;
  final int maxHp;
  final String? edition;

  Creature copyWith({String? name, StatBlock? statBlock, int? maxHp, String? edition}) =>
      Creature(
        id: id,
        name: name ?? this.name,
        statBlock: statBlock ?? this.statBlock,
        maxHp: maxHp ?? this.maxHp,
        edition: edition ?? this.edition,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (!statBlock.isEmpty) 'statBlock': statBlock.toJson(),
        if (maxHp > 0) 'maxHp': maxHp,
        if (edition != null) 'edition': edition,
      };
```

And in `maybeFromJson`, add `edition: j['edition'] as String?,` to the returned `Creature(...)`.

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/statblock_enrichment_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 7: Guard against regressions**

Run: `flutter test test/encounter_test.dart test/bestiary_test.dart` (whichever exist that touch StatBlock/Creature).
Expected: PASS — back-compat preserved.

- [ ] **Step 8: Commit**

```bash
git add lib/engine/models.dart test/statblock_enrichment_test.dart
git commit -m "feat(content): enrich StatBlock (cr/type/size/abilities/traits) + Creature.edition"
```

---

## Task 3: Content registry — pure search + attribution + adapter

**Files:**
- Create: `lib/engine/content_registry.dart`
- Test: `test/content_registry_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/content_registry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/spell.dart';
import 'package:juice_oracle/engine/content_registry.dart';

void main() {
  final monsters = [
    const Creature(id: 'dnd-goblin', name: 'Goblin', edition: '5.1'),
    const Creature(id: 'cairn-wolf', name: 'Wolf'),
  ];
  final spells = [
    const SpellEntry(id: 'dnd-fireball', system: 'dnd', name: 'Fireball', level: 3),
    const SpellEntry(id: 'dnd-fire-bolt', system: 'dnd', name: 'Fire Bolt', level: 0),
  ];

  test('empty query returns everything (type=all)', () {
    final r = searchContent(
        query: '', filter: ContentType.all, monsters: monsters, spells: spells);
    expect(r.monsters.length, 2);
    expect(r.spells.length, 2);
  });

  test('query matches name case-insensitively', () {
    final r = searchContent(
        query: 'fire', filter: ContentType.all, monsters: monsters, spells: spells);
    expect(r.monsters, isEmpty);
    expect(r.spells.map((s) => s.name), containsAll(['Fireball', 'Fire Bolt']));
  });

  test('type filter narrows to monsters only', () {
    final r = searchContent(
        query: '', filter: ContentType.monsters, monsters: monsters, spells: spells);
    expect(r.monsters.length, 2);
    expect(r.spells, isEmpty);
  });

  test('foeEntryToCreature maps rank to hp and folds tactics/features into notes', () {
    final c = foeEntryToCreature(const FoeEntry(
      id: 'is-haunt', name: 'Haunt', rank: 3, nature: 'Horror',
      features: ['Cold spot'], drives: [], tactics: ['Ambush'],
    ));
    expect(c.maxHp, 30);
    expect(c.name, 'Haunt');
    expect(c.statBlock.notes, contains('Ambush'));
    expect(c.statBlock.notes, contains('Cold spot'));
  });

  test('attribution map carries the D&D SRD line', () {
    expect(kContentAttributions['dnd'], contains('System Reference Document'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/content_registry_test.dart`
Expected: FAIL — `content_registry.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/engine/content_registry.dart
import 'models.dart';
import 'spell.dart';

enum ContentType { all, monsters, spells }

class ContentResults {
  const ContentResults({required this.monsters, required this.spells});
  final List<Creature> monsters;
  final List<SpellEntry> spells;
}

/// Pure search over already-loaded content. Case-insensitive substring match on
/// name (plus monster type / spell school). Empty query returns all (filtered).
ContentResults searchContent({
  required String query,
  required ContentType filter,
  String? system,
  List<Creature> monsters = const [],
  List<SpellEntry> spells = const [],
}) {
  final q = query.trim().toLowerCase();
  bool monsterMatch(Creature c) {
    if (system != null && _monsterSystem(c) != system) return false;
    if (q.isEmpty) return true;
    return c.name.toLowerCase().contains(q) ||
        (c.statBlock.creatureType?.toLowerCase().contains(q) ?? false);
  }

  bool spellMatch(SpellEntry s) {
    if (system != null && s.system != system) return false;
    if (q.isEmpty) return true;
    return s.name.toLowerCase().contains(q) ||
        s.school.toLowerCase().contains(q);
  }

  final m = (filter == ContentType.spells)
      ? <Creature>[]
      : monsters.where(monsterMatch).toList();
  final s = (filter == ContentType.monsters)
      ? <SpellEntry>[]
      : spells.where(spellMatch).toList();
  return ContentResults(monsters: m, spells: s);
}

/// Best-effort system inference from a creature id prefix (e.g. "dnd-goblin").
String? _monsterSystem(Creature c) {
  final dash = c.id.indexOf('-');
  return dash > 0 ? c.id.substring(0, dash) : null;
}

/// Adapts an Ironsworn-family [FoeEntry] into the unified [Creature] shape so it
/// shows alongside bundled monsters in the registry. Rank x10 HP (matching the
/// encounter foe picker); tactics + features folded into the stat block notes.
Creature foeEntryToCreature(FoeEntry e) {
  final noteParts = [
    if (e.nature.isNotEmpty) 'Nature: ${e.nature}',
    if (e.tactics.isNotEmpty) 'Tactics: ${e.tactics.join(', ')}',
    if (e.features.isNotEmpty) 'Features: ${e.features.join(', ')}',
  ];
  return Creature(
    id: e.id,
    name: e.name,
    maxHp: e.rank * 10,
    statBlock:
        noteParts.isNotEmpty ? StatBlock(notes: noteParts.join('\n')) : const StatBlock(),
  );
}

/// System -> attribution/license line, shown in the reference footer + settings.
/// Only systems with bundled content appear.
const kContentAttributions = <String, String>{
  'dnd':
      'Includes content from the System Reference Document 5.1, © Wizards of '
          'the Coast LLC, available under the Creative Commons Attribution 4.0 '
          'International License (CC-BY-4.0).',
  'cairn': 'Cairn © Yochai Gal, licensed under CC-BY-SA-4.0.',
  'ose':
      'Compatible with Old-School Essentials (Necrotic Gnome). B/X mechanics; '
          'not affiliated.',
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/content_registry_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/content_registry.dart test/content_registry_test.dart
git commit -m "feat(content): pure content registry — searchContent + foe adapter + attribution"
```

---

## Task 4: Providers — spells + aggregating monster/spell providers

**Files:**
- Modify: `lib/state/providers.dart` (near `systemFoesProvider`, ~line 1810)
- Test: `test/content_providers_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/content_providers_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/spell.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  test('contentMonstersProvider aggregates + de-dups by id', () async {
    final container = ProviderContainer(overrides: [
      // Two systems each contribute a monster; one duplicate id is de-duped.
      systemFoesProvider('dnd').overrideWith((ref) async =>
          [const Creature(id: 'dnd-goblin', name: 'Goblin')]),
      systemFoesProvider('cairn').overrideWith((ref) async =>
          [const Creature(id: 'cairn-wolf', name: 'Wolf')]),
      foesProvider.overrideWith((ref) async => const []),
      bestiaryProvider.overrideWith(() => _FakeBestiary([
            const Creature(id: 'dnd-goblin', name: 'Goblin (dupe)'),
          ])),
      enabledContentSystemsProvider.overrideWith((ref) => ['dnd', 'cairn']),
    ]);
    addTearDown(container.dispose);
    final monsters = await container.read(contentMonstersProvider.future);
    final ids = monsters.map((m) => m.id).toList();
    expect(ids, containsAll(['dnd-goblin', 'cairn-wolf']));
    expect(ids.where((i) => i == 'dnd-goblin').length, 1); // de-duped
  });
}

class _FakeBestiary extends BestiaryNotifier {
  _FakeBestiary(this._seed);
  final List<Creature> _seed;
  @override
  Future<List<Creature>> build() async => _seed;
}
```

> NOTE: if `BestiaryNotifier.build` is not trivially overridable this way, the
> implementer may instead override `bestiaryProvider` with an
> `AsyncNotifierProvider` test double exposing the same `List<Creature>`. The
> assertion (aggregation + de-dup) is what matters.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/content_providers_test.dart`
Expected: FAIL — `systemSpellsProvider`, `contentMonstersProvider`, `enabledContentSystemsProvider` undefined.

- [ ] **Step 3: Add the providers**

After `systemFoesProvider` in `lib/state/providers.dart`, add:

```dart
/// Systems that ship bundled content files (foes_/spells_). Drives aggregation.
const kContentSystemsWithFiles = ['dnd', 'cairn', 'ose'];

/// Enabled systems that also have bundled content files.
final enabledContentSystemsProvider = Provider<List<String>>((ref) {
  final systems =
      ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
          kAllSystems;
  return kContentSystemsWithFiles.where(systems.contains).toList();
});

/// Loads a system-specific spell file (e.g. spells_dnd.json). Empty on absence.
final systemSpellsProvider =
    FutureProvider.family<List<SpellEntry>, String>((ref, system) async {
  try {
    final raw = await rootBundle.loadString('assets/spells_$system.json');
    final list = jsonDecode(raw) as List?;
    return list
            ?.map(SpellEntry.maybeFromJson)
            .whereType<SpellEntry>()
            .toList() ??
        const <SpellEntry>[];
  } catch (_) {
    return const <SpellEntry>[];
  }
});

/// All monsters across enabled systems: bundled creature files + Ironsworn
/// npc_collections (adapted) + the user bestiary. De-duped by id.
final contentMonstersProvider = FutureProvider<List<Creature>>((ref) async {
  final systems = ref.watch(enabledContentSystemsProvider);
  final out = <String, Creature>{};
  for (final sys in systems) {
    for (final c in await ref.watch(systemFoesProvider(sys).future)) {
      out.putIfAbsent(c.id, () => c);
    }
  }
  for (final coll in await ref.watch(foesProvider.future)) {
    for (final e in coll.entries) {
      final c = foeEntryToCreature(e);
      out.putIfAbsent(c.id, () => c);
    }
  }
  for (final c in ref.watch(bestiaryProvider).valueOrNull ?? const <Creature>[]) {
    out.putIfAbsent(c.id, () => c);
  }
  return out.values.toList();
});

/// All spells across enabled systems.
final contentSpellsProvider = FutureProvider<List<SpellEntry>>((ref) async {
  final systems = ref.watch(enabledContentSystemsProvider);
  final out = <SpellEntry>[];
  for (final sys in systems) {
    out.addAll(await ref.watch(systemSpellsProvider(sys).future));
  }
  return out;
});
```

Add imports at the top of `providers.dart` if not present:
```dart
import '../engine/spell.dart';
import '../engine/content_registry.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/content_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/content_providers_test.dart
git commit -m "feat(content): spell + aggregating monster/spell providers"
```

---

## Task 5: Build rail — vendor SRD data + `build_dnd_content.py` + assets

**Files:**
- Create: `data/dnd_srd/spells.json`, `data/dnd_srd/monsters.json` (vendored, committed)
- Create: `build_dnd_content.py`
- Create (generated): `assets/spells_dnd.json`, `assets/foes_dnd.json`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Vendor the SRD source data**

Fetch the CC-BY 5e SRD 5.1 dataset (the `5e-bits/5e-SRD-API` repo's `src/data/2014` JSON — `5e-SRD-Spells.json`, `5e-SRD-Monsters.json`, both CC-BY-4.0 / OGL). Save them as:
- `data/dnd_srd/spells.json`
- `data/dnd_srd/monsters.json`

```bash
mkdir -p data/dnd_srd
curl -fsSL -o data/dnd_srd/spells.json \
  https://raw.githubusercontent.com/5e-bits/5e-database/main/src/2014/5e-SRD-Spells.json
curl -fsSL -o data/dnd_srd/monsters.json \
  https://raw.githubusercontent.com/5e-bits/5e-database/main/src/2014/5e-SRD-Monsters.json
```

Verify each is a non-empty JSON array:
```bash
python3 -c "import json;print('spells',len(json.load(open('data/dnd_srd/spells.json'))))"
python3 -c "import json;print('monsters',len(json.load(open('data/dnd_srd/monsters.json'))))"
```
Expected: ~319 spells, ~334 monsters. (If the upstream path/shape differs, adjust the transform field-mapping in Step 2 to match the actual keys — the field map below targets the 5e-bits schema: spells use `name/level/school.name/casting_time/range/components/material/duration/concentration/ritual/classes[].name/desc[]/higher_level[]`; monsters use `name/armor_class/challenge_rating/type/size/strength.../speed/special_abilities[]/actions[]`.)

- [ ] **Step 2: Write `build_dnd_content.py`**

```python
#!/usr/bin/env python3
"""Generate assets/spells_dnd.json + assets/foes_dnd.json from vendored SRD JSON.

Source: SRD 5.1 (5e-bits/5e-database, CC-BY-4.0 / OGL), vendored under
data/dnd_srd/. The script is the source of truth — edit it, rerun, copy output.
Self-verifies counts, ids, required fields, level/cr ranges. Supports --edition
for the later SRD 5.2 follow-up.

Run: python3 build_dnd_content.py            # edition 5.1 (default)
     python3 build_dnd_content.py --edition 5.2
"""
import argparse
import json
import re
import sys

SCHOOLS = None  # 5e-bits embeds school.name directly.


def slug(name):
    return re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')


def id_for(edition, name):
    prefix = 'dnd' if edition == '5.1' else 'dnd-2024'
    return f'{prefix}-{slug(name)}'


def transform_spell(s, edition):
    desc = '\n\n'.join(s.get('desc') or [])
    higher = '\n\n'.join(s.get('higher_level') or []) or None
    comps = ', '.join(s.get('components') or [])
    if s.get('material'):
        comps = f'{comps} ({s["material"]})' if comps else s['material']
    return {
        'id': id_for(edition, s['name']),
        'system': 'dnd',
        'edition': edition,
        'name': s['name'],
        'level': int(s.get('level', 0)),
        'school': (s.get('school') or {}).get('name', ''),
        'castingTime': s.get('casting_time', ''),
        'range': s.get('range', ''),
        'components': comps,
        'duration': s.get('duration', ''),
        'concentration': bool(s.get('concentration')),
        'ritual': bool(s.get('ritual')),
        'classes': [c.get('name', '') for c in (s.get('classes') or [])],
        'description': desc,
        **({'higherLevels': higher} if higher else {}),
    }


ABIL_KEYS = [('STR', 'strength'), ('DEX', 'dexterity'), ('CON', 'constitution'),
             ('INT', 'intelligence'), ('WIS', 'wisdom'), ('CHA', 'charisma')]


def fmt_speed(sp):
    if isinstance(sp, dict):
        return ', '.join(f'{k} {v}' for k, v in sp.items())
    return str(sp or '')


def transform_monster(m, edition):
    ac = m.get('armor_class')
    if isinstance(ac, list) and ac:
        ac = ac[0].get('value', 0)
    abilities = {k: int(m.get(src, 10)) for k, src in ABIL_KEYS}
    traits = []
    for t in (m.get('special_abilities') or []):
        traits.append({'name': t.get('name', ''), 'text': t.get('desc', '')})
    attacks = []
    for a in (m.get('actions') or []):
        attacks.append({'name': a.get('name', ''), 'detail': a.get('desc', '')})
    cr = m.get('challenge_rating')
    cr_str = ('1/8' if cr == 0.125 else '1/4' if cr == 0.25 else
              '1/2' if cr == 0.5 else str(int(cr)) if isinstance(cr, (int, float)) else str(cr))
    hp = int(m.get('hit_points', 0))
    return {
        'id': id_for(edition, m['name']),
        'name': m['name'],
        'edition': edition,
        'maxHp': hp,
        'statBlock': {
            'ac': int(ac or 0),
            'cr': cr_str,
            'creatureType': (m.get('type') or '').title(),
            'size': m.get('size', ''),
            'speed': fmt_speed(m.get('speed')),
            'abilities': abilities,
            'attacks': [a for a in attacks if a['name']],
            'traits': [t for t in traits if t['name']],
        },
    }


def verify_spells(spells):
    fails, seen = [], set()
    for s in spells:
        if not s['id'] or s['id'] in seen:
            fails.append(f"bad/dup spell id: {s.get('name')!r}")
        seen.add(s['id'])
        if not s['name'] or not s['description']:
            fails.append(f"empty name/desc: {s['id']}")
        if not (0 <= s['level'] <= 9):
            fails.append(f"bad level {s['level']} on {s['id']}")
    return fails


def verify_monsters(monsters):
    fails, seen = [], set()
    for m in monsters:
        if not m['id'] or m['id'] in seen:
            fails.append(f"bad/dup monster id: {m.get('name')!r}")
        seen.add(m['id'])
        if not m['name']:
            fails.append(f"empty name: {m['id']}")
        if not m['statBlock']['abilities']:
            fails.append(f"no abilities: {m['id']}")
    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--edition', default='5.1', choices=['5.1', '5.2'])
    args = ap.parse_args()
    src_spells = json.load(open('data/dnd_srd/spells.json'))
    src_monsters = json.load(open('data/dnd_srd/monsters.json'))
    spells = [transform_spell(s, args.edition) for s in src_spells]
    monsters = [transform_monster(m, args.edition) for m in src_monsters]
    fails = verify_spells(spells) + verify_monsters(monsters)
    if not spells or not monsters:
        fails.append('empty output')
    if fails:
        print('VERIFICATION FAILED:')
        for f in fails:
            print('  -', f)
        sys.exit(1)
    suffix = '' if args.edition == '5.1' else '_2024'
    with open(f'assets/spells_dnd{suffix}.json', 'w') as f:
        json.dump(spells, f, ensure_ascii=False, indent=2)
    with open(f'assets/foes_dnd{suffix}.json', 'w') as f:
        json.dump(monsters, f, ensure_ascii=False, indent=2)
    print(f'spells_dnd{suffix}.json: {len(spells)} · '
          f'foes_dnd{suffix}.json: {len(monsters)}. All checks passed.')


if __name__ == '__main__':
    main()
```

- [ ] **Step 3: Run the build**

Run: `python3 build_dnd_content.py`
Expected: `spells_dnd.json: ~319 · foes_dnd.json: ~334. All checks passed.`

- [ ] **Step 4: Register the assets in `pubspec.yaml`**

After `- assets/foes_ose.json`, add:
```yaml
    - assets/spells_dnd.json
    - assets/foes_dnd.json
```

- [ ] **Step 5: Sanity-check parse with a quick Dart smoke (optional but recommended)**

Run: `python3 -c "import json; d=json.load(open('assets/foes_dnd.json')); print(d[0]['name'], d[0]['statBlock']['cr'])"`
Expected: a monster name + CR prints.

- [ ] **Step 6: Commit**

```bash
git add data/dnd_srd build_dnd_content.py assets/spells_dnd.json assets/foes_dnd.json pubspec.yaml
git commit -m "feat(content): D&D 5e SRD build rail + spells_dnd/foes_dnd assets"
```

---

## Task 6: `SpellCard` + `StatBlockView` enrichment

**Files:**
- Create: `lib/features/reference_view.dart` (SpellCard here; ReferenceView in Task 7)
- Modify: `lib/features/sheet_widgets.dart` (`StatBlockView`)
- Test: `test/reference_view_test.dart` (SpellCard portion)

- [ ] **Step 1: Write the failing test**

```dart
// test/reference_view_test.dart (part 1)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/spell.dart';
import 'package:juice_oracle/features/reference_view.dart';

void main() {
  testWidgets('SpellCard renders name, level/school, and description', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SpellCard(
          spell: SpellEntry(
            id: 'dnd-fireball', system: 'dnd', name: 'Fireball', level: 3,
            school: 'Evocation', castingTime: '1 action', range: '150 feet',
            components: 'V, S, M', duration: 'Instantaneous',
            description: 'A bright streak flashes.', concentration: false,
          ),
        ),
      ),
    ));
    expect(find.text('Fireball'), findsOneWidget);
    expect(find.textContaining('Evocation'), findsOneWidget);
    expect(find.textContaining('A bright streak'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/reference_view_test.dart`
Expected: FAIL — `SpellCard` undefined.

- [ ] **Step 3: Implement `SpellCard` in `reference_view.dart`**

```dart
// lib/features/reference_view.dart
import 'package:flutter/material.dart';
import '../engine/spell.dart';

/// Read-only glance card for a spell. Pure display; no state.
class SpellCard extends StatelessWidget {
  const SpellCard({super.key, required this.spell});
  final SpellEntry spell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final levelLabel =
        spell.level == 0 ? 'Cantrip' : 'Level ${spell.level}';
    final meta = [
      if (spell.castingTime.isNotEmpty) 'Casting: ${spell.castingTime}',
      if (spell.range.isNotEmpty) 'Range: ${spell.range}',
      if (spell.components.isNotEmpty) 'Components: ${spell.components}',
      if (spell.duration.isNotEmpty) 'Duration: ${spell.duration}',
    ].join('\n');
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(spell.name, style: theme.textTheme.titleLarge),
          Text(
            [levelLabel, if (spell.school.isNotEmpty) spell.school].join(' · '),
            style: theme.textTheme.labelMedium!
                .copyWith(color: theme.colorScheme.primary),
          ),
          Wrap(spacing: 6, children: [
            if (spell.concentration) const Chip(label: Text('Concentration')),
            if (spell.ritual) const Chip(label: Text('Ritual')),
            if (spell.classes.isNotEmpty)
              Chip(label: Text(spell.classes.join(', '))),
          ]),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(meta, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Text(spell.description, style: theme.textTheme.bodyMedium),
          if (spell.higherLevels != null) ...[
            const SizedBox(height: 8),
            Text('At Higher Levels', style: theme.textTheme.titleSmall),
            Text(spell.higherLevels!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Extend `StatBlockView`**

In `lib/features/sheet_widgets.dart`, find `StatBlockView`'s build and add a header line + abilities row + traits list when the new fields are present. Add, near the top of the rendered column (after the AC/existing fields), guarded blocks:

```dart
        if (sb.cr != null || sb.creatureType != null || sb.size != null)
          Text(
            [
              if (sb.size != null) sb.size,
              if (sb.creatureType != null) sb.creatureType,
              if (sb.cr != null) 'CR ${sb.cr}',
            ].whereType<String>().join(' · '),
            style: Theme.of(context).textTheme.labelMedium,
          ),
        if (sb.abilities != null && sb.abilities!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              sb.abilities!.entries
                  .map((e) => '${e.key} ${e.value}')
                  .join('  '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (sb.traits != null)
          for (final tr in sb.traits!)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodySmall,
                  children: [
                    TextSpan(
                        text: '${tr.name}. ',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: tr.text),
                  ],
                ),
              ),
            ),
```

> Confirm the local variable name for the stat block inside `StatBlockView.build` (likely `statBlock` or `sb`) and use it consistently; the snippet assumes `sb`.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/reference_view_test.dart`
Expected: PASS (SpellCard test).

- [ ] **Step 6: Commit**

```bash
git add lib/features/reference_view.dart lib/features/sheet_widgets.dart test/reference_view_test.dart
git commit -m "feat(content): SpellCard + StatBlockView renders cr/abilities/traits"
```

---

## Task 7: `ReferenceView` — search + filters + glance

**Files:**
- Modify: `lib/features/reference_view.dart` (add `ReferenceView`)
- Test: `test/reference_view_test.dart` (add ReferenceView widget tests)

- [ ] **Step 1: Write the failing test**

```dart
// test/reference_view_test.dart (part 2 — add to the same file)
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/content_registry.dart';
import 'package:juice_oracle/state/providers.dart';

  testWidgets('ReferenceView lists results and opens a spell glance', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        contentMonstersProvider.overrideWith((ref) async =>
            [const Creature(id: 'dnd-goblin', name: 'Goblin')]),
        contentSpellsProvider.overrideWith((ref) async =>
            [const SpellEntry(id: 'dnd-fireball', system: 'dnd', name: 'Fireball', level: 3, description: 'Boom.')]),
      ],
      child: const MaterialApp(home: Scaffold(body: ReferenceView())),
    ));
    await t.pumpAndSettle();
    expect(find.text('Goblin'), findsOneWidget);
    expect(find.text('Fireball'), findsOneWidget);

    await t.enterText(find.byKey(const Key('reference-search')), 'fire');
    await t.pumpAndSettle();
    expect(find.text('Goblin'), findsNothing);
    expect(find.text('Fireball'), findsOneWidget);

    await t.tap(find.byKey(const Key('reference-spell-dnd-fireball')));
    await t.pumpAndSettle();
    expect(find.textContaining('Boom.'), findsOneWidget); // glance opened
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/reference_view_test.dart`
Expected: FAIL — `ReferenceView` undefined.

- [ ] **Step 3: Implement `ReferenceView`**

Add to `lib/features/reference_view.dart` (add imports for riverpod, models, content_registry, providers, sheet_widgets, and `initialQuery`/`initialType` params for slash-command deep-linking used in Task 10):

```dart
class ReferenceView extends ConsumerStatefulWidget {
  const ReferenceView({
    super.key,
    this.initialQuery = '',
    this.initialType = ContentType.all,
  });
  final String initialQuery;
  final ContentType initialType;

  @override
  ConsumerState<ReferenceView> createState() => _ReferenceViewState();
}

class _ReferenceViewState extends ConsumerState<ReferenceView> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialQuery);
  late ContentType _type = widget.initialType;
  String? _system; // null = all systems

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final monsters =
        ref.watch(contentMonstersProvider).valueOrNull ?? const <Creature>[];
    final spells =
        ref.watch(contentSpellsProvider).valueOrNull ?? const <SpellEntry>[];
    final results = searchContent(
      query: _ctrl.text,
      filter: _type,
      system: _system,
      monsters: monsters,
      spells: spells,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            key: const Key('reference-search'),
            controller: _ctrl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search spells & monsters',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SegmentedButton<ContentType>(
          segments: const [
            ButtonSegment(value: ContentType.all, label: Text('All')),
            ButtonSegment(value: ContentType.monsters, label: Text('Monsters')),
            ButtonSegment(value: ContentType.spells, label: Text('Spells')),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final s in results.spells)
                ListTile(
                  key: Key('reference-spell-${s.id}'),
                  dense: true,
                  leading: const Icon(Icons.auto_fix_high),
                  title: Text(s.name),
                  subtitle: Text(
                      s.level == 0 ? 'Cantrip · ${s.school}' : 'Lvl ${s.level} · ${s.school}'),
                  onTap: () => _glance(context, spell: s),
                ),
              for (final m in results.monsters)
                ListTile(
                  key: Key('reference-monster-${m.id}'),
                  dense: true,
                  leading: const Icon(Icons.pets),
                  title: Text(m.name),
                  subtitle: Text([
                    if (m.statBlock.cr != null) 'CR ${m.statBlock.cr}',
                    if (m.maxHp > 0) 'HP ${m.maxHp}',
                  ].join(' · ')),
                  onTap: () => _glance(context, monster: m),
                ),
            ],
          ),
        ),
        const _AttributionFooter(),
      ],
    );
  }

  void _glance(BuildContext context, {SpellEntry? spell, Creature? monster}) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 360,
            child: spell != null
                ? SpellCard(spell: spell)
                : StatBlockView(statBlock: monster!.statBlock, title: monster.name),
          ),
        ),
      ),
    );
  }
}

class _AttributionFooter extends StatelessWidget {
  const _AttributionFooter();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: const Key('reference-sources'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Sources & licenses'),
            content: SingleChildScrollView(
              child: Text(kContentAttributions.values.join('\n\n')),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
        child: const Text('Sources & licenses'),
      ),
    );
  }
}
```

> Confirm `StatBlockView`'s constructor params (it currently takes the stat block + a title — verify the exact names in `sheet_widgets.dart` and match them).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/reference_view_test.dart`
Expected: PASS (all parts).

- [ ] **Step 5: Commit**

```bash
git add lib/features/reference_view.dart test/reference_view_test.dart
git commit -m "feat(content): ReferenceView — search/filter/glance + sources footer"
```

---

## Task 8: Ask "Reference" tab

**Files:**
- Modify: `lib/features/oracles_tab.dart`
- Test: `test/oracles_tab_test.dart` (or extend home_shell coverage)

- [ ] **Step 1: Write the failing test**

```dart
// test/oracles_tab_reference_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/features/oracles_tab.dart';
// ... plus the standard test fixtures/overrides used by other oracles_tab tests.

void main() {
  testWidgets('Ask shows a Reference tab', (t) async {
    SharedPreferences.setMockInitialValues({});
    // Pump OraclesTab with the project's standard provider overrides
    // (oracle/verdant/emulator/ruleset data + mock prefs) per the
    // rootBundle-hang rule; see test/widget_test_helpers.dart.
    // ... build the widget under ProviderScope with a loaded Oracle ...
    // Then:
    expect(find.text('Reference'), findsOneWidget);
  });
}
```

> Use the same fixture/override harness the existing `oracles_tab`/`home_shell`
> tests use (see [[juice-widget-test-rootbundle-hang]] — never call `*.load()`;
> override the data providers with file fixtures + `setMockInitialValues`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/oracles_tab_reference_test.dart`
Expected: FAIL — no "Reference" tab.

- [ ] **Step 3: Add the tab**

In `lib/features/oracles_tab.dart`, add a Reference subtab (always present, both modes):

```dart
    final tabs = <SubtabDef>[
      const SubtabDef('oracle', 'Oracle'),
      const SubtabDef('tables', 'Tables'),
      const SubtabDef('reference', 'Reference'),
      if (lonelog) const SubtabDef('lonelog', 'Lonelog'),
    ];
    final children = <Widget>[
      FateScreen(oracle: oracle, initialSection: FateSection.fateCheck),
      TablesScreen(oracle: oracle),
      const ReferenceView(),
      if (lonelog) const LonelogReferenceScreen(),
    ];
```

Add `import 'reference_view.dart';` at the top.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/oracles_tab_reference_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/oracles_tab.dart test/oracles_tab_reference_test.dart
git commit -m "feat(content): Reference tab under Ask (always available)"
```

---

## Task 9: Run-screen reference lookup panel

**Files:**
- Modify: `lib/features/run_screen.dart`
- Test: `test/run_screen_test.dart` (extend)

- [ ] **Step 1: Write the failing test**

```dart
// add to test/run_screen_test.dart
  testWidgets('Run screen shows a reference lookup panel', (t) async {
    // Pump RunScreen under the project's standard run-screen test harness
    // (encounter/scene/oracle provider overrides). Then:
    expect(find.byKey(const Key('run-panel-reference')), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/run_screen_test.dart`
Expected: FAIL — panel absent.

- [ ] **Step 3: Add `_ReferencePanel`**

In `lib/features/run_screen.dart`, add a panel that embeds `ReferenceView` inside the existing `_Panel` shell, and include it in the grid composition next to the other panels:

```dart
class _ReferencePanel extends StatelessWidget {
  const _ReferencePanel();
  @override
  Widget build(BuildContext context) {
    return _Panel(
      k: const Key('run-panel-reference'),
      title: 'Reference',
      child: SizedBox(height: 320, child: const ReferenceView()),
    );
  }
}
```

Add `import 'reference_view.dart';` and place `const _ReferencePanel()` in the panel list (follow the existing pattern for how panels are laid into the 2-col / stacked grid).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/run_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/run_screen.dart test/run_screen_test.dart
git commit -m "feat(content): Run-screen reference lookup panel"
```

---

## Task 10: Slash commands `/lookup` `/spell` `/monster`

**Files:**
- Modify: `lib/features/journal_screen.dart`
- Test: `test/journal_slash_reference_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/journal_slash_reference_test.dart
  testWidgets('/spell opens the reference filtered to spells', (t) async {
    // Pump JournalScreen under the standard journal test harness
    // (see test/widget_test_helpers.dart — override data providers + mock prefs).
    await t.enterText(find.byKey(const Key('journal-composer')), '/spell fire');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    // ReferenceView opened (as a pushed route / sheet) pre-filtered:
    expect(find.byKey(const Key('reference-search')), findsOneWidget);
    expect(find.text('fire'), findsOneWidget);
  });
```

> Use the composer key actually used by the journal (confirm — likely
> `journal-composer` or similar) and the same harness as other journal tests.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/journal_slash_reference_test.dart`
Expected: FAIL — command not handled.

- [ ] **Step 3: Add the builtins + dispatch + palette entries**

In `lib/features/journal_screen.dart`:

1. Add constants near line 108:
```dart
  static const _builtinLookup = 'lookup';
  static const _builtinSpell = 'spell';
  static const _builtinMonster = 'monster';
```

2. Add a helper that opens the reference pre-filtered:
```dart
  void _openReference(String query, ContentType type) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Reference')),
        body: ReferenceView(initialQuery: query, initialType: type),
      ),
    ));
  }
```
Add `import 'reference_view.dart';` and `import '../engine/content_registry.dart';`.

3. In the `text.startsWith('/')` dispatch (after the `_builtinThread` block, ~line 1822), add:
```dart
      if (_builtinLookup == tok) {
        _composer.clear();
        _openReference(parsed.rest.trim(), ContentType.all);
        return;
      }
      if (_builtinSpell == tok) {
        _composer.clear();
        _openReference(parsed.rest.trim(), ContentType.spells);
        return;
      }
      if (_builtinMonster == tok) {
        _composer.clear();
        _openReference(parsed.rest.trim(), ContentType.monsters);
        return;
      }
```

4. In `_slashPalette()` (~line 1240) add show-flags + palette rows mirroring the `/roll` entry:
```dart
    final showLookup = _builtinLookup.startsWith(tok);
    final showSpell = _builtinSpell.startsWith(tok);
    final showMonster = _builtinMonster.startsWith(tok);
```
and add three palette items (copy the structure of the `/spread` item) with commands `/lookup`, `/spell`, `/monster` and short descriptions ("Look up any spell or monster", "Look up a spell", "Look up a monster"), each gated on its show-flag and calling the same `_openReference` on tap.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/journal_slash_reference_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/journal_screen.dart test/journal_slash_reference_test.dart
git commit -m "feat(content): /lookup //spell //monster slash commands"
```

---

## Task 11: Encounter "Add from reference" (unified monster picker)

**Files:**
- Modify: `lib/features/encounter_screen.dart`
- Test: `test/encounter_reference_add_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/encounter_reference_add_test.dart
  testWidgets('Add from reference adds a combatant with the stat block', (t) async {
    // Pump EncounterScreen under the standard encounter harness, overriding
    // contentMonstersProvider with a single enriched creature:
    //   Creature(id:'dnd-goblin', name:'Goblin', maxHp:7,
    //            statBlock: StatBlock(ac:15, cr:'1/4'))
    await t.tap(find.byKey(const Key('add-from-reference')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ref-monster-pick-dnd-goblin')));
    await t.pumpAndSettle();
    expect(find.text('Goblin'), findsWidgets); // combatant row present
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/encounter_reference_add_test.dart`
Expected: FAIL — button absent.

- [ ] **Step 3: Implement**

In `_addButtons` add a full-width button when `contentMonstersProvider` is non-empty:
```dart
    final refMonsters =
        ref.watch(contentMonstersProvider).valueOrNull ?? const <Creature>[];
    // ... inside the Column, after the existing system foe buttons:
          if (refMonsters.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('add-from-reference'),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Add from reference'),
                onPressed: () => _addFromReference(context, ref, refMonsters),
              ),
            ),
          ],
```

Add the handler + a picker dialog (reuse the `_SystemCreaturePickerDialog` pattern, but with key prefix `ref-monster-pick-`):
```dart
  Future<void> _addFromReference(
      BuildContext context, WidgetRef ref, List<Creature> creatures) async {
    final creature = await showDialog<Creature>(
      context: context,
      builder: (_) => _ReferenceMonsterPicker(creatures: creatures),
    );
    if (creature == null) return;
    await ref.read(encounterProvider.notifier).addCombatant(Combatant(
          id: _newId(),
          name: creature.name,
          initiative: 0,
          track: creature.maxHp > 0
              ? CharTrack(label: 'HP', current: creature.maxHp, max: creature.maxHp)
              : null,
          statBlock: creature.statBlock.isEmpty ? null : creature.statBlock,
        ));
  }
```

Add `_ReferenceMonsterPicker` (a `StatelessWidget` like `_SystemCreaturePickerDialog`, list keyed `ref-monster-pick-${cr.id}`, subtitle shows CR/HP, with a search field for the ~330-entry D&D list — reuse a simple `TextField` filter via a small `StatefulWidget`). Add `import '../engine/content_registry.dart';` if needed for any types.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/encounter_reference_add_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/encounter_screen.dart test/encounter_reference_add_test.dart
git commit -m "feat(content): encounter Add-from-reference unified monster picker"
```

---

## Task 12: D&D caster-sheet spell picker + glance

**Files:**
- Modify: `lib/engine/models.dart` (`DndSheet.spellIds`)
- Modify: `lib/features/dnd_sheet.dart`
- Test: `test/dnd_spellids_test.dart`, `test/dnd_sheet_spell_picker_test.dart`

- [ ] **Step 1: Write the failing model test**

```dart
// test/dnd_spellids_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('DndSheet.spellIds round-trips and defaults empty', () {
    expect(const DndSheet().spellIds, isEmpty);
    final s = const DndSheet().copyWith(spellIds: ['dnd-fireball']);
    final back = DndSheet.maybeFromJson(s.toJson())!;
    expect(back.spellIds, ['dnd-fireball']);
  });
}
```

- [ ] **Step 2: Run + fail**

Run: `flutter test test/dnd_spellids_test.dart`
Expected: FAIL — `spellIds` undefined.

- [ ] **Step 3: Add `spellIds` to `DndSheet`**

Add field `this.spellIds = const []` to the constructor; `final List<String> spellIds;`; thread through `copyWith` (`List<String>? spellIds`), `toJson` (`if (spellIds.isNotEmpty) 'spellIds': spellIds`), and `maybeFromJson` (`spellIds: ((j['spellIds'] as List?) ?? const []).cast<String>()`).

- [ ] **Step 4: Run + pass**

Run: `flutter test test/dnd_spellids_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the picker widget test**

```dart
// test/dnd_sheet_spell_picker_test.dart
  testWidgets('attach a spell then glance it', (t) async {
    // Pump the D&D sheet for a caster character under the standard sheet harness,
    // overriding contentSpellsProvider with [Fireball]. Then:
    await t.tap(find.byKey(const Key('dnd-spell-add')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('dnd-spell-pick-dnd-fireball')));
    await t.pumpAndSettle();
    expect(find.text('Fireball'), findsWidgets); // now in prepared list
    await t.tap(find.byKey(const Key('dnd-spell-view-dnd-fireball')));
    await t.pumpAndSettle();
    expect(find.textContaining('Boom.'), findsOneWidget); // SpellCard glance
  });
```

- [ ] **Step 6: Run + fail**

Run: `flutter test test/dnd_sheet_spell_picker_test.dart`
Expected: FAIL.

- [ ] **Step 7: Implement the spell section in `dnd_sheet.dart`**

In the Spellcasting section, add (for caster characters):
- An "Add spell" button (`dnd-spell-add`) → a picker dialog listing `contentSpellsProvider` spells (filter by name; optionally by level/class), items keyed `dnd-spell-pick-<id>`; on tap, append the id to `sheet.spellIds` via `_save(ref, s.copyWith(spellIds: [...s.spellIds, id]))` (de-dup).
- A prepared-spells list rendering each attached spell resolved from the registry (`contentSpellsProvider`), grouped by level; each row keyed `dnd-spell-view-<id>` opens a `SpellCard` dialog; a remove affordance (`dnd-spell-del-<id>`) drops the id.
- Keep the existing freeform `preparedSpells` text field below, relabeled "Notes".

Add `import 'reference_view.dart';` (SpellCard) and read `ref.watch(contentSpellsProvider)`.

- [ ] **Step 8: Run + pass**

Run: `flutter test test/dnd_sheet_spell_picker_test.dart`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/engine/models.dart lib/features/dnd_sheet.dart test/dnd_spellids_test.dart test/dnd_sheet_spell_picker_test.dart
git commit -m "feat(content): D&D sheet spell picker (spellIds) + SpellCard glance"
```

---

## Task 13: Settings "Sources & licenses" section

**Files:**
- Modify: `lib/features/settings_sheet.dart`
- Test: `test/settings_sources_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/settings_sources_test.dart
  testWidgets('Settings shows a Sources & licenses entry', (t) async {
    // Pump showSettingsSheet under the standard settings harness. Then:
    expect(find.text('Sources & licenses'), findsWidgets);
  });
```

- [ ] **Step 2: Run + fail**

Run: `flutter test test/settings_sources_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `settings_sheet.dart`, add a section/list tile "Sources & licenses" (key `settings-sources`) that opens an AlertDialog showing `kContentAttributions.values.join('\n\n')` (import `../engine/content_registry.dart`).

- [ ] **Step 4: Run + pass**

Run: `flutter test test/settings_sources_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings_sheet.dart test/settings_sources_test.dart
git commit -m "feat(content): Settings Sources & licenses section"
```

---

## Task 14: Full verification + docs + memory

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 3: Document in `CLAUDE.md`**

Add a "Content library (spells & monsters)" bullet near the bestiary/encounter notes describing: the unified `contentRegistry` (Approach A); `SpellEntry` + enriched `StatBlock` + `Creature.edition`; the providers (`systemSpellsProvider`/`contentMonstersProvider`/`contentSpellsProvider`/`enabledContentSystemsProvider` + `kContentSystemsWithFiles`); `build_dnd_content.py` rail (vendored SRD under `data/dnd_srd/`, `--edition`, never edit emitted JSON); surfaces (Ask Reference tab + Run `run-panel-reference` + `/lookup` `/spell` `/monster` + encounter `add-from-reference` + D&D `spellIds` picker); attribution (`kContentAttributions` → reference footer + settings); and the licensing-posture shift (vendored-content-with-attribution OK for free licenses; Shadowdark/Kal-Arath still blocked). Point to the spec.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(content): document the content library in CLAUDE.md"
```

- [ ] **Step 5: Ship**

Invoke `/ship-pr` with title:
`feat(content): D&D 5e SRD spells & monsters + unified GM quick-reference`

---

## Self-Review

**Spec coverage:**
- §1 data model → Tasks 1, 2. ✓
- §2 registry → Tasks 3, 4. ✓
- §3 build rail + D&D data → Task 5. ✓
- §4 attribution → Tasks 3 (map), 7 (footer), 13 (settings). ✓
- §5 reference surface (Ask/Run/slash) → Tasks 7, 8, 9, 10. ✓
- §6 opportunistic wiring (encounter, D&D sheet) → Tasks 11, 12. ✓
- §7a edition-awareness → Tasks 1, 2 (field) + Task 5 (`--edition`). ✓
- §7 testing → every task is TDD; Task 14 full verify. ✓

**Placeholder scan:** No "TBD"/"handle edge cases". Two tasks (8, 9, 10, 12, 13) reference the project's existing widget-test harness rather than re-pasting fixture boilerplate — intentional, because the rootBundle-hang rule ([[juice-widget-test-rootbundle-hang]]) requires the standard overrides and re-pasting them risks drift; each names the exact keys/assertions to add.

**Type consistency:** `SpellEntry`, `StatTrait`, `StatBlock`(+cr/creatureType/size/abilities/traits), `Creature.edition`, `ContentType{all,monsters,spells}`, `ContentResults{monsters,spells}`, `searchContent({query,filter,system,monsters,spells})`, `foeEntryToCreature`, `kContentAttributions`, `kContentSystemsWithFiles`, `enabledContentSystemsProvider`, `systemSpellsProvider`, `contentMonstersProvider`, `contentSpellsProvider`, `ReferenceView{initialQuery,initialType}`, `SpellCard{spell}`, `DndSheet.spellIds` — names used identically across tasks. ✓

**Open implementation confirmations (flagged inline, not blockers):** exact `StatBlockView` constructor param names; the journal composer's widget key; whether `BestiaryNotifier.build` is override-friendly in tests (fallback noted).
