# Character Library (PR 1 of streamline epic) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An app-global character library (library of copies) so heroes are reusable across campaigns — managed from the launcher, imported/saved from the roster.

**Architecture:** Pure JSON-round-trip copy helpers in the engine; a `CharacterLibraryNotifier` mirroring the bestiary's app-global posture (`loreseer.charlibrary.v1`, NOT session-scoped, NOT exported); a launcher-level manage screen; roster hooks ("From library" in the new-character dialog, "Save to library" on row menus).

**Tech Stack:** Flutter + flutter_riverpod + shared_preferences (existing rails only; no new deps).

**Spec:** `docs/superpowers/specs/2026-08-12-streamline-library-exclusive-capabilities-design.md` (Part 1)

## Global Constraints

- Copies get FRESH ids and drop `polarityId` (Practical Magic link is campaign-local).
- Campaign import additionally resets `role` to pc and clears `starred`.
- Library key `loreseer.charlibrary.v1` must NOT appear in `sessionScopedKeys` (providers.dart) — that would export it.
- Destructive deletes get the `showUndoSnackbar` treatment (repo doctrine), never a confirm dialog.
- Tests: never construct `GemmaInterpreterService`; launcher-pumping tests MUST override `interpreterServiceProvider` with the fake and set `'loreseer.ai_offer_seen.v1': true` in mock prefs (see existing `test/launcher_welcome_test.dart` for the pattern — copy its setup).
- Widget tests pumping HomeShell/JournalScreen must override asset providers (see `test/` helpers) — the tasks below avoid that by pumping screens directly.
- Format only files you edit (`dart format <file>`), never repo-wide.

---

### Task 1: Pure copy helpers

**Files:**
- Create: `lib/engine/character_library.dart`
- Test: `test/character_library_copy_test.dart`

**Interfaces:**
- Consumes: `Character` (`lib/engine/models.dart`, part file `models/character.dart`; `toJson()` omits defaults, `fromJson` tolerant).
- Produces: `Character libraryCopy(Character c, String newId)`, `Character campaignCopy(Character c, String newId)` — used by Tasks 2–5.

- [ ] **Step 1: Write the failing test**

```dart
// test/character_library_copy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/character_library.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  final src = Character(
    id: 'orig',
    name: 'Brakka',
    note: 'scarred',
    stats: const [CharStat(label: 'STR', value: '14')],
    starred: true,
    role: CharacterRole.companion,
    conditions: const ['poisoned'],
    coins: 7,
    polarityId: 'pg-1',
    dnd: DndSheet.premade(),
  );

  test('libraryCopy: fresh id, polarityId dropped, rest preserved', () {
    final copy = libraryCopy(src, 'lib-1');
    expect(copy.id, 'lib-1');
    expect(copy.polarityId, isNull);
    expect(copy.name, 'Brakka');
    expect(copy.note, 'scarred');
    expect(copy.stats.single.label, 'STR');
    expect(copy.dnd, isNotNull);
    expect(copy.starred, isTrue); // library keeps flags as captured
    expect(copy.role, CharacterRole.companion);
    expect(copy.conditions, ['poisoned']);
    expect(copy.coins, 7);
    // Source untouched.
    expect(src.id, 'orig');
    expect(src.polarityId, 'pg-1');
  });

  test('campaignCopy: also resets role to pc and clears starred', () {
    final copy = campaignCopy(src, 'camp-1');
    expect(copy.id, 'camp-1');
    expect(copy.polarityId, isNull);
    expect(copy.role, CharacterRole.pc);
    expect(copy.starred, isFalse);
    expect(copy.conditions, ['poisoned']); // play state comes along
    expect(copy.dnd, isNotNull);
  });
}
```

Note: check `CharStat`'s actual constructor in `lib/engine/models/character.dart` (top of file) before running — if `value` is an int or the parameter names differ, adjust the test's `CharStat` literal to match. Everything else stands.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/character_library_copy_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'juice_oracle/engine/character_library.dart'` (file missing).

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/engine/character_library.dart
//
// Pure copy helpers for the app-global character library. Copies go through
// JSON so every sheet type rides along without a per-field list. The library
// is a library of COPIES — play state diverges per campaign after the copy.
import 'models.dart';

/// Copy for saving INTO the library: fresh [newId]; the Practical-Magic link
/// is dropped because the linked magic record lives in the source campaign's
/// storage and would dangle anywhere else.
Character libraryCopy(Character c, String newId) {
  final j = c.toJson()
    ..['id'] = newId
    ..remove('polarityId');
  return Character.fromJson(j);
}

/// Copy for importing INTO a campaign roster: everything [libraryCopy] does,
/// plus role reset to pc and star cleared (both are campaign-local flags).
Character campaignCopy(Character c, String newId) {
  final j = c.toJson()
    ..['id'] = newId
    ..remove('polarityId')
    ..remove('role')
    ..remove('starred');
  return Character.fromJson(j);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/character_library_copy_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/character_library.dart test/character_library_copy_test.dart
git commit -m "feat(library): pure character copy helpers (fresh id, magic link dropped)"
```

---

### Task 2: CharacterLibraryNotifier (app-global store)

**Files:**
- Modify: `lib/state/providers.dart` (add notifier + provider right after `bestiaryProvider`, ~line 2111)
- Test: `test/character_library_provider_test.dart`

**Interfaces:**
- Consumes: `decodePersisted` (providers.dart:88), `prefsProvider`, `Character`, `libraryCopy` (Task 1).
- Produces: `characterLibraryProvider` (`AsyncNotifierProvider<CharacterLibraryNotifier, List<Character>>`) with `add(Character)`, `remove(String id)`, `rename(String id, String name)`, `insertAt(int index, Character c)` — used by Tasks 4–5. Key `loreseer.charlibrary.v1`.

- [ ] **Step 1: Write the failing test**

```dart
// test/character_library_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('add/remove/rename round-trip and persist app-globally', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(characterLibraryProvider.notifier);

    await notifier.add(const Character(id: 'a', name: 'Brakka'));
    await notifier.add(const Character(id: 'b', name: 'Yeva'));
    expect((await container.read(characterLibraryProvider.future)).length, 2);

    await notifier.rename('a', 'Brakka the Bold');
    var list = await container.read(characterLibraryProvider.future);
    expect(list.firstWhere((c) => c.id == 'a').name, 'Brakka the Bold');

    await notifier.remove('b');
    list = await container.read(characterLibraryProvider.future);
    expect(list.single.id, 'a');

    // Key is app-global: NOT suffixed with a session id.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('loreseer.charlibrary.v1'), isNotNull);
  });

  test('corrupt storage degrades to empty, corrupt row skipped', () async {
    SharedPreferences.setMockInitialValues(
        {'loreseer.charlibrary.v1': '[{"id":"ok","name":"Ok"},{"bad":1}]'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final list = await container.read(characterLibraryProvider.future);
    expect(list.single.id, 'ok');
  });

  test('insertAt restores a deleted row for undo', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(characterLibraryProvider.notifier);
    await notifier.add(const Character(id: 'a', name: 'A'));
    await notifier.add(const Character(id: 'b', name: 'B'));
    await notifier.remove('a');
    await notifier.insertAt(0, const Character(id: 'a', name: 'A'));
    final list = await container.read(characterLibraryProvider.future);
    expect(list.map((c) => c.id).toList(), ['a', 'b']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/character_library_provider_test.dart`
Expected: FAIL — `characterLibraryProvider` undefined.

- [ ] **Step 3: Write minimal implementation**

Insert after `bestiaryProvider`'s closing declaration (providers.dart ~line 2111), following the `BestiaryNotifier` shape exactly (same tolerant decode; `Character.fromJson` throws on bad rows, so wrap rows like `decodePersistedList` does — reuse it):

```dart
/// App-global character library — a library of COPIES so heroes are reusable
/// across campaigns. Like [bestiaryProvider]: NOT session-scoped, NOT
/// exported. Copies in/out go through the pure helpers in
/// `lib/engine/character_library.dart` (fresh id, magic link dropped).
class CharacterLibraryNotifier extends AsyncNotifier<List<Character>> {
  static const _key = 'loreseer.charlibrary.v1';

  @override
  Future<List<Character>> build() async {
    final raw = (await ref.read(prefsProvider.future)).getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    return decodePersistedList(raw, Character.fromJson);
  }

  Future<List<Character>> get _ready async => state.valueOrNull ?? await future;

  Future<void> _save(List<Character> list) async {
    await (await ref.read(prefsProvider.future))
        .setString(_key, jsonEncode(list.map((c) => c.toJson()).toList()));
    state = AsyncData(list);
  }

  Future<void> add(Character c) async {
    await _save([...await _ready, c]);
  }

  Future<void> remove(String id) async {
    await _save((await _ready).where((c) => c.id != id).toList());
  }

  Future<void> rename(String id, String name) async {
    await _save([
      for (final c in await _ready) c.id == id ? c.copyWith(name: name) : c,
    ]);
  }

  /// Re-inserts [c] at [index] (clamped) — the delete-undo restore.
  Future<void> insertAt(int index, Character c) async {
    final list = [...await _ready];
    list.insert(index.clamp(0, list.length), c);
    await _save(list);
  }
}

final characterLibraryProvider =
    AsyncNotifierProvider<CharacterLibraryNotifier, List<Character>>(
        CharacterLibraryNotifier.new);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/character_library_provider_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Verify the key is NOT exported**

Run: `grep -n "charlibrary" lib/state/providers.dart lib/state/campaign_io.dart lib/engine/models/session.dart`
Expected: hits ONLY inside `CharacterLibraryNotifier` — none in `sessionScopedKeys` or campaign IO.

- [ ] **Step 6: Commit**

```bash
git add lib/state/providers.dart test/character_library_provider_test.dart
git commit -m "feat(library): app-global character library store (loreseer.charlibrary.v1)"
```

---

### Task 3: Campaign-side import + cross-session roster read

**Files:**
- Modify: `lib/state/providers.dart` (`CharacterNotifier`, after `addFunnel`; plus one top-level helper near `decodePersistedList`)
- Test: `test/character_library_import_test.dart`

**Interfaces:**
- Consumes: `campaignCopy` (Task 1), `_newId()` (providers.dart:81), `_PersistedList._persist/_ready`, `decodePersistedList`.
- Produces:
  - `Future<String> CharacterNotifier.addFromLibrary(Character libraryEntry)` — copies in at top of roster, returns new id. Used by Task 5.
  - `List<Character> sessionCharactersFromPrefs(SharedPreferences prefs, String sessionId)` (top-level, sync) — tolerant read of ANY session's roster for the library's "Copy from campaign" picker. Used by Task 4.

- [ ] **Step 1: Write the failing test**

```dart
// test/character_library_import_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('addFromLibrary copies with fresh id, pc role, no star/magic link',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const entry = Character(
        id: 'lib-1',
        name: 'Brakka',
        starred: true,
        role: CharacterRole.npc,
        polarityId: 'pg-9');
    final id = await container
        .read(charactersProvider.notifier)
        .addFromLibrary(entry);
    final roster = await container.read(charactersProvider.future);
    final added = roster.firstWhere((c) => c.id == id);
    expect(id, isNot('lib-1'));
    expect(added.name, 'Brakka');
    expect(added.role, CharacterRole.pc);
    expect(added.starred, isFalse);
    expect(added.polarityId, isNull);
  });

  test('sessionCharactersFromPrefs reads another session tolerantly', () async {
    SharedPreferences.setMockInitialValues({
      'loreseer.characters.v1.other':
          '[{"id":"x","name":"Xa"},{"corrupt":true}]',
    });
    final prefs = await SharedPreferences.getInstance();
    final list = sessionCharactersFromPrefs(prefs, 'other');
    expect(list.single.name, 'Xa');
    expect(sessionCharactersFromPrefs(prefs, 'missing'), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/character_library_import_test.dart`
Expected: FAIL — `addFromLibrary` / `sessionCharactersFromPrefs` undefined.

- [ ] **Step 3: Write minimal implementation**

In `CharacterNotifier` (providers.dart, after `addFunnel`), add — needs `import '../engine/character_library.dart';` at the top of providers.dart:

```dart
  /// Copies a library entry into this campaign's roster (fresh id, role reset
  /// to pc, star + magic link cleared) and returns the new character's id.
  Future<String> addFromLibrary(Character libraryEntry) async {
    final id = _newId();
    await _persist([campaignCopy(libraryEntry, id), ...await _ready]);
    return id;
  }
```

Top-level, next to `decodePersistedList`:

```dart
/// Tolerant read of ANY session's roster straight from prefs — the character
/// library's "Copy from campaign" picker needs rosters of campaigns that are
/// not active (the active one comes from [charactersProvider]).
List<Character> sessionCharactersFromPrefs(
        SharedPreferences prefs, String sessionId) {
  final raw = prefs.getString('loreseer.characters.v1.$sessionId');
  if (raw == null || raw.isEmpty) return const [];
  return decodePersistedList(raw, Character.fromJson);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/character_library_import_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/character_library_import_test.dart
git commit -m "feat(library): roster import from library + cross-session roster read"
```

---

### Task 4: Library screen + launcher entry

**Files:**
- Create: `lib/features/character_library_screen.dart`
- Modify: `lib/features/launcher_screen.dart` (non-pristine branch, after the `launcher-import` ListTile ~line 347)
- Test: `test/character_library_screen_test.dart`

**Interfaces:**
- Consumes: `characterLibraryProvider` (Task 2), `libraryCopy` (Task 1), `sessionCharactersFromPrefs` (Task 3), `sessionsProvider`, `prefsProvider`, `showUndoSnackbar` (`lib/shared/undo_snackbar.dart`), `campaignSubtitle` (models).
- Produces: `CharacterLibraryScreen` (pushed route). Keys: `library-char-<id>`, `library-rename-<id>`, `library-delete-<id>`, `library-copy-from-campaign`, `library-src-<sessionId>`, `library-src-char-<id>`, launcher entry `launcher-library`.

- [ ] **Step 1: Write the failing test**

```dart
// test/character_library_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/character_library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpLibrary(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: CharacterLibraryScreen())));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('lists entries; delete has undo', (tester) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.charlibrary.v1': '[{"id":"a","name":"Brakka"}]',
    });
    await pumpLibrary(tester);
    expect(find.text('Brakka'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-delete-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-char-a')), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-char-a')), findsOneWidget);
  });

  testWidgets('copy from campaign imports a copy (magic link dropped)',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
          '{"active":"s1","sessions":[{"id":"s1","name":"Alpha"}]}',
      'loreseer.characters.v1.s1':
          '[{"id":"c1","name":"Yeva","polarityId":"pg-1"}]',
    });
    await pumpLibrary(tester);
    await tester.tap(find.byKey(const Key('library-copy-from-campaign')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-src-s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-src-char-c1')));
    await tester.pumpAndSettle();
    expect(find.text('Yeva'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('loreseer.charlibrary.v1')!;
    expect(raw, contains('"Yeva"'));
    expect(raw, isNot(contains('polarityId')));
    expect(raw, isNot(contains('"id":"c1"'))); // fresh id
  });
}
```

Note: check the exact `loreseer.sessions.v1` JSON shape against `SessionsState.toJson`/`fromJson` in `lib/engine/models/session.dart` before running; adjust the fixture keys to match (the registry may carry extra fields — extra absence is fine, key NAMES must match).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/character_library_screen_test.dart`
Expected: FAIL — `character_library_screen.dart` missing.

- [ ] **Step 3: Implement the screen**

```dart
// lib/features/character_library_screen.dart
//
// App-global character library manager, opened from the launcher. A library
// of COPIES: nothing here references campaign state, and copying in/out
// always mints fresh ids (see lib/engine/character_library.dart).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/character_library.dart';
import '../engine/models.dart';
import '../shared/undo_snackbar.dart';
import '../state/providers.dart';

class CharacterLibraryScreen extends ConsumerWidget {
  const CharacterLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries =
        ref.watch(characterLibraryProvider).valueOrNull ?? const <Character>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Character library')),
      body: ListView(
        children: [
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No saved characters yet. Copy one in from a '
                  'campaign below, or use "Save to library" on a roster '
                  'character.'),
            ),
          for (final c in entries)
            ListTile(
              key: Key('library-char-${c.id}'),
              title: Text(c.name),
              subtitle: c.note.isEmpty
                  ? null
                  : Text(c.note, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('library-rename-${c.id}'),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Rename',
                    onPressed: () => _rename(context, ref, c),
                  ),
                  IconButton(
                    key: Key('library-delete-${c.id}'),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete',
                    onPressed: () => _delete(context, ref, c, entries),
                  ),
                ],
              ),
            ),
          const Divider(),
          ListTile(
            key: const Key('library-copy-from-campaign'),
            leading: const Icon(Icons.download_outlined),
            title: const Text('Copy from campaign'),
            onTap: () => _copyFromCampaign(context, ref),
          ),
        ],
      ),
    );
  }

  void _delete(BuildContext context, WidgetRef ref, Character c,
      List<Character> entries) {
    final idx = entries.indexWhere((x) => x.id == c.id);
    ref.read(characterLibraryProvider.notifier).remove(c.id);
    showUndoSnackbar(
        context,
        '${c.name} deleted',
        () => ref
            .read(characterLibraryProvider.notifier)
            .insertAt(idx < 0 ? 0 : idx, c));
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, Character c) async {
    final ctrl = TextEditingController(text: c.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    await ref.read(characterLibraryProvider.notifier).rename(c.id, name);
  }

  Future<void> _copyFromCampaign(BuildContext context, WidgetRef ref) async {
    final sessions = await ref.read(sessionsProvider.future);
    final prefs = await ref.read(prefsProvider.future);
    if (!context.mounted) return;
    // Step 1: pick a campaign.
    final sessionId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Copy from campaign'),
        children: [
          for (final s in sessions.sessions)
            SimpleDialogOption(
              key: Key('library-src-${s.id}'),
              onPressed: () => Navigator.pop(context, s.id),
              child: Text(s.name),
            ),
        ],
      ),
    );
    if (sessionId == null || !context.mounted) return;
    // Step 2: pick a character from that campaign's roster.
    final roster = sessionCharactersFromPrefs(prefs, sessionId);
    final picked = await showDialog<Character>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Pick a character'),
        children: [
          if (roster.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No characters in that campaign.'),
            ),
          for (final c in roster)
            SimpleDialogOption(
              key: Key('library-src-char-${c.id}'),
              onPressed: () => Navigator.pop(context, c),
              child: Text(c.name),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await ref
        .read(characterLibraryProvider.notifier)
        .add(libraryCopy(picked, DateTime.now().microsecondsSinceEpoch.toString()));
  }
}
```

- [ ] **Step 4: Add the launcher entry**

In `lib/features/launcher_screen.dart`, non-pristine branch, directly after the `launcher-import` ListTile (~line 347; NOT in the pristine branch — first-run stays minimal). Add the import `import 'character_library_screen.dart';` at the top.

```dart
                  ListTile(
                    key: const Key('launcher-library'),
                    leading: const Icon(Icons.people_outline),
                    title: const Text('Character library'),
                    subtitle: const Text('Reusable heroes, shared across '
                        'campaigns'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const CharacterLibraryScreen())),
                  ),
```

- [ ] **Step 5: Run tests**

Run: `flutter test test/character_library_screen_test.dart test/launcher_welcome_test.dart test/launcher_first_run_test.dart test/backup_nudge_test.dart`
Expected: all PASS (new screen tests + no launcher regressions).

- [ ] **Step 6: Format + commit**

```bash
dart format lib/features/character_library_screen.dart lib/features/launcher_screen.dart
git add lib/features/character_library_screen.dart lib/features/launcher_screen.dart test/character_library_screen_test.dart
git commit -m "feat(library): launcher-level character library screen"
```

---

### Task 5: Roster hooks (From library / Save to library)

**Files:**
- Modify: `lib/features/tracker_screen.dart` (new-character dialog `options` list ~line 624 + choice dispatch ~line 798; `lead-more` menu ~line 1298; compact card trailing ~line 1382)
- Test: `test/roster_library_hooks_test.dart`

**Interfaces:**
- Consumes: `characterLibraryProvider`, `libraryCopy`, `CharacterNotifier.addFromLibrary` (Tasks 1–3). Imports to add in tracker_screen.dart: `import '../engine/character_library.dart';`.
- Produces: keys `new-from-library`, `library-pick-<id>`, menu values `'save-library'` (lead card) and compact menu `compact-more-<id>` with Save to library + Delete-with-undo.

- [ ] **Step 1: Write the failing test**

Model the setup on an existing roster widget test — find one with `grep -rln "new-generic\|generate-npc" test/ | head` and copy its pump/override scaffolding (roster tests pump the tracker/sheet pane with mock prefs; do NOT pump HomeShell). Then:

```dart
// test/roster_library_hooks_test.dart — assertions to hit (scaffolding from
// the existing roster test):

// 1. Library non-empty → New-character dialog shows 'new-from-library';
//    tapping it lists 'library-pick-<id>'; picking adds to roster with role
//    pc, no star, fresh id.
// 2. Library empty → 'new-from-library' absent from the dialog.
// 3. lead-more menu shows 'Save to library'; selecting it adds a library
//    entry (assert prefs 'loreseer.charlibrary.v1' contains the name and NOT
//    the roster id — fresh id).
// 4. compact-more-<id> menu: 'Save to library' works the same; 'Delete'
//    removes with an Undo snackbar that restores.
```

Write real tests for all four (mock prefs: `'loreseer.charlibrary.v1': '[{"id":"L1","name":"Brakka"}]'` for 1/3/4, `{}` for 2).

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/roster_library_hooks_test.dart`
Expected: FAIL — keys not found.

- [ ] **Step 3: Implement the hooks**

(a) New-character dialog: in the `options` list builder (~line 624), the "From library" row is NOT a sheet-type option — add it as a separate ListTile above the sheet-type loop inside the dialog Column (before `for (final o in options)`), gated on the library being non-empty:

```dart
                Builder(builder: (context) {
                  final lib = ref.watch(characterLibraryProvider).valueOrNull ??
                      const <Character>[];
                  if (lib.isEmpty) return const SizedBox.shrink();
                  return ListTile(
                    key: const Key('new-from-library'),
                    title: const Text('From library'),
                    subtitle: const Text('Copy a saved character into this '
                        'campaign.'),
                    onTap: () => Navigator.pop(context, 'from-library'),
                  );
                }),
```

In the choice dispatch (after `if (choice == 'generic')` chain start), add:

```dart
    } else if (choice == 'from-library') {
      await _addFromLibrary(context);
```

And the handler beside `_newIronsworn`:

```dart
  Future<void> _addFromLibrary(BuildContext context) async {
    final lib = ref.read(characterLibraryProvider).valueOrNull ??
        const <Character>[];
    final picked = await showDialog<Character>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('From library'),
        children: [
          for (final c in lib)
            SimpleDialogOption(
              key: Key('library-pick-${c.id}'),
              onPressed: () => Navigator.pop(context, c),
              child: Text(c.name),
            ),
        ],
      ),
    );
    if (picked == null) return;
    final id =
        await ref.read(charactersProvider.notifier).addFromLibrary(picked);
    if (mounted) setState(() => _editingId = id);
  }
```

(b) `lead-more` menu (~line 1298): add case + item:

```dart
                      case 'save-library':
                        ref.read(characterLibraryProvider.notifier).add(
                            libraryCopy(c,
                                DateTime.now().microsecondsSinceEpoch.toString()));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('${c.name} saved to library')));
```

```dart
                    const PopupMenuItem<String>(
                      value: 'save-library',
                      child: Text('Save to library'),
                    ),
```

(c) Compact card (~line 1382): replace the bare delete IconButton with a `PopupMenuButton<String>` keyed `Key('compact-more-${c.id}')` carrying 'Save to library' (same handler as (b)) and 'Delete' — the delete now goes through `showUndoSnackbar` + `restoreAt` exactly like the lead card's delete case (capture `list`/`idx` from `charactersProvider` before `remove`, mirror lines 1308–1318).

- [ ] **Step 4: Run tests**

Run: `flutter test test/roster_library_hooks_test.dart`
Expected: PASS. Then the tracker's own suite: `flutter test test/ -x integration --name ""` is too broad — run the roster-touching files: `flutter test $(grep -rln "tracker_screen" test/ | tr '\n' ' ')`
Expected: all PASS.

- [ ] **Step 5: Format + commit**

```bash
dart format lib/features/tracker_screen.dart
git add lib/features/tracker_screen.dart test/roster_library_hooks_test.dart
git commit -m "feat(library): roster From-library import + Save-to-library"
```

---

### Task 6: Full verify + docs

**Files:**
- Modify: `CLAUDE.md` (project notes — one bullet), spec status line.

- [ ] **Step 1: Analyze + full suite**

Run: `flutter analyze && flutter test`
Expected: no analyzer issues; suite green. If a failure appears, use the final "Failing tests:" block to attribute (NEVER the `+P -F:` progress lines), and treat it as caused by this work until a main-branch baseline proves otherwise.

- [ ] **Step 2: Add CLAUDE.md project note**

Append a bullet under Project notes:

```markdown
- **Character library (2026-08-12)** — app-global library of character COPIES
  (`characterLibraryProvider`, `loreseer.charlibrary.v1`, NOT session-scoped/
  exported — bestiary posture). Pure copy helpers in
  `lib/engine/character_library.dart`: `libraryCopy` (fresh id, `polarityId`
  dropped), `campaignCopy` (also role→pc, star cleared). Launcher
  `launcher-library` → `CharacterLibraryScreen` (rename/delete-undo +
  two-step `library-copy-from-campaign` picker via
  `sessionCharactersFromPrefs`); roster `new-from-library` picker →
  `CharacterNotifier.addFromLibrary`; `save-library` on the lead-more +
  `compact-more-<id>` menus (compact delete gained undo). See
  `docs/superpowers/specs/2026-08-12-streamline-library-exclusive-capabilities-design.md`.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: character library project note"
```
