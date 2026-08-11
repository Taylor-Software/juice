# Polarity Grammar Magic Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Embed the sibling `polarity_grammar` package (The Polarity Grammar magic system) into juice/loreseer as an opt-in, per-character casting panel available on all 15 premade character sheets.

**Architecture:** Pin `polarity_grammar` as a git dependency. Bridge juice's `Character` to the package's own narrower `Character` record via a new `Character.polarityId` field. Port the standalone app's `LibraryController` (Riverpod `AsyncNotifier<Library>`) into a new session-scoped `MagicController`, persisted through a `JuiceMagicStore` adapter implementing the package's `TextLibraryStore`. Surface it via one shared `magicSection()` widget (mirrors the existing `conditionsSection()` precedent) dropped into all 15 sheet files, wiring the package's own `ManaBar`/`SpellbookList`/`SpellBuilderScreen`/`CardReferenceScreen`/`ConversionCalculator`/`UserGuideScreen` widgets directly.

**Tech Stack:** Flutter, Riverpod (`AsyncNotifier`), `shared_preferences`, the `polarity_grammar` package (git dependency, no state-mgmt deps of its own).

## Global Constraints

- Package source: `https://github.com/Taylor-Software/practical-magic.git`, path `packages/polarity_grammar`, pinned to commit `b1704876ce64156d1896e5836073c8aabc4dbe88` (current `working` branch HEAD as of 2026-08-11 — bump this ref by hand for future `magic` changes, never track a branch).
- Persisted keys use the `loreseer.` prefix everywhere in this codebase (NOT `juice.` — CLAUDE.md's note that `juice.*` keys are kept for stability is stale). New key: `loreseer.magic.v1.<sessionId>`.
- Import the package aliased everywhere it's used: `import 'package:polarity_grammar/polarity_grammar.dart' as pg;` — its `Character`/`Library`/`Spell` collide with juice's own types of the same name.
- No campaign-level system flag. Magic is a per-character toggle (`Character.polarityId`), available regardless of which ruleset sheet a character uses — same posture as `CharacterRole`/`conditions`.
- P1 wires the full standalone-app feature set: build, price, save, cast, browse the card reference, run the conversion calculator, read the user guide. Backup/sharing JSON import-export (the package's own per-character copy/share feature) is explicitly OUT of scope — juice's existing whole-campaign export already carries this data.
- Spec: `docs/superpowers/specs/2026-08-11-polarity-grammar-magic-design.md`.

---

### Task 1: Add the `polarity_grammar` git dependency

**Files:**
- Modify: `pubspec.yaml`
- Test: `test/polarity_grammar_dependency_test.dart`

**Interfaces:**
- Produces: the `polarity_grammar` package importable as `package:polarity_grammar/polarity_grammar.dart` throughout the rest of this plan.

- [ ] **Step 1: Write the failing test**

```dart
// test/polarity_grammar_dependency_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:polarity_grammar/polarity_grammar.dart' as pg;

void main() {
  test('polarity_grammar package resolves and its effect deck loads', () {
    // 44 effect pairs per the ruleset (polarity-grammar.md §2).
    expect(pg.kEffects.length, 44);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/polarity_grammar_dependency_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:polarity_grammar/polarity_grammar.dart'` (the dependency isn't declared yet).

- [ ] **Step 3: Add the dependency**

In `pubspec.yaml`, under `dependencies:` (alongside the other packages), add:

```yaml
  polarity_grammar:
    git:
      url: https://github.com/Taylor-Software/practical-magic.git
      path: packages/polarity_grammar
      ref: b1704876ce64156d1896e5836073c8aabc4dbe88
```

Then run: `flutter pub get`

Note: fetching a private git dependency requires whatever git credentials the environment already uses to reach `github.com/Taylor-Software` — the same mechanism this repo's own remote already relies on. If `flutter pub get` fails with an auth error here, that's an environment/credential problem to resolve before continuing, not a plan defect.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/polarity_grammar_dependency_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock test/polarity_grammar_dependency_test.dart
git commit -m "feat(magic): add polarity_grammar git dependency"
```

---

### Task 2: `Character.polarityId`

**Files:**
- Modify: `lib/engine/models/character.dart`
- Test: `test/character_polarity_id_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Character.polarityId` (`String?`), `Character.copyWith({String? polarityId, bool clearPolarityId = false, ...})` — later tasks read/write this to link a juice `Character` to a `pg.Character`.

- [ ] **Step 1: Write the failing test**

```dart
// test/character_polarity_id_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';

void main() {
  test('Character.polarityId round-trips through JSON', () {
    const c = Character(id: 'c1', name: 'Ash', polarityId: 'pg-1');
    final decoded = Character.fromJson(c.toJson());
    expect(decoded.polarityId, 'pg-1');
  });

  test('Character.polarityId is omitted from JSON when null', () {
    const c = Character(id: 'c1', name: 'Ash');
    expect(c.toJson().containsKey('polarityId'), isFalse);
  });

  test('copyWith clearPolarityId nulls it out', () {
    const c = Character(id: 'c1', name: 'Ash', polarityId: 'pg-1');
    final cleared = c.copyWith(clearPolarityId: true);
    expect(cleared.polarityId, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/character_polarity_id_test.dart`
Expected: FAIL — `No named parameter with the name 'polarityId'`.

- [ ] **Step 3: Add the field**

In `lib/engine/models/character.dart`, five edits to the `Character` class (mirror the existing `coins`/`funnel` fields exactly — `coins` is the last constructor param/field, `funnel` is the last nullable-sheet param):

1. Constructor — add after `this.coins = 0,`:
```dart
    this.polarityId,
```

2. Field — add after `final int coins;`:
```dart
  /// Links to a `pg.Character.id` in the campaign's Polarity Grammar
  /// [Library] when this character has opted into magic casting; null
  /// otherwise. See `lib/state/magic_controller.dart`.
  final String? polarityId;
```

3. `copyWith` params — add after `int? coins,`:
```dart
    String? polarityId,
    bool clearPolarityId = false,
```

4. `copyWith` body — add after `coins: coins ?? this.coins,`:
```dart
        polarityId: clearPolarityId ? null : (polarityId ?? this.polarityId),
```

5. `toJson` — add after `if (coins != 0) 'coins': coins,`:
```dart
        if (polarityId != null) 'polarityId': polarityId,
```

6. `fromJson` — add after `coins: (j['coins'] as int?) ?? 0,`:
```dart
        polarityId: j['polarityId'] as String?,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/character_polarity_id_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models/character.dart test/character_polarity_id_test.dart
git commit -m "feat(magic): add Character.polarityId link field"
```

---

### Task 3: `JuiceMagicStore` persistence adapter

**Files:**
- Create: `lib/state/magic_controller.dart`
- Modify: `lib/state/providers.dart` (add `'loreseer.magic.v1'` to `sessionScopedKeys`)
- Test: `test/magic_store_test.dart`

**Interfaces:**
- Consumes: `pg.TextLibraryStore`, `pg.Library`, `pg.kQuarantineKeep` (from `package:polarity_grammar/polarity_grammar.dart`).
- Produces: `JuiceMagicStore(SharedPreferences prefs, String sessionId)` implementing `pg.TextLibraryStore` — `Future<pg.Library> load()`, `Future<void> save(pg.Library)`. Task 4 builds `MagicController` on top of this.

- [ ] **Step 1: Write the failing test**

```dart
// test/magic_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/state/magic_controller.dart';
import 'package:polarity_grammar/polarity_grammar.dart' as pg;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('JuiceMagicStore round-trips a Library through SharedPreferences',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = JuiceMagicStore(prefs, 'campaign-1');
    const lib = pg.Library(
      characters: [
        pg.Character(id: 'pg-1', name: 'Ash', baseMana: 4, currentMana: 4),
      ],
      spells: [],
    );
    await store.save(lib);
    final loaded = await store.load();
    expect(loaded.characters.single.id, 'pg-1');
    expect(prefs.getString('loreseer.magic.v1.campaign-1'), isNotNull);
  });

  test('JuiceMagicStore quarantines corrupt data and returns an empty library',
      () async {
    SharedPreferences.setMockInitialValues({
      'loreseer.magic.v1.campaign-1': 'not json',
    });
    final prefs = await SharedPreferences.getInstance();
    final store = JuiceMagicStore(prefs, 'campaign-1');
    final loaded = await store.load();
    expect(loaded.characters, isEmpty);
    expect(
      prefs.getString('loreseer.magic.v1.campaign-1.quarantine.0'),
      'not json',
    );
  });

  test('JuiceMagicStore is scoped per session — two sessions do not collide',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storeA = JuiceMagicStore(prefs, 'a');
    final storeB = JuiceMagicStore(prefs, 'b');
    await storeA.save(const pg.Library(
      characters: [pg.Character(id: 'x', name: 'X', baseMana: 4, currentMana: 4)],
      spells: [],
    ));
    final loadedB = await storeB.load();
    expect(loadedB.characters, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/magic_store_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'loreseer' in 'package:loreseer/state/magic_controller.dart'` (file doesn't exist yet).

- [ ] **Step 3: Implement `JuiceMagicStore`**

```dart
// lib/state/magic_controller.dart
import 'package:polarity_grammar/polarity_grammar.dart' as pg;
import 'package:shared_preferences/shared_preferences.dart';

/// [pg.PolarityStore] over [SharedPreferences], scoped to one campaign
/// session — mirrors the `<base>.<sessionId>` convention every other
/// per-campaign store in this app uses. The package's [pg.TextLibraryStore]
/// already owns JSON (de)serialization, corrupt-data quarantine, and
/// schema-too-new handling; this adapter only supplies raw string IO.
class JuiceMagicStore extends pg.TextLibraryStore {
  JuiceMagicStore(this._prefs, String sessionId)
      : _key = 'loreseer.magic.v1.$sessionId';

  final SharedPreferences _prefs;
  final String _key;

  String _quarantineKey(int i) => '$_key.quarantine.$i';

  @override
  Future<String?> readRaw() async => _prefs.getString(_key);

  @override
  Future<void> writeRaw(String data) async {
    await _prefs.setString(_key, data);
  }

  @override
  Future<void> quarantineRaw(String data) async {
    // Rotate the kQuarantineKeep (3) slots — oldest ages out, newest at [0]
    // — so a fresh corruption is always recoverable without unbounded growth.
    for (var i = pg.kQuarantineKeep - 1; i > 0; i--) {
      final prev = _prefs.getString(_quarantineKey(i - 1));
      if (prev != null) await _prefs.setString(_quarantineKey(i), prev);
    }
    await _prefs.setString(_quarantineKey(0), data);
  }
}
```

Then in `lib/state/providers.dart`, add `'loreseer.magic.v1'` to the `sessionScopedKeys` list (`lib/state/providers.dart:2522`), alongside `'loreseer.decks.v1'`:

```dart
  'loreseer.decks.v1',
  'loreseer.magic.v1',
  'loreseer.gmchat.v1',
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/magic_store_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/state/magic_controller.dart lib/state/providers.dart test/magic_store_test.dart
git commit -m "feat(magic): add JuiceMagicStore persistence adapter"
```

---

### Task 4: `MagicController` — core CRUD

**Files:**
- Modify: `lib/state/magic_controller.dart`
- Test: `test/magic_controller_test.dart`

**Interfaces:**
- Consumes: `JuiceMagicStore` (Task 3); `sessionsProvider` and `prefsProvider` from `lib/state/providers.dart` (existing — `sessionsProvider.future` resolves to a value with `.active` (`String`, the current session id); `prefsProvider.future` resolves to a `SharedPreferences`).
- Produces: `magicProvider` (`AsyncNotifierProvider<MagicController, pg.Library>`); `MagicController` methods `upsertCharacter(pg.Character)`, `deleteCharacter(String id)`, `setMana(String characterId, int value)`, `upsertSpell(pg.Spell)`, `deleteSpell(String id)`, `toggleFavorite(pg.Spell)`, `duplicateSpell(pg.Spell)`, `loadSamples(String characterId)`. Task 5 adds casting/rest/hanging/running methods to this same class.

- [ ] **Step 1: Write the failing test**

```dart
// test/magic_controller_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/state/magic_controller.dart';
import 'package:polarity_grammar/polarity_grammar.dart' as pg;
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _container() {
  SharedPreferences.setMockInitialValues({
    'loreseer.sessions.v1':
        '{"active":"c1","sessions":[{"id":"c1","name":"Test"}]}',
  });
  final container = ProviderContainer();
  return container;
}

void main() {
  test('upsertCharacter creates then setMana updates a caster, persisted',
      () async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(magicProvider.future);
    final ctrl = container.read(magicProvider.notifier);

    await ctrl.upsertCharacter(
      const pg.Character(id: 'pg-1', name: 'Ash', baseMana: 4, currentMana: 4),
    );
    var lib = container.read(magicProvider).valueOrNull!;
    expect(lib.characters.single.name, 'Ash');

    await ctrl.setMana('pg-1', 2);
    lib = container.read(magicProvider).valueOrNull!;
    expect(lib.characters.single.currentMana, 2);
  });

  test('upsertSpell then deleteSpell round-trips the spellbook', () async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(magicProvider.future);
    final ctrl = container.read(magicProvider.notifier);
    await ctrl.upsertCharacter(
      const pg.Character(id: 'pg-1', name: 'Ash', baseMana: 4, currentMana: 4),
    );

    final spell = pg.Spell(
      id: 's1',
      characterId: 'pg-1',
      name: 'Spark',
      effects: const [
        pg.EffectChoice(pg.CardChoice('effect.sensory.numb', pg.PoleSide.a), 1),
      ],
      form: const pg.CardChoice('form.link', pg.PoleSide.a),
      targets: const [pg.TargetPhrase(count: 1, targetType: 1)],
      size: 0,
      distance: 0,
      timing: 0,
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
      editedAt: DateTime(2026, 1, 1),
    );
    await ctrl.upsertSpell(spell);
    expect(
        container.read(magicProvider).valueOrNull!.spellsFor('pg-1').single.name,
        'Spark');

    await ctrl.deleteSpell('s1');
    expect(container.read(magicProvider).valueOrNull!.spellsFor('pg-1'), isEmpty);
  });

  test('deleteCharacter removes the caster and their spells', () async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(magicProvider.future);
    final ctrl = container.read(magicProvider.notifier);
    await ctrl.upsertCharacter(
      const pg.Character(id: 'pg-1', name: 'Ash', baseMana: 4, currentMana: 4),
    );
    await ctrl.deleteCharacter('pg-1');
    final lib = container.read(magicProvider).valueOrNull!;
    expect(lib.characters, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/magic_controller_test.dart`
Expected: FAIL — `Undefined name 'magicProvider'`.

- [ ] **Step 3: Implement `MagicController` core methods**

Append to `lib/state/magic_controller.dart` (add these imports at the top first: `import 'package:flutter_riverpod/flutter_riverpod.dart';` and `import 'providers.dart' show sessionsProvider, prefsProvider;`):

```dart
class MagicController extends AsyncNotifier<pg.Library> {
  late JuiceMagicStore _store;

  @override
  Future<pg.Library> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    final prefs = await ref.read(prefsProvider.future);
    _store = JuiceMagicStore(prefs, sessions.active);
    return _store.load();
  }

  pg.Library get _lib => state.valueOrNull ?? const pg.Library.empty();

  Future<void> _commit(pg.Library next) async {
    // Update in-memory state before the async persist so a rapid second
    // mutation (fired during this persist) reads the new library, not the
    // stale one — mirrors DecksNotifier._save.
    state = AsyncData(next);
    await _store.save(next);
  }

  /// Monotonic counter behind [_freshId] — a timestamp alone can collide if
  /// two ids are minted in the same microsecond.
  int _idSeq = 0;

  String _freshId(String kind, DateTime at) =>
      '$kind-${at.microsecondsSinceEpoch}-${_idSeq++}';

  /// The character list with [c] swapped in at its existing position
  /// (appended if new).
  List<pg.Character> _withCharacter(List<pg.Character> chars, pg.Character c) {
    final i = chars.indexWhere((x) => x.id == c.id);
    if (i < 0) return [...chars, c];
    final next = [...chars];
    next[i] = c;
    return next;
  }

  pg.Character? _byId(String id) {
    for (final c in _lib.characters) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> upsertCharacter(pg.Character c) async {
    await _commit(_lib.copyWith(characters: _withCharacter(_lib.characters, c)));
  }

  Future<void> deleteCharacter(String id) async {
    await _commit(_lib.copyWith(
      characters: _lib.characters.where((c) => c.id != id).toList(),
      spells: _lib.spells.where((s) => s.characterId != id).toList(),
      history: _lib.history.where((h) => h.characterId != id).toList(),
      hanging: _lib.hanging.where((h) => h.characterId != id).toList(),
      running: _lib.running.where((r) => r.characterId != id).toList(),
    ));
  }

  Future<void> setMana(String characterId, int value) async {
    final c = _byId(characterId);
    if (c == null) return;
    await upsertCharacter(c.copyWith(currentMana: value.clamp(0, c.availableMana)));
  }

  Future<void> upsertSpell(pg.Spell s) async {
    final rest = _lib.spells.where((x) => x.id != s.id).toList();
    await _commit(_lib.copyWith(spells: [...rest, s]));
  }

  Future<void> deleteSpell(String id) async {
    await _commit(_lib.copyWith(spells: _lib.spells.where((s) => s.id != id).toList()));
  }

  Future<void> toggleFavorite(pg.Spell s) =>
      upsertSpell(s.copyWith(favorite: !s.favorite, editedAt: DateTime.now()));

  Future<void> duplicateSpell(pg.Spell s) async {
    final now = DateTime.now();
    await upsertSpell(s.copyWith(
      id: _freshId('spell', now),
      name: '${s.name} (copy)',
      favorite: false,
      editedAt: now,
    ));
  }

  /// Copies the sample spellbook into [characterId] with fresh ids —
  /// additive and repeatable, mirrors the standalone app's "Load samples".
  Future<List<pg.Spell>> loadSamples(String characterId) async {
    final school = _byId(characterId)?.school;
    final source =
        school == null ? pg.kSampleSpells : pg.kSampleSpellsBySchool[school]!;
    final now = DateTime.now();
    final added = <pg.Spell>[
      for (final s in source)
        s.copyWith(id: _freshId('spell', now), characterId: characterId, editedAt: now),
    ];
    await _commit(_lib.copyWith(spells: [..._lib.spells, ...added]));
    return added;
  }
}

final magicProvider =
    AsyncNotifierProvider<MagicController, pg.Library>(MagicController.new);
```

Before running the tests, confirm `sessionsProvider`'s resolved value exposes `.active` (`String`) and `prefsProvider.future` resolves to a `SharedPreferences` — both already used exactly this way by `DecksNotifier` in `lib/state/providers.dart`; if either name differs, use the real one from that file.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/magic_controller_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/state/magic_controller.dart test/magic_controller_test.dart
git commit -m "feat(magic): add MagicController core CRUD"
```

---

### Task 5: `MagicController` — casting engine (cast, undo, rest, hanging, running)

**Files:**
- Modify: `lib/state/magic_controller.dart`
- Test: `test/magic_controller_cast_test.dart`

**Interfaces:**
- Consumes: everything from Task 4.
- Produces: `MagicController.cast(pg.Spell, {String? trigger})`, `undoCast(...)`, `rest(String characterId)`, `undoRest(...)`, `dismissHanging(String id)`, `restoreHanging(List<pg.HangingSpell>)`, `endRunning(String id)`, `restoreRunning(List<pg.RunningSpell>)`, `clearHistory(String characterId)`, `restoreHistory(List<pg.CastRecord>)`, `toggleAdjusted(String recordId)`. Tasks 7-8 wire `cast`/`rest` into `magicSection()`.

- [ ] **Step 1: Write the failing test**

```dart
// test/magic_controller_cast_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/state/magic_controller.dart';
import 'package:polarity_grammar/polarity_grammar.dart' as pg;
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _container() {
  SharedPreferences.setMockInitialValues({
    'loreseer.sessions.v1':
        '{"active":"c1","sessions":[{"id":"c1","name":"Test"}]}',
  });
  return ProviderContainer();
}

void main() {
  test('cast deducts mana and logs history; undoCast refunds it', () async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(magicProvider.future);
    final ctrl = container.read(magicProvider.notifier);
    await ctrl.upsertCharacter(
      const pg.Character(id: 'pg-1', name: 'Ash', baseMana: 8, currentMana: 8),
    );
    final spell = pg.Spell(
      id: 's1',
      characterId: 'pg-1',
      name: 'Spark',
      effects: const [
        pg.EffectChoice(pg.CardChoice('effect.sensory.numb', pg.PoleSide.a), 1),
      ],
      form: const pg.CardChoice('form.link', pg.PoleSide.a),
      targets: const [pg.TargetPhrase(count: 1, targetType: 1)],
      size: 0,
      distance: 0,
      timing: 0,
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
      editedAt: DateTime(2026, 1, 1),
    );

    final result = await ctrl.cast(spell);
    var lib = container.read(magicProvider).valueOrNull!;
    expect(lib.characters.single.currentMana, lessThan(8));
    expect(lib.history.length, 1);

    await ctrl.undoCast('pg-1', result.refund, result.recordId);
    lib = container.read(magicProvider).valueOrNull!;
    expect(lib.characters.single.currentMana, 8);
    expect(lib.history, isEmpty);
  });

  test('rest refills mana to max and logs a rest marker', () async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(magicProvider.future);
    final ctrl = container.read(magicProvider.notifier);
    await ctrl.upsertCharacter(
      const pg.Character(id: 'pg-1', name: 'Ash', baseMana: 8, currentMana: 2),
    );
    await ctrl.rest('pg-1');
    final lib = container.read(magicProvider).valueOrNull!;
    expect(lib.characters.single.currentMana, 8);
    expect(lib.history.single.kind, pg.CastKind.rest);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/magic_controller_cast_test.dart`
Expected: FAIL — `The method 'cast' isn't defined for the type 'MagicController'`.

- [ ] **Step 3: Implement the casting engine**

Add these imports to `lib/state/magic_controller.dart` if not already present (needed for the free functions `pg.spellCost`, `pg.incantation`, `pg.requiresTrigger`, `pg.hasDuration` — all already exported by `polarity_grammar.dart`, no extra import needed beyond the existing `as pg` import).

Insert inside the `MagicController` class, after `loadSamples` and before the closing `}`:

```dart
  /// Keep each character's cast log bounded (per character, not per
  /// library — a shared cap would let a busy caster evict someone else's
  /// log).
  static const _kMaxHistory = 200;
  static const _kMaxRunning = 30;

  List<pg.CastRecord> _capped(List<pg.CastRecord> history, String characterId) {
    final mine = [for (final h in history) if (h.characterId == characterId) h];
    if (mine.length <= _kMaxHistory) return history;
    final drop = {for (final h in mine.take(mine.length - _kMaxHistory)) h.id};
    return [for (final h in history) if (!drop.contains(h.id)) h];
  }

  List<pg.RunningSpell> _cappedRunning(List<pg.RunningSpell> running, String characterId) {
    final mine = [for (final r in running) if (r.characterId == characterId) r];
    if (mine.length <= _kMaxRunning) return running;
    final drop = {for (final r in mine.take(mine.length - _kMaxRunning)) r.id};
    return [for (final r in running) if (!drop.contains(r.id)) r];
  }

  /// Deducts cost and appends a history record of the spell AS CAST. A
  /// Triggered cast also hangs (oldest over the Spell Level cap silently
  /// defuses); a duration cast joins the running list. Returns what
  /// [undoCast] needs.
  Future<
      ({
        int refund,
        String recordId,
        String? hangingId,
        String? runningId,
        List<pg.HangingSpell> defused,
      })> cast(pg.Spell s, {String? trigger}) async {
    final c = _byId(s.characterId);
    if (c == null) {
      return (
        refund: 0,
        recordId: '',
        hangingId: null,
        runningId: null,
        defused: const <pg.HangingSpell>[],
      );
    }
    final before = c.currentMana;
    final now = DateTime.now();
    final record = pg.CastRecord(
      id: _freshId('cast', now),
      characterId: s.characterId,
      spellName: s.name,
      incantation: pg.incantation(s),
      cost: pg.spellCost(s),
      at: now,
      spellId: s.id,
      spell: s,
    );
    final history = _capped([..._lib.history, record], s.characterId);
    var hanging = _lib.hanging;
    String? hangingId;
    var defused = const <pg.HangingSpell>[];
    if (pg.requiresTrigger(s)) {
      final mine = [for (final h in hanging) if (h.characterId == s.characterId) h];
      final overflow = mine.length - c.spellLevel + 1;
      if (overflow > 0) {
        defused = mine.take(overflow).toList();
        final drop = {for (final h in defused) h.id};
        hanging = [for (final h in hanging) if (!drop.contains(h.id)) h];
      }
      hangingId = _freshId('hang', now);
      hanging = [
        ...hanging,
        pg.HangingSpell(
          id: hangingId,
          characterId: s.characterId,
          spellName: s.name,
          incantation: pg.incantation(s),
          cost: pg.spellCost(s),
          trigger: trigger ?? '',
          at: now,
          spell: s,
        ),
      ];
    }
    var running = _lib.running;
    String? runningId;
    if (pg.hasDuration(s)) {
      runningId = _freshId('run', now);
      running = _cappedRunning([
        ...running,
        pg.RunningSpell(
          id: runningId,
          characterId: s.characterId,
          spellName: s.name,
          incantation: pg.incantation(s),
          cost: pg.spellCost(s),
          timing: s.timing,
          at: now,
          spell: s,
        ),
      ], s.characterId);
    }
    final spells = [
      for (final t in _lib.spells)
        if (t.id == s.id) t.copyWith(castCount: t.castCount + 1) else t,
    ];
    final after = (before - pg.spellCost(s)).clamp(0, c.availableMana);
    await _commit(_lib.copyWith(
      characters: _withCharacter(_lib.characters, c.copyWith(currentMana: after)),
      spells: spells,
      history: history,
      hanging: hanging,
      running: running,
    ));
    return (
      refund: before - after,
      recordId: record.id,
      hangingId: hangingId,
      runningId: runningId,
      defused: defused,
    );
  }

  /// Undo a cast: refund what it deducted and drop its history record (plus
  /// un-hang/un-run/re-hang-defused as applicable).
  Future<void> undoCast(
    String characterId,
    int refund,
    String recordId, {
    String? hangingId,
    String? runningId,
    List<pg.HangingSpell> defused = const [],
  }) async {
    final c = _byId(characterId);
    if (c == null) return;
    final hanging = [
      for (final h in _lib.hanging) if (h.id != hangingId) h,
      ...defused,
    ]..sort((a, b) => a.at.compareTo(b.at));
    String? spellId;
    for (final h in _lib.history) {
      if (h.id == recordId) spellId = h.spellId;
    }
    final spells = [
      for (final t in _lib.spells)
        if (t.id == spellId && t.castCount > 0) t.copyWith(castCount: t.castCount - 1) else t,
    ];
    await _commit(_lib.copyWith(
      characters: _withCharacter(
          _lib.characters, c.copyWith(currentMana: (c.currentMana + refund).clamp(0, c.availableMana))),
      spells: spells,
      history: _lib.history.where((h) => h.id != recordId).toList(),
      hanging: hanging,
      running: _lib.running.where((r) => r.id != runningId).toList(),
    ));
  }

  /// Refills to max and logs a session-boundary marker. Returns what
  /// [undoRest] needs.
  Future<({int before, String recordId})> rest(String characterId) async {
    final c = _byId(characterId);
    if (c == null) return (before: 0, recordId: '');
    final now = DateTime.now();
    final record = pg.CastRecord(
      id: _freshId('rest', now),
      characterId: characterId,
      spellName: 'Rest',
      incantation: '',
      cost: 0,
      at: now,
      kind: pg.CastKind.rest,
    );
    final history = _capped([..._lib.history, record], characterId);
    await _commit(_lib.copyWith(
      characters: _withCharacter(_lib.characters, c.copyWith(currentMana: c.availableMana)),
      history: history,
    ));
    return (before: c.currentMana, recordId: record.id);
  }

  Future<void> undoRest(String characterId, int before, String recordId) async {
    final c = _byId(characterId);
    if (c == null) return;
    await _commit(_lib.copyWith(
      characters: _withCharacter(
          _lib.characters, c.copyWith(currentMana: before.clamp(0, c.availableMana))),
      history: _lib.history.where((h) => h.id != recordId).toList(),
    ));
  }

  Future<void> dismissHanging(String id) async {
    await _commit(_lib.copyWith(hanging: _lib.hanging.where((h) => h.id != id).toList()));
  }

  Future<void> restoreHanging(List<pg.HangingSpell> records) async {
    final merged = [..._lib.hanging, ...records]..sort((a, b) => a.at.compareTo(b.at));
    await _commit(_lib.copyWith(hanging: merged));
  }

  Future<void> endRunning(String id) async {
    await _commit(_lib.copyWith(running: _lib.running.where((r) => r.id != id).toList()));
  }

  Future<void> restoreRunning(List<pg.RunningSpell> records) async {
    final merged = [..._lib.running, ...records]..sort((a, b) => a.at.compareTo(b.at));
    await _commit(_lib.copyWith(running: merged));
  }

  Future<List<pg.CastRecord>> clearHistory(String characterId) async {
    final removed = _lib.history.where((h) => h.characterId == characterId).toList();
    await _commit(_lib.copyWith(
      history: _lib.history.where((h) => h.characterId != characterId).toList(),
    ));
    return removed;
  }

  Future<void> restoreHistory(List<pg.CastRecord> records) async {
    final merged = [..._lib.history, ...records]..sort((a, b) => a.at.compareTo(b.at));
    await _commit(_lib.copyWith(history: merged));
  }

  Future<void> toggleAdjusted(String recordId) async {
    await _commit(_lib.copyWith(
      history: [
        for (final h in _lib.history)
          if (h.id == recordId) h.copyWith(adjusted: !h.adjusted) else h,
      ],
    ));
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/magic_controller_cast_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Run the full magic test suite so far**

Run: `flutter test test/polarity_grammar_dependency_test.dart test/character_polarity_id_test.dart test/magic_store_test.dart test/magic_controller_test.dart test/magic_controller_cast_test.dart`
Expected: PASS (all)

- [ ] **Step 6: Commit**

```bash
git add lib/state/magic_controller.dart test/magic_controller_cast_test.dart
git commit -m "feat(magic): add MagicController casting engine"
```

---

### Task 6: `CharacterNotifier.enableMagic` / `disableMagic`

**Files:**
- Modify: `lib/state/providers.dart`
- Test: `test/character_notifier_magic_test.dart`

**Interfaces:**
- Consumes: `Character.polarityId`/`clearPolarityId` (Task 2), `magicProvider`/`MagicController.upsertCharacter`/`deleteCharacter` (Tasks 3-4).
- Produces: `CharacterNotifier.enableMagic(String characterId)`, `CharacterNotifier.disableMagic(String characterId)`. Task 7 calls these from `magicSection()`.

- [ ] **Step 1: Write the failing test**

```dart
// test/character_notifier_magic_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/state/magic_controller.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('enableMagic creates a pg.Character and links polarityId, disableMagic undoes it',
      () async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
          '{"active":"c1","sessions":[{"id":"c1","name":"Test"}]}',
      'loreseer.characters.v1.c1':
          '[{"id":"ch1","name":"Ash","stats":[],"tracks":[],"tags":[]}]',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(charactersProvider.future);
    final ctrl = container.read(charactersProvider.notifier);

    await ctrl.enableMagic('ch1');
    var chars = await container.read(charactersProvider.future);
    final linked = chars.single.polarityId;
    expect(linked, isNotNull);
    var lib = await container.read(magicProvider.future);
    expect(lib.characters.single.id, linked);
    expect(lib.characters.single.name, 'Ash');

    await ctrl.disableMagic('ch1');
    chars = await container.read(charactersProvider.future);
    expect(chars.single.polarityId, isNull);
    lib = await container.read(magicProvider.future);
    expect(lib.characters, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/character_notifier_magic_test.dart`
Expected: FAIL — `The method 'enableMagic' isn't defined for the type 'CharacterNotifier'`.

- [ ] **Step 3: Implement**

In `lib/state/providers.dart`, add the import `import 'package:polarity_grammar/polarity_grammar.dart' as pg;` and `import 'magic_controller.dart';` at the top, then add these methods to `CharacterNotifier` (alongside `setRole`/`setConditions`, `lib/state/providers.dart:~558`):

```dart
  /// Enables Polarity Grammar casting on [id]: creates its linked pg.Character
  /// (Base Mana 4 / Spell Level 1 — a starting pool sized for exactly one
  /// minimal 4-mana spell, per the quickstart's "cheapest possible spell")
  /// and stamps [Character.polarityId]. No-op if already enabled.
  Future<void> enableMagic(String id) async {
    final list = await _ready;
    final c = list.where((e) => e.id == id).firstOrNull;
    if (c == null || c.polarityId != null) return;
    final pgId = _newId();
    await ref.read(magicProvider.notifier).upsertCharacter(
          pg.Character(id: pgId, name: c.name, baseMana: 4, currentMana: 4),
        );
    await replace(c.copyWith(polarityId: pgId));
  }

  /// Disables casting on [id]: removes its pg.Character (and their spells
  /// and history) from the campaign's Library and clears the link.
  Future<void> disableMagic(String id) async {
    final list = await _ready;
    final c = list.where((e) => e.id == id).firstOrNull;
    if (c == null || c.polarityId == null) return;
    await ref.read(magicProvider.notifier).deleteCharacter(c.polarityId!);
    await replace(c.copyWith(clearPolarityId: true));
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/character_notifier_magic_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/character_notifier_magic_test.dart
git commit -m "feat(magic): add CharacterNotifier.enableMagic/disableMagic"
```

---

### Task 7: `magicSection()` — enable button + mana bar

**Files:**
- Modify: `lib/features/sheet_widgets.dart`
- Test: `test/magic_section_test.dart`

**Interfaces:**
- Consumes: `charactersProvider`/`enableMagic` (Task 6), `magicProvider` (Task 4), `pg.ManaBar` (package widget), `sheetSection(BuildContext, String)` (existing helper in `sheet_widgets.dart`).
- Produces: `Widget magicSection(BuildContext context, WidgetRef ref, Character c)`. Task 8 extends it with the spellbook; Task 10 drops it into all 15 sheets.

- [ ] **Step 1: Write the failing test**

```dart
// test/magic_section_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';
import 'package:loreseer/features/sheet_widgets.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester, {String? polarityId}) async {
  SharedPreferences.setMockInitialValues({
    'loreseer.sessions.v1':
        '{"active":"c1","sessions":[{"id":"c1","name":"Test"}]}',
    'loreseer.characters.v1.c1': jsonEncode([
      {
        'id': 'ch1',
        'name': 'Ash',
        'stats': [],
        'tracks': [],
        'tags': [],
        if (polarityId != null) 'polarityId': polarityId,
      }
    ]),
    if (polarityId != null)
      'loreseer.magic.v1.c1': jsonEncode({
        'characters': [
          {'id': polarityId, 'name': 'Ash', 'baseMana': 4, 'currentMana': 4}
        ],
        'spells': [],
      }),
  });
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final char = (await container.read(charactersProvider.future)).single;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(builder: (_, ref, __) {
          final live =
              ref.watch(charactersProvider).valueOrNull?.firstOrNull ?? char;
          return SingleChildScrollView(
              child: magicSection(context, ref, live));
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('shows an enable button when magic is not linked', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('magic-enable')), findsOneWidget);
    expect(find.byKey(const Key('magic-mana-bar')), findsNothing);
  });

  testWidgets('tapping enable creates the link and swaps in the mana bar',
      (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.byKey(const Key('magic-enable')));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.polarityId, isNotNull);
    expect(find.byKey(const Key('magic-mana-bar')), findsOneWidget);
  });

  testWidgets('shows the mana bar directly when already linked', (tester) async {
    await _pump(tester, polarityId: 'pg-1');
    expect(find.byKey(const Key('magic-enable')), findsNothing);
    expect(find.byKey(const Key('magic-mana-bar')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/magic_section_test.dart`
Expected: FAIL — `The function 'magicSection' isn't defined`.

- [ ] **Step 3: Implement**

In `lib/features/sheet_widgets.dart`, add `import 'package:polarity_grammar/polarity_grammar.dart' as pg;` and `import '../state/magic_controller.dart';` at the top, then add:

```dart
/// A "Magic" section for the open sheets, mirroring [conditionsSection]:
/// an enable button when [c] hasn't opted into Polarity Grammar casting, or
/// the live mana bar (+ Task 8's spellbook) once it has.
Widget magicSection(BuildContext context, WidgetRef ref, Character c) {
  if (c.polarityId == null) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sheetSection(context, 'Magic'),
        FilledButton.icon(
          key: const Key('magic-enable'),
          icon: const Icon(Icons.auto_fix_high_outlined),
          label: const Text('Enable Polarity Grammar casting'),
          onPressed: () =>
              ref.read(charactersProvider.notifier).enableMagic(c.id),
        ),
      ],
    );
  }
  final lib = ref.watch(magicProvider).valueOrNull;
  final pgChar =
      lib?.characters.where((x) => x.id == c.polarityId).firstOrNull;
  if (lib == null || pgChar == null) return const SizedBox.shrink();
  final ctrl = ref.read(magicProvider.notifier);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      sheetSection(context, 'Magic'),
      pg.ManaBar(
        key: const Key('magic-mana-bar'),
        current: pgChar.currentMana,
        max: pgChar.availableMana,
        caption: 'Spell Level ${pg.kRoman[pgChar.spellLevel]}',
        onChanged: (v) => ctrl.setMana(pgChar.id, v),
        onRest: () => ctrl.rest(pgChar.id),
      ),
    ],
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/magic_section_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/sheet_widgets.dart test/magic_section_test.dart
git commit -m "feat(magic): add magicSection enable button and mana bar"
```

---

### Task 8: `magicSection()` — spellbook + casting

**Files:**
- Modify: `lib/features/sheet_widgets.dart`
- Test: `test/magic_section_spellbook_test.dart`

**Interfaces:**
- Consumes: `pg.SpellbookList` (package widget), `MagicController.cast`/`upsertSpell`/`deleteSpell`/`toggleFavorite`/`duplicateSpell` (Tasks 4-5).
- Produces: `magicSection()` now renders the spellbook and casts through it. Task 9 adds the Build/Reference/Convert/Guide entry points.

- [ ] **Step 1: Write the failing test**

```dart
// test/magic_section_spellbook_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/features/sheet_widgets.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a saved spell appears in the spellbook and casts on tap',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
          '{"active":"c1","sessions":[{"id":"c1","name":"Test"}]}',
      'loreseer.characters.v1.c1': jsonEncode([
        {
          'id': 'ch1',
          'name': 'Ash',
          'stats': [],
          'tracks': [],
          'tags': [],
          'polarityId': 'pg-1',
        }
      ]),
      'loreseer.magic.v1.c1': jsonEncode({
        'characters': [
          {'id': 'pg-1', 'name': 'Ash', 'baseMana': 8, 'currentMana': 8}
        ],
        'spells': [
          {
            'id': 's1',
            'characterId': 'pg-1',
            'name': 'Spark',
            'effects': [
              {
                'effect': {'card': 'effect.sensory.numb', 'side': 'a'},
                'intensity': 1,
              }
            ],
            'form': {'card': 'form.link', 'side': 'a'},
            'targets': [
              {'count': 1, 'targetType': 1}
            ],
            'size': 0,
            'distance': 0,
            'timing': 0,
            'favorite': false,
            'createdAt': '2026-01-01T00:00:00.000Z',
            'editedAt': '2026-01-01T00:00:00.000Z',
          }
        ],
      }),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final char = (await container.read(charactersProvider.future)).single;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (_, ref, __) {
            final live =
                ref.watch(charactersProvider).valueOrNull?.firstOrNull ?? char;
            return magicSection(context, ref, live);
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Spark'), findsWidgets);
  });
}
```


- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/magic_section_spellbook_test.dart`
Expected: FAIL — spellbook not rendered (`findsWidgets` returns 0).

- [ ] **Step 3: Implement**

In `magicSection()`'s linked branch (Task 7), after the `pg.ManaBar(...)` child, add:

```dart
      const SizedBox(height: 8),
      SizedBox(
        height: 320,
        child: pg.SpellbookList(
          spells: lib.spellsFor(pgChar.id),
          currentMana: pgChar.currentMana,
          spellLevel: pgChar.spellLevel,
          castLevelCap: pgChar.gatedCasting ? pgChar.spellLevel : null,
          school: pgChar.school,
          enforceSchool: pgChar.enforceSchool,
          onCast: (s, trigger) => ctrl.cast(s, trigger: trigger),
          onEdit: (s) => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => pg.SpellBuilderScreen(
              characterId: pgChar.id,
              spellLevel: pgChar.spellLevel,
              currentMana: pgChar.currentMana,
              school: pgChar.school,
              enforceSchool: pgChar.enforceSchool,
              existing: s,
              onSave: ctrl.upsertSpell,
            ),
          )),
          onDelete: (s) => ctrl.deleteSpell(s.id),
          onToggleFavorite: ctrl.toggleFavorite,
          onDuplicate: ctrl.duplicateSpell,
        ),
      ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/magic_section_spellbook_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/sheet_widgets.dart test/magic_section_spellbook_test.dart
git commit -m "feat(magic): wire spellbook + casting into magicSection"
```

---

### Task 9: Build / Reference / Convert / Guide entry points

**Files:**
- Modify: `lib/features/sheet_widgets.dart`
- Test: `test/magic_section_routes_test.dart`

**Interfaces:**
- Consumes: `pg.SpellBuilderScreen`, `pg.CardReferenceScreen`, `pg.ConversionCalculator`, `pg.UserGuideScreen`, `pg.gameSystemById` (package).
- Produces: `magicSection()` P1-complete — matches the design spec's "wire the entire standalone-app feature set."

- [ ] **Step 1: Write the failing test**

```dart
// test/magic_section_routes_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/features/sheet_widgets.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpLinked(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'loreseer.sessions.v1':
        '{"active":"c1","sessions":[{"id":"c1","name":"Test"}]}',
    'loreseer.characters.v1.c1': jsonEncode([
      {
        'id': 'ch1', 'name': 'Ash', 'stats': [], 'tracks': [], 'tags': [],
        'polarityId': 'pg-1',
      }
    ]),
    'loreseer.magic.v1.c1': jsonEncode({
      'characters': [
        {'id': 'pg-1', 'name': 'Ash', 'baseMana': 4, 'currentMana': 4}
      ],
      'spells': [],
    }),
  });
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final char = (await container.read(charactersProvider.future)).single;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(builder: (_, ref, __) {
          final live =
              ref.watch(charactersProvider).valueOrNull?.firstOrNull ?? char;
          return magicSection(context, ref, live);
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('Build spell pushes the spell builder screen', (tester) async {
    await _pumpLinked(tester);
    await tester.tap(find.byKey(const Key('magic-build')));
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold), findsWidgets);
    expect(find.textContaining('Spell'), findsWidgets);
  });

  testWidgets('Card reference pushes the reference screen', (tester) async {
    await _pumpLinked(tester);
    await tester.tap(find.byKey(const Key('magic-reference')));
    await tester.pumpAndSettle();
    expect(find.text('Card Reference'), findsOneWidget);
  });

  testWidgets('User guide pushes the guide screen', (tester) async {
    await _pumpLinked(tester);
    await tester.tap(find.byKey(const Key('magic-guide')));
    await tester.pumpAndSettle();
    expect(find.text('User Guide'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/magic_section_routes_test.dart`
Expected: FAIL — the `magic-build`/`magic-reference`/`magic-guide` keys don't exist yet.

- [ ] **Step 3: Implement**

After the `pg.SpellbookList(...)` child (Task 8), add:

```dart
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            key: const Key('magic-build'),
            icon: const Icon(Icons.add),
            label: const Text('Build spell'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => pg.SpellBuilderScreen(
                characterId: pgChar.id,
                spellLevel: pgChar.spellLevel,
                currentMana: pgChar.currentMana,
                school: pgChar.school,
                enforceSchool: pgChar.enforceSchool,
                onSave: ctrl.upsertSpell,
              ),
            )),
          ),
          TextButton.icon(
            key: const Key('magic-reference'),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Card reference'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const pg.CardReferenceScreen(),
            )),
          ),
          if (pg.gameSystemById(pgChar.systemId) != null)
            TextButton.icon(
              key: const Key('magic-convert'),
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Conversion'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => pg.ConversionCalculator(
                  system: pg.gameSystemById(pgChar.systemId)!,
                ),
              )),
            ),
          TextButton.icon(
            key: const Key('magic-guide'),
            icon: const Icon(Icons.help_outline),
            label: const Text('User guide'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const pg.UserGuideScreen(),
            )),
          ),
        ],
      ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/magic_section_routes_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Run the whole magic test suite**

Run: `flutter test test/polarity_grammar_dependency_test.dart test/character_polarity_id_test.dart test/magic_store_test.dart test/magic_controller_test.dart test/magic_controller_cast_test.dart test/character_notifier_magic_test.dart test/magic_section_test.dart test/magic_section_spellbook_test.dart test/magic_section_routes_test.dart`
Expected: PASS (all)

- [ ] **Step 6: Commit**

```bash
git add lib/features/sheet_widgets.dart test/magic_section_routes_test.dart
git commit -m "feat(magic): wire spell builder, card reference, conversion, guide routes"
```

---

### Task 10: Drop `magicSection()` into all 15 sheet views

**Files:**
- Modify: `lib/features/argosa_sheet.dart`, `lib/features/cairn_sheet.dart`, `lib/features/custom_sheet.dart`, `lib/features/dcc_sheet.dart`, `lib/features/dnd_sheet.dart`, `lib/features/draw_steel_sheet.dart`, `lib/features/embark_sheet.dart`, `lib/features/funnel_sheet.dart`, `lib/features/ironsworn_sheet.dart`, `lib/features/kal_arath_sheet.dart`, `lib/features/knave_sheet.dart`, `lib/features/nimble_sheet.dart`, `lib/features/ose_sheet.dart`, `lib/features/shadowdark_sheet.dart`, `lib/features/starforged_sheet.dart`
- Test: `test/magic_section_all_sheets_test.dart`

**Interfaces:**
- Consumes: `magicSection()` (Tasks 7-9).
- Produces: every premade sheet renders the `magic-enable`/`magic-mana-bar` key from `magicSection()`.

- [ ] **Step 1: Write the failing test**

```dart
// test/magic_section_all_sheets_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';
import 'package:loreseer/features/argosa_sheet.dart';
import 'package:loreseer/features/cairn_sheet.dart';
import 'package:loreseer/features/custom_sheet.dart';
import 'package:loreseer/features/dcc_sheet.dart';
import 'package:loreseer/features/dnd_sheet.dart';
import 'package:loreseer/features/draw_steel_sheet.dart';
import 'package:loreseer/features/embark_sheet.dart';
import 'package:loreseer/features/funnel_sheet.dart';
import 'package:loreseer/features/ironsworn_sheet.dart';
import 'package:loreseer/features/kal_arath_sheet.dart';
import 'package:loreseer/features/knave_sheet.dart';
import 'package:loreseer/features/nimble_sheet.dart';
import 'package:loreseer/features/ose_sheet.dart';
import 'package:loreseer/features/shadowdark_sheet.dart';
import 'package:loreseer/features/starforged_sheet.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One [Character] per premade system, seeded with the minimal sheet each
/// view requires (defaults for every sheet's const constructor already
/// satisfy this — pass `Character.forSheet(systemKey, id)` for the ones
/// with a `.premade()` factory, else the system's bare default sheet).
final _cases = <String, Widget Function(Character c)>{
  'argosa': (c) => ArgosaSheetView(character: c, onBack: () {}),
  'cairn': (c) => CairnSheetView(character: c, onBack: () {}),
  'custom': (c) => CustomSheetView(character: c, onBack: () {}),
  'dcc': (c) => DccSheetView(character: c, onBack: () {}),
  'dnd': (c) => DndSheetView(character: c, onBack: () {}),
  'draw-steel': (c) => DrawSteelSheetView(character: c, onBack: () {}),
  'embark': (c) => EmbarkSheetView(character: c, onBack: () {}),
  'funnel': (c) => FunnelSheetView(character: c, onBack: () {}),
  'ironsworn': (c) => IronswornSheetView(character: c, onBack: () {}),
  'kal-arath': (c) => KalArathSheetView(character: c, onBack: () {}),
  'knave': (c) => KnaveSheetView(character: c, onBack: () {}),
  'nimble': (c) => NimbleSheetView(character: c, onBack: () {}),
  'ose': (c) => OseSheetView(character: c, onBack: () {}),
  'shadowdark': (c) => ShadowdarkSheetView(character: c, onBack: () {}),
  'starforged': (c) => StarforgedSheetView(character: c, onBack: () {}),
};

void main() {
  for (final entry in _cases.entries) {
    testWidgets('${entry.key} sheet renders magicSection', (tester) async {
      tester.view.physicalSize = const Size(1200, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'loreseer.sessions.v1':
            '{"active":"c1","sessions":[{"id":"c1","name":"Test"}]}',
      });
      final character = Character.forSheet(entry.key, 'c1');
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: entry.value(character))),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('magic-enable')), findsOneWidget,
          reason: '${entry.key} sheet is missing magicSection');
    });
  }
}
```

Note: `Character.forSheet` (`lib/engine/models/character.dart`) only covers `ironsworn`/`starforged`/`sundered_isles`/`dnd`/`shadowdark`/`nimble`/`draw-steel`/`argosa`/`cairn`/`knave`/`embark`/`ose`/`kal-arath`/`custom`/`dcc` — it does not build a `funnel` character (`FunnelSheet` isn't one of its cases). Before finalizing this test, check `lib/engine/models/character.dart` for how a bare funnel `Character` is normally constructed (likely `Character(id: id, name: ..., funnel: const FunnelSheet())` directly, mirroring the `CharacterNotifier.addFunnel`-style factory) and use that instead of `Character.forSheet('funnel', 'c1')` for that one case.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/magic_section_all_sheets_test.dart`
Expected: FAIL on all 15 — `magic-enable` key not found anywhere.

- [ ] **Step 3: Insert `magicSection(context, ref, character)` into each sheet's `ListView`**

For the 10 sheets that already call `conditionsSection(...)` unconditionally, insert `magicSection(context, ref, character),` as the item immediately after that call (same indentation `dart format` will normalize):

| File | Insert after |
|---|---|
| `lib/features/argosa_sheet.dart` | `conditionsSection(context, ref, character, 'argosa'),` |
| `lib/features/cairn_sheet.dart` | `conditionsSection(context, ref, character, 'cairn'),` |
| `lib/features/dcc_sheet.dart` | `conditionsSection(context, ref, character, 'dcc'),` |
| `lib/features/draw_steel_sheet.dart` | `conditionsSection(context, ref, character, 'draw-steel'),` |
| `lib/features/embark_sheet.dart` | `conditionsSection(context, ref, character, 'embark'),` |
| `lib/features/kal_arath_sheet.dart` | `conditionsSection(context, ref, character, 'kal-arath'),` |
| `lib/features/knave_sheet.dart` | `conditionsSection(context, ref, character, 'knave'),` |
| `lib/features/nimble_sheet.dart` | `conditionsSection(context, ref, character, 'nimble'),` |
| `lib/features/ose_sheet.dart` | `conditionsSection(context, ref, character, 'ose'),` |
| `lib/features/shadowdark_sheet.dart` | `conditionsSection(context, ref, character, 'sd'),` |

For the 5 sheets with no `conditionsSection` call, insert `magicSection(context, ref, character),` as the LAST child of the top-level `ListView`'s `children:` list, immediately before its closing `],`:

| File | `ListView` closes at (line, current as of this plan's writing — re-locate if the file has since changed) |
|---|---|
| `lib/features/custom_sheet.dart` | line 101 |
| `lib/features/dnd_sheet.dart` | line 292 |
| `lib/features/funnel_sheet.dart` | line 74 (the OUTER `],` — insert so it renders even when the funnel has no active peasant profile) |
| `lib/features/ironsworn_sheet.dart` | line 205 |
| `lib/features/starforged_sheet.dart` | line 230 |

Every one of these 15 files already imports `flutter_riverpod` and takes `character`/`ref` in scope inside its `build` method, so no new imports are needed beyond confirming `../shared/sheet_widgets.dart` (or wherever each file currently imports `conditionsSection`/`sheetNameHeader` from) already exposes `magicSection` too — it's defined in the same file (`sheet_widgets.dart`), so no import changes needed at all.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/magic_section_all_sheets_test.dart`
Expected: PASS (15 tests)

- [ ] **Step 5: Run `dart format` and the full suite**

```bash
dart format lib/features/argosa_sheet.dart lib/features/cairn_sheet.dart lib/features/custom_sheet.dart lib/features/dcc_sheet.dart lib/features/dnd_sheet.dart lib/features/draw_steel_sheet.dart lib/features/embark_sheet.dart lib/features/funnel_sheet.dart lib/features/ironsworn_sheet.dart lib/features/kal_arath_sheet.dart lib/features/knave_sheet.dart lib/features/nimble_sheet.dart lib/features/ose_sheet.dart lib/features/shadowdark_sheet.dart lib/features/starforged_sheet.dart
flutter test
```
Expected: full suite PASS (this also verifies inserting `magicSection` didn't break any of the existing 15 sheets' own widget tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/argosa_sheet.dart lib/features/cairn_sheet.dart lib/features/custom_sheet.dart lib/features/dcc_sheet.dart lib/features/dnd_sheet.dart lib/features/draw_steel_sheet.dart lib/features/embark_sheet.dart lib/features/funnel_sheet.dart lib/features/ironsworn_sheet.dart lib/features/kal_arath_sheet.dart lib/features/knave_sheet.dart lib/features/nimble_sheet.dart lib/features/ose_sheet.dart lib/features/shadowdark_sheet.dart lib/features/starforged_sheet.dart test/magic_section_all_sheets_test.dart
git commit -m "feat(magic): render magicSection on all 15 premade sheets"
```

---

### Task 11: Export/import round-trip

**Files:**
- Test: `test/magic_export_import_test.dart`

**Interfaces:**
- Consumes: `sessionScopedKeys` (Task 3); `SessionsNotifier.exportActiveFile()` → `Future<({List<int> bytes, String ext})>` and `SessionsNotifier.importCampaignData(List<int> bytes)` → `Future<void>` (both confirmed verbatim at `lib/state/providers.dart:2710` and `:2775` — `importCampaignData` creates a NEW session and switches `sessionsProvider`'s active id to it).

- [ ] **Step 1: Write the failing test**

```dart
// test/magic_export_import_test.dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/state/magic_controller.dart';
import 'package:loreseer/state/providers.dart';
import 'package:polarity_grammar/polarity_grammar.dart' as pg;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('loreseer.magic.v1 data survives export then import into a new session',
      () async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
          '{"active":"c1","sessions":[{"id":"c1","name":"Source"}]}',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(sessionsProvider.future);
    await container.read(magicProvider.future);
    await container.read(magicProvider.notifier).upsertCharacter(
          const pg.Character(id: 'pg-1', name: 'Ash', baseMana: 4, currentMana: 4),
        );

    expect(sessionScopedKeys.contains('loreseer.magic.v1'), isTrue);

    final exported = await container.read(sessionsProvider.notifier).exportActiveFile();
    expect(exported.ext, 'json'); // no blob images referenced, so plain JSON
    final decoded = jsonDecode(utf8.decode(exported.bytes)) as Map<String, dynamic>;
    expect((decoded['data'] as Map)['loreseer.magic.v1'], isNotNull);

    await container.read(sessionsProvider.notifier).importCampaignData(exported.bytes);
    final sessions = await container.read(sessionsProvider.future);
    expect(sessions.sessions.length, 2); // original 'c1' + the freshly imported one
    final importedLib = await container.read(magicProvider.future);
    expect(importedLib.characters.single.name, 'Ash');
  });
}
```

The `decoded['data']` key path above assumes `encodeCampaign`'s top-level shape nests `rawByKey` under a `data` field — confirm the real key by inspecting `encodeCampaign`'s return shape (`lib/engine/campaign_bundle.dart` or wherever it's defined) before finalizing; if the shape differs, adjust the assertion to whatever key actually holds the per-store raw JSON blobs. The two higher-value assertions (`sessions.sessions.length == 2` and the re-imported `magicProvider` resolving the same character) don't depend on that internal shape and are the ones that actually prove the round-trip works.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/magic_export_import_test.dart`
Expected: FAIL only if Task 3's `sessionScopedKeys` registration was missed — otherwise this should PASS immediately, since it exercises only existing export/import machinery plus Task 3's key registration.

- [ ] **Step 3: Fix the `decoded['data']` key path if Step 2 revealed it's wrong**

No other production code change is expected here — this task proves Task 3's `sessionScopedKeys` registration is sufficient for the existing export/import machinery to carry `loreseer.magic.v1` correctly, not something that itself changes.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/magic_export_import_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add test/magic_export_import_test.dart
git commit -m "test(magic): verify loreseer.magic.v1 survives campaign export/import"
```

---

### Task 12: Design-system check (verification, not a fixed diff)

**Files:**
- Possibly modify: `lib/features/sheet_widgets.dart`, wherever the new pushed screens are found to violate a rule.
- Test: `test/design_system_test.dart` (existing).

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new — this task is a verification gate, not a feature.

- [ ] **Step 1: Run the existing design-system test suite**

Run: `flutter test test/design_system_test.dart`

- [ ] **Step 2: Triage any failures against the new `magicSection` / pushed magic screens**

The design spec (`docs/superpowers/specs/2026-08-11-polarity-grammar-magic-design.md`, "Out of scope") flagged this explicitly: the package's card-stock widgets keep their own parchment palette by design (an intentional exception, not a bug), but the chrome around them (buttons, the mana bar's tonal container, the Scaffold app bars on pushed screens) reads ambient `Theme.of(context)` and should already comply with `JuiceTokens`. If `design_system_test.dart` flags something real (e.g. a stray default `Card` elevation casting a second shadow, violating One Shadow), fix it in `magicSection()` or the surrounding wrapper — do NOT touch the vendored `polarity_grammar` package to "fix" its own parchment card faces; that's the intentional exception, and editing vendored package code defeats the whole point of pinning a git dependency.

If the test suite instead reveals the parchment-card exception needs to be formally blessed in `DESIGN.md` (a new named exception, mechanically enforced or explicitly carved out), stop here and flag it back to the user — that's a DESIGN.md authority decision, not something to resolve unilaterally in this task.

- [ ] **Step 3: Run the full suite one more time**

Run: `flutter analyze && flutter test`
Expected: PASS, zero analyzer issues.

- [ ] **Step 4: Commit (only if Step 2 required a code change)**

```bash
git add -A
git commit -m "fix(magic): reconcile magicSection chrome with the design system"
```

---

## Final verification

- [ ] `flutter analyze` — zero issues.
- [ ] `flutter test` — full suite green.
- [ ] Manually smoke-test on a device/simulator per this repo's `run` convention: open any character sheet, enable magic, build a spell, cast it, verify mana deducts and the journal/history reflects it, verify Card Reference/User Guide/Conversion routes open and pop cleanly.
