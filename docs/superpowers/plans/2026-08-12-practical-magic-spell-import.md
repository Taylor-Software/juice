# Practical Magic Spell Import + Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import spells from a Practical Magic app export (paste JSON) into a juice character's spellbook, and rename juice's UI strings from "Polarity Grammar" to "Practical Magic".

**Architecture:** A pure `decodeShare` parser moves into the `polarity_grammar` package (sibling repo `~/StudioProjects/magic`) so both apps share one export decoder; the standalone app's `_decodeImport` delegates to it. Juice bumps its pinned git ref, adds `MagicController.importSpells` (spells only, fresh ids, append to target caster), and a paste-JSON dialog behind a `magic-import` button in the Magic section.

**Tech Stack:** Flutter/Dart, Riverpod, `polarity_grammar` pinned git dependency.

**Spec:** `docs/superpowers/specs/2026-08-12-practical-magic-spell-import-design.md`

## Global Constraints

- Two repos: Tasks 1–2 in `~/StudioProjects/magic` (branch off `main`, currently `6646f1f`), Tasks 3–6 in `~/StudioProjects/juice`.
- The magic-repo commit MUST be pushed to GitHub (`Taylor-Software/practical-magic`) before Task 3 — juice's pub pulls the ref from GitHub, not the local checkout.
- Unchanged identifiers (rename is UI-strings/comments only): `Character.polarityId`, prefs key `loreseer.magic.v1.<sessionId>`, package name `polarity_grammar`, all widget keys.
- Error messages in `decodeShare` stay byte-identical to the standalone app's current ones ('Not valid JSON', 'Not a Practical Magic export', 'Character data is damaged', 'Library data is damaged') — app tests assert them.
- juice repo: `dart format` runs via hook on every edit; format only edited files, never repo-wide.
- Imports append, never replace; importing twice duplicates.

---

### Task 1: `decodeShare` in the polarity_grammar package (magic repo)

**Files:**
- Create: `~/StudioProjects/magic/packages/polarity_grammar/lib/src/model/share.dart`
- Modify: `~/StudioProjects/magic/packages/polarity_grammar/lib/polarity_grammar.dart` (add export)
- Test: `~/StudioProjects/magic/packages/polarity_grammar/test/share_test.dart`

**Interfaces:**
- Consumes: `Character`, `Spell`, `CastRecord`, `HangingSpell`, `RunningSpell`, `Library`, `kSchemaVersion`, `SchemaTooNewException` (all already exported by the package).
- Produces: `typedef ShareBundle = ({List<Character> characters, List<Spell> spells, List<CastRecord> history, List<HangingSpell> hanging, List<RunningSpell> running});` and `ShareBundle decodeShare(String raw)` — used by Task 2 (app delegation) and Task 4 (juice import).

- [ ] **Step 1: Create branch in the magic repo**

```bash
cd ~/StudioProjects/magic && git checkout main && git pull && git checkout -b feat/share-decode
```

- [ ] **Step 2: Write the failing test**

Create `packages/polarity_grammar/test/share_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:polarity_grammar/polarity_grammar.dart';

Spell _spell(String id, String characterId) => Spell(
      id: id,
      characterId: characterId,
      name: 'Spark',
      effects: const [
        EffectChoice(CardChoice('effect.sensory.numb', PoleSide.a), 1),
      ],
      form: const CardChoice('form.link', PoleSide.a),
      targets: const [TargetPhrase(count: 1, targetType: 1)],
      size: 0,
      distance: 0,
      timing: 0,
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
      editedAt: DateTime(2026, 1, 1),
    );

const _char = Character(id: 'c1', name: 'Ash', baseMana: 4, currentMana: 4);

String _envelope({int? schemaVersion, Map<String, dynamic>? spellJson}) =>
    jsonEncode({
      'practicalmagicCharacter': 1,
      'schemaVersion': schemaVersion ?? kSchemaVersion,
      'character': _char.toJson(),
      'spells': [spellJson ?? _spell('s1', 'c1').toJson()],
      'history': <dynamic>[],
      'hanging': <dynamic>[],
      'running': <dynamic>[],
    });

void main() {
  test('decodes a character envelope', () {
    final d = decodeShare(_envelope());
    expect(d.characters.single.name, 'Ash');
    expect(d.spells.single.name, 'Spark');
    expect(d.spells.single.characterId, 'c1');
    expect(d.history, isEmpty);
    expect(d.hanging, isEmpty);
    expect(d.running, isEmpty);
  });

  test('decodes a whole-library blob', () {
    final lib = const Library.empty().copyWith(
      characters: [_char],
      spells: [_spell('s1', 'c1'), _spell('s2', 'c1')],
    );
    final d = decodeShare(jsonEncode(lib.toJson()));
    expect(d.characters.single.id, 'c1');
    expect(d.spells, hasLength(2));
  });

  test('junk is FormatException("Not valid JSON")', () {
    expect(
      () => decodeShare('{{{'),
      throwsA(isA<FormatException>()
          .having((e) => e.message, 'message', 'Not valid JSON')),
    );
  });

  test('a JSON map that is no export is rejected', () {
    expect(
      () => decodeShare('{"foo": 1}'),
      throwsA(isA<FormatException>().having(
          (e) => e.message, 'message', 'Not a Practical Magic export')),
    );
  });

  test('newer envelope schema throws SchemaTooNewException', () {
    expect(
      () => decodeShare(_envelope(schemaVersion: kSchemaVersion + 1)),
      throwsA(isA<SchemaTooNewException>()),
    );
  });

  test('damaged envelope character data is wrapped', () {
    final raw = jsonEncode({
      'practicalmagicCharacter': 1,
      'schemaVersion': kSchemaVersion,
      'character': {'bogus': true},
    });
    expect(
      () => decodeShare(raw),
      throwsA(isA<FormatException>().having(
          (e) => e.message, 'message', 'Character data is damaged')),
    );
  });

  test('v1 envelope shifts adverbial dials (label preserved)', () {
    // Pre-0.9.0 saves stored Size/Distance/Timing on 1-6; schema < 2
    // decode maps them onto the rescaled 0-5 ladders.
    final v1Spell = {..._spell('s1', 'c1').toJson()}
      ..['size'] = 2
      ..['distance'] = 1
      ..['timing'] = 3;
    final d = decodeShare(_envelope(schemaVersion: 1, spellJson: v1Spell));
    expect(d.spells.single.size, 1);
    expect(d.spells.single.distance, 0);
    expect(d.spells.single.timing, 2);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ~/StudioProjects/magic/packages/polarity_grammar && flutter test test/share_test.dart`
Expected: FAIL — `decodeShare` undefined.

- [ ] **Step 4: Implement `share.dart`**

Create `packages/polarity_grammar/lib/src/model/share.dart` — this is the parse half of the standalone app's `_decodeImport` (`app/lib/state.dart`), moved verbatim; no id remapping (hosts mint their own ids):

```dart
import 'dart:convert';

import 'package:polarity_grammar/src/model/character.dart';
import 'package:polarity_grammar/src/model/library.dart';
import 'package:polarity_grammar/src/model/spell.dart';

/// Everything a Practical Magic export can carry, parsed but NOT id-remapped
/// — the importing host mints its own fresh ids.
typedef ShareBundle = ({
  List<Character> characters,
  List<Spell> spells,
  List<CastRecord> history,
  List<HangingSpell> hanging,
  List<RunningSpell> running,
});

/// Pure parse of a Practical Magic export: the single-character envelope
/// (`practicalmagicCharacter: 1`) or a whole-library blob. Throws
/// [FormatException] on junk and [SchemaTooNewException] on a newer save.
/// Old saves get the same schema migrations a library load gets
/// (`shiftAdverbials` below schema 2).
ShareBundle decodeShare(String raw) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw const FormatException('Not valid JSON');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Not a Practical Magic export');
  }

  if (decoded['practicalmagicCharacter'] == 1) {
    final v = decoded['schemaVersion'] as int? ?? 1;
    if (v > kSchemaVersion) throw SchemaTooNewException(v, kSchemaVersion);
    try {
      return (
        characters: [
          Character.fromJson(decoded['character'] as Map<String, dynamic>),
        ],
        spells: [
          for (final s in decoded['spells'] as List? ?? const <dynamic>[])
            Spell.fromJson(s as Map<String, dynamic>, shiftAdverbials: v < 2),
        ],
        history: [
          for (final h in decoded['history'] as List? ?? const <dynamic>[])
            // Same migration the spells above get — a record's snapshot is
            // a Spell too.
            CastRecord.fromJson(
              h as Map<String, dynamic>,
              shiftAdverbials: v < 2,
            ),
        ],
        hanging: [
          for (final h in decoded['hanging'] as List? ?? const <dynamic>[])
            HangingSpell.fromJson(
              h as Map<String, dynamic>,
              shiftAdverbials: v < 2,
            ),
        ],
        running: [
          for (final r in decoded['running'] as List? ?? const <dynamic>[])
            RunningSpell.fromJson(
              r as Map<String, dynamic>,
              shiftAdverbials: v < 2,
            ),
        ],
      );
    } on SchemaTooNewException {
      rethrow;
    } on Object catch (_) {
      throw const FormatException('Character data is damaged');
    }
  }

  if (decoded.containsKey('characters')) {
    final Library lib;
    try {
      lib = Library.fromJson(decoded);
    } on SchemaTooNewException {
      rethrow;
    } on Object catch (_) {
      throw const FormatException('Library data is damaged');
    }
    return (
      characters: lib.characters,
      spells: lib.spells,
      history: lib.history,
      hanging: lib.hanging,
      running: lib.running,
    );
  }

  throw const FormatException('Not a Practical Magic export');
}
```

Add to `packages/polarity_grammar/lib/polarity_grammar.dart` (alphabetical with the other `src/model/` exports):

```dart
export 'src/model/share.dart';
```

NOTE: if `CastRecord`/`HangingSpell`/`RunningSpell` live in `library.dart` (they do — check imports compile), the `spell.dart` import may be unused; keep only the imports the analyzer needs.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd ~/StudioProjects/magic/packages/polarity_grammar && flutter test test/share_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/StudioProjects/magic && git add packages/polarity_grammar && git commit -m "feat(package): decodeShare — shared export parser for host apps"
```

---

### Task 2: Standalone app delegates to `decodeShare`; push (magic repo)

**Files:**
- Modify: `~/StudioProjects/magic/app/lib/state.dart` (`_decodeImport`, ~lines 221–400)

**Interfaces:**
- Consumes: `decodeShare`/`ShareBundle` from Task 1.
- Produces: pushed GitHub commit SHA on branch `feat/share-decode` merged to `main` — Task 3 pins it.

- [ ] **Step 1: Replace the parse half of `_decodeImport`**

In `app/lib/state.dart`, `_decodeImport` currently opens with `jsonDecode`, the envelope branch, the library branch, and the `else throw` (everything before the `// Fresh ids across the board, references remapped.` comment). Replace that whole parse section with:

```dart
  ({
    List<Character> characters,
    List<Spell> spells,
    List<CastRecord> history,
    List<HangingSpell> hanging,
    List<RunningSpell> running,
  })
  _decodeImport(String raw) {
    final d = decodeShare(raw);
    final characters = d.characters;
    final spells = d.spells;
    final history = d.history;
    final hangingIn = d.hanging;
    final runningIn = d.running;

    // Fresh ids across the board, references remapped.
    ...existing remap code unchanged from here down...
```

Delete nothing below that comment; the remap half stays byte-identical. Remove any now-unused imports (`dart:convert` stays — `exportLibraryJson`/`exportCharacterJson` still use it).

- [ ] **Step 2: Run the app + package test suites**

Run: `cd ~/StudioProjects/magic/app && flutter test && cd ../packages/polarity_grammar && flutter test`
Expected: PASS — delegation is behavior-neutral; the app's existing import tests (`backup_export_test.dart` etc.) assert the same error messages `decodeShare` kept.

- [ ] **Step 3: Run analyzer**

Run: `cd ~/StudioProjects/magic && flutter analyze app packages/polarity_grammar`
Expected: No issues.

- [ ] **Step 4: Commit, merge to main, push**

```bash
cd ~/StudioProjects/magic
git add app/lib/state.dart && git commit -m "refactor(app): _decodeImport delegates to package decodeShare"
git checkout main && git merge --no-ff feat/share-decode -m "feat: shared decodeShare export parser"
git push origin main
git rev-parse HEAD   # <- record this SHA for Task 3
```

(If this repo's convention is PR-based instead, open + merge a PR via `gh pr create` — either way `main` on GitHub must contain the commit; record the merged SHA.)

---

### Task 3: Bump juice's pinned ref (juice repo)

**Files:**
- Modify: `~/StudioProjects/juice/pubspec.yaml:28` (the `ref:` under `polarity_grammar`)

**Interfaces:**
- Consumes: pushed SHA from Task 2.
- Produces: `pg.decodeShare` / `pg.ShareBundle` resolvable in juice.

- [ ] **Step 1: Update the ref**

In `pubspec.yaml`, replace `ref: 6646f1fa5590b623f0011b660eb9fde9abbd4a47` with the Task 2 SHA (full 40-char).

- [ ] **Step 2: Fetch + sanity-check**

Run: `cd ~/StudioProjects/juice && flutter pub get && flutter analyze lib`
Expected: pub resolves; no analyzer issues.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock && git commit -m "chore(deps): bump polarity_grammar for decodeShare"
```

---

### Task 4: `MagicController.importSpells` + `deleteSpells` (juice repo)

**Files:**
- Modify: `~/StudioProjects/juice/lib/state/magic_controller.dart`
- Test: `~/StudioProjects/juice/test/magic_import_test.dart` (new)

**Interfaces:**
- Consumes: `pg.decodeShare` (Task 1/3); existing `_lib`, `_commit`, `_freshId`, `_byId` in `MagicController`.
- Produces: `Future<List<pg.Spell>> importSpells(String targetPgCharacterId, String raw)` and `Future<void> deleteSpells(Iterable<String> ids)` — Task 5's dialog + undo call these.

- [ ] **Step 1: Write the failing test**

Create `test/magic_import_test.dart`:

```dart
import 'dart:convert';

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

pg.Spell _spell(String id, String characterId, String name) => pg.Spell(
      id: id,
      characterId: characterId,
      name: name,
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

String _envelope() => jsonEncode({
      'practicalmagicCharacter': 1,
      'schemaVersion': pg.kSchemaVersion,
      'character': const pg.Character(
              id: 'ext-1', name: 'Vex', baseMana: 6, currentMana: 6)
          .toJson(),
      'spells': [_spell('ext-s1', 'ext-1', 'Spark').toJson()],
    });

Future<MagicController> _readyController(ProviderContainer container) async {
  await container.read(magicProvider.future);
  final ctrl = container.read(magicProvider.notifier);
  await ctrl.upsertCharacter(
    const pg.Character(id: 'pg-1', name: 'Ash', baseMana: 4, currentMana: 4),
  );
  return ctrl;
}

void main() {
  test('importSpells: envelope spells land on the target with fresh ids',
      () async {
    final container = _container();
    addTearDown(container.dispose);
    final ctrl = await _readyController(container);

    final added = await ctrl.importSpells('pg-1', _envelope());

    expect(added, hasLength(1));
    final lib = container.read(magicProvider).valueOrNull!;
    final got = lib.spellsFor('pg-1').single;
    expect(got.name, 'Spark');
    expect(got.characterId, 'pg-1');
    expect(got.id, isNot('ext-s1'));
    // The exported caster is NOT imported — spells only.
    expect(lib.characters.map((c) => c.id), ['pg-1']);
  });

  test('importSpells: library blob flattens all characters\' spells',
      () async {
    final container = _container();
    addTearDown(container.dispose);
    final ctrl = await _readyController(container);

    final blob = jsonEncode(const pg.Library.empty().copyWith(
      characters: [
        const pg.Character(id: 'a', name: 'A', baseMana: 4, currentMana: 4),
        const pg.Character(id: 'b', name: 'B', baseMana: 4, currentMana: 4),
      ],
      spells: [_spell('sa', 'a', 'Alpha'), _spell('sb', 'b', 'Beta')],
    ).toJson());

    final added = await ctrl.importSpells('pg-1', blob);
    expect(added, hasLength(2));
    expect(
      container
          .read(magicProvider)
          .valueOrNull!
          .spellsFor('pg-1')
          .map((s) => s.name)
          .toSet(),
      {'Alpha', 'Beta'},
    );
  });

  test('importing twice duplicates rather than collides', () async {
    final container = _container();
    addTearDown(container.dispose);
    final ctrl = await _readyController(container);

    await ctrl.importSpells('pg-1', _envelope());
    await ctrl.importSpells('pg-1', _envelope());
    final spells =
        container.read(magicProvider).valueOrNull!.spellsFor('pg-1');
    expect(spells, hasLength(2));
    expect(spells[0].id, isNot(spells[1].id));
  });

  test('junk throws and the library is untouched', () async {
    final container = _container();
    addTearDown(container.dispose);
    final ctrl = await _readyController(container);

    await expectLater(
        ctrl.importSpells('pg-1', '{{{'), throwsFormatException);
    expect(
        container.read(magicProvider).valueOrNull!.spellsFor('pg-1'), isEmpty);
  });

  test('unknown target caster throws StateError', () async {
    final container = _container();
    addTearDown(container.dispose);
    final ctrl = await _readyController(container);

    await expectLater(
        ctrl.importSpells('nope', _envelope()), throwsStateError);
  });

  test('deleteSpells removes exactly the given ids in one commit', () async {
    final container = _container();
    addTearDown(container.dispose);
    final ctrl = await _readyController(container);
    final added = await ctrl.importSpells('pg-1', _envelope());
    await ctrl.upsertSpell(_spell('keep', 'pg-1', 'Keeper'));

    await ctrl.deleteSpells([for (final s in added) s.id]);
    expect(
      container
          .read(magicProvider)
          .valueOrNull!
          .spellsFor('pg-1')
          .single
          .name,
      'Keeper',
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/magic_import_test.dart`
Expected: FAIL — `importSpells`/`deleteSpells` undefined.

- [ ] **Step 3: Implement**

In `lib/state/magic_controller.dart`, after `deleteSpell`:

```dart
  /// Removes every spell in [ids] in one commit — the import undo path.
  Future<void> deleteSpells(Iterable<String> ids) async {
    final drop = ids.toSet();
    await _commit(_lib.copyWith(
        spells: _lib.spells.where((s) => !drop.contains(s.id)).toList()));
  }

  /// Merge-imports the spells from a Practical Magic export (either shape;
  /// all characters' spells flattened) into [targetPgCharacterId]'s
  /// spellbook: fresh ids, appended — never replaces, so importing the same
  /// export twice duplicates. Mana/history/hanging/running in the export are
  /// ignored. Returns the added spells (count + undo). Throws
  /// [FormatException] / [pg.SchemaTooNewException] like [pg.decodeShare],
  /// and [StateError] when the target caster is missing.
  Future<List<pg.Spell>> importSpells(
      String targetPgCharacterId, String raw) async {
    if (_byId(targetPgCharacterId) == null) {
      throw StateError('No caster with id $targetPgCharacterId');
    }
    final d = pg.decodeShare(raw);
    final now = DateTime.now();
    final added = <pg.Spell>[
      for (final s in d.spells)
        s.copyWith(
          id: _freshId('spell', now),
          characterId: targetPgCharacterId,
          editedAt: now,
        ),
    ];
    await _commit(_lib.copyWith(spells: [..._lib.spells, ...added]));
    return added;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/magic_import_test.dart`
Expected: PASS (6 tests). Also run the neighbors: `flutter test test/magic_controller_test.dart test/magic_store_test.dart` — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/magic_controller.dart test/magic_import_test.dart
git commit -m "feat(magic): MagicController.importSpells — merge-import from Practical Magic exports"
```

---

### Task 5: Import button + paste dialog (juice repo)

**Files:**
- Modify: `~/StudioProjects/juice/lib/features/sheet_widgets.dart` (the action `Wrap` at the end of `magicSection`, plus a new private dialog helper)
- Test: `~/StudioProjects/juice/test/magic_import_ui_test.dart` (new)

**Interfaces:**
- Consumes: `importSpells`/`deleteSpells` (Task 4); existing `showUndoSnackbar` (`lib/shared/undo_snackbar.dart`, already imported by sheet_widgets.dart — verify).
- Produces: keys `magic-import`, `magic-import-field`, `magic-import-confirm`, `magic-import-error`.

- [ ] **Step 1: Write the failing test**

Create `test/magic_import_ui_test.dart` (harness copied from `test/magic_section_test.dart`'s `_pump` — the linked-caster shape):

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/features/sheet_widgets.dart';
import 'package:loreseer/state/providers.dart';
import 'package:polarity_grammar/polarity_grammar.dart' as pg;
import 'package:shared_preferences/shared_preferences.dart';

String _envelope() => jsonEncode({
      'practicalmagicCharacter': 1,
      'schemaVersion': pg.kSchemaVersion,
      'character': const pg.Character(
              id: 'ext-1', name: 'Vex', baseMana: 6, currentMana: 6)
          .toJson(),
      'spells': [
        pg.Spell(
          id: 'ext-s1',
          characterId: 'ext-1',
          name: 'Spark',
          effects: const [
            pg.EffectChoice(
                pg.CardChoice('effect.sensory.numb', pg.PoleSide.a), 1),
          ],
          form: const pg.CardChoice('form.link', pg.PoleSide.a),
          targets: const [pg.TargetPhrase(count: 1, targetType: 1)],
          size: 0,
          distance: 0,
          timing: 0,
          favorite: false,
          createdAt: DateTime(2026, 1, 1),
          editedAt: DateTime(2026, 1, 1),
        ).toJson(),
      ],
    });

Future<void> _pump(WidgetTester tester) async {
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
        body: Consumer(builder: (context, ref, __) {
          final live =
              ref.watch(charactersProvider).valueOrNull?.firstOrNull ?? char;
          return SingleChildScrollView(child: magicSection(context, ref, live));
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('import button opens dialog; valid paste imports with undo',
      (tester) async {
    await _pump(tester);

    await tester.scrollUntilVisible(
        find.byKey(const Key('magic-import')), 200);
    await tester.tap(find.byKey(const Key('magic-import')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('magic-import-field')), _envelope());
    await tester.tap(find.byKey(const Key('magic-import-confirm')));
    await tester.pumpAndSettle();

    // Dialog closed, snackbar up, spell in the book.
    expect(find.byKey(const Key('magic-import-field')), findsNothing);
    expect(find.text('Imported 1 spell'), findsOneWidget);
    expect(find.text('Spark'), findsOneWidget);

    // Undo removes it again.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Spark'), findsNothing);
  });

  testWidgets('junk paste shows an inline error and stays open',
      (tester) async {
    await _pump(tester);

    await tester.scrollUntilVisible(
        find.byKey(const Key('magic-import')), 200);
    await tester.tap(find.byKey(const Key('magic-import')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('magic-import-field')), '{{{');
    await tester.tap(find.byKey(const Key('magic-import-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('magic-import-error')), findsOneWidget);
    expect(find.text('Not valid JSON'), findsOneWidget);
    // Still open.
    expect(find.byKey(const Key('magic-import-field')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/magic_import_ui_test.dart`
Expected: FAIL — no `magic-import` key.

- [ ] **Step 3: Implement button + dialog**

In `lib/features/sheet_widgets.dart`, add to the action `Wrap` at the end of `magicSection` (after the 'Build spell' button):

```dart
          TextButton.icon(
            key: const Key('magic-import'),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Import spells'),
            onPressed: () async {
              final ctrl = ref.read(magicProvider.notifier);
              final added = await _showImportSpells(context, ref, pgChar.id);
              // Snackbar on the sheet's context, AFTER the dialog popped —
              // the log-and-pop rule: the surviving ref/context is the
              // caller's, never the dialog's.
              if (added == null || !context.mounted) return;
              if (added.isEmpty) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(
                      content: Text('No spells in that export')));
                return;
              }
              showUndoSnackbar(
                context,
                'Imported ${added.length} '
                'spell${added.length == 1 ? '' : 's'}',
                () => ctrl.deleteSpells([for (final s in added) s.id]),
              );
            },
          ),
```

New private helper in the same file (near `_confirmDisableMagic`):

```dart
/// Paste-JSON import dialog. Returns the spells added (empty list when the
/// export held none), or null on cancel. Parse errors render inline and
/// keep the dialog open.
Future<List<pg.Spell>?> _showImportSpells(
    BuildContext context, WidgetRef ref, String pgCharacterId) {
  final input = TextEditingController();
  String? error;
  return showDialog<List<pg.Spell>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Import spells'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Paste an export from the Practical Magic app.'),
            const SizedBox(height: 8),
            TextField(
              key: const Key('magic-import-field'),
              controller: input,
              maxLines: 6,
              decoration: const InputDecoration(hintText: '{ … }'),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                key: const Key('magic-import-error'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('magic-import-confirm'),
            onPressed: () async {
              try {
                final added = await ref
                    .read(magicProvider.notifier)
                    .importSpells(pgCharacterId, input.text);
                if (context.mounted) Navigator.pop(context, added);
              } on pg.SchemaTooNewException catch (e) {
                setState(() => error = '$e');
              } on FormatException catch (e) {
                setState(() => error = e.message);
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    ),
  );
}
```

GOTCHA: this `FilledButton` sits in dialog `actions` (bounded), not beside an `Expanded` field — the full-width-theme trap doesn't apply here, no `minimumSize` pin needed.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/magic_import_ui_test.dart`
Expected: PASS. Also `flutter test test/magic_section_test.dart test/magic_section_spellbook_test.dart` — PASS (Wrap gained a button; keys untouched).

- [ ] **Step 5: Commit**

```bash
git add lib/features/sheet_widgets.dart test/magic_import_ui_test.dart
git commit -m "feat(magic): import spells from a Practical Magic export"
```

---

### Task 6: Rename "Polarity Grammar" → "Practical Magic" in juice UI; full verify

**Files:**
- Modify: `~/StudioProjects/juice/lib/features/sheet_widgets.dart:656,667,920`
- Modify: `~/StudioProjects/juice/lib/engine/models/character.dart:293` (comment)
- Modify: `~/StudioProjects/juice/lib/state/providers.dart:576,627` (comments)
- Modify: `~/StudioProjects/juice/test/magic_caster_settings_test.dart:12` (comment)

**Interfaces:**
- Consumes: nothing new.
- Produces: UI label "Enable Practical Magic casting" (no test asserts the old label — they all use the `magic-enable` key).

- [ ] **Step 1: Rename the strings + comments**

- `sheet_widgets.dart:667`: `const Text('Enable Polarity Grammar casting')` → `const Text('Enable Practical Magic casting')`.
- `sheet_widgets.dart:656,920` doc comments: "Polarity Grammar casting" → "Practical Magic casting".
- `character.dart:293`, `providers.dart:576,627`, `test/magic_caster_settings_test.dart:12`: same comment swap.
- Sweep for stragglers: `grep -rn "Polarity" lib test` — after the edits, the only hits should be `polarityId` identifiers and the `polarity_grammar` package imports. Fix any other prose hit the same way.

Do NOT touch: `polarityId` (field + JSON key), `loreseer.magic.v1`, package imports, widget keys.

- [ ] **Step 2: Full verify**

Run: `flutter analyze && flutter test`
Expected: analyze clean; suite green. If any test fails, use the final "Failing tests:" block to name it — never the `+P -F:` progress lines.

- [ ] **Step 3: Commit**

```bash
git add -A lib test
git commit -m "chore(magic): rename Polarity Grammar to Practical Magic in UI strings"
```

---

## Ship

After Task 6: `/ship-pr` from the juice repo (single PR for Tasks 3–6; the magic-repo change already landed on its main in Task 2).
