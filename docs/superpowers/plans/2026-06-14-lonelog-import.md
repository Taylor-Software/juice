# Lonelog Import (P2b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import a Lonelog `.md` as a new campaign — parse the YAML header, `[STATE]` block, and grouped beats into juice threads/characters/tracks/journal entries.

**Architecture:** A pure parser `lib/engine/lonelog_import.dart` (`parseLonelog`, no Flutter/clock) returns a `LonelogImport` of juice models; `SessionsNotifier.importLonelog` `toJson`s them into a new session's scoped prefs (mirroring `importCampaign`); the Campaigns dialog adds an "Import Lonelog (.md)" tile. Tolerant and lossy by design.

**Tech Stack:** Dart/Flutter, flutter_riverpod, shared_preferences, file_picker, package:flutter_test.

**Scope guard:** new session only; no roll-payload reconstruction; pretty notation rendering is P3.

---

## File structure

**New:** `lib/engine/lonelog_import.dart` (parser), `test/lonelog_import_test.dart`.
**Edit:** `lib/state/providers.dart` (`importLonelog`), `lib/shared/home_shell.dart` (menu tile + `_importLonelog`), `test/lonelog_campaign_ui_test.dart` (tile test).

---

### Task 1: Pure parser

**Files:**
- Create: `lib/engine/lonelog_import.dart`
- Create: `test/lonelog_import_test.dart`

- [ ] **Step 1: Write the failing test**

`test/lonelog_import_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/lonelog_export.dart';
import 'package:juice_oracle/engine/lonelog_import.dart';
import 'package:juice_oracle/engine/models.dart';

final _t = DateTime(2026, 6, 14);

void main() {
  test('parses YAML header (quoted) and falls back when title missing', () {
    final a = parseLonelog('---\ntitle: "West Marches"\ngenre: "noir"\n---\n',
        importedAt: _t);
    expect(a.campaignName, 'West Marches');
    expect(a.genre, 'noir');
    final b = parseLonelog('## Session log\n', importedAt: _t);
    expect(b.campaignName, 'Imported Lonelog');
  });

  test('parses the STATE block into threads, characters, tracks', () {
    const md = '---\ntitle: "C"\n---\n\n[STATE]\n'
        '[Thread:Slay the wyrm|Open]\n'
        '[Thread:Find the heir|Closed]\n'
        '[N:Vance|gruff, ally]\n'
        '[N:Mute]\n'
        '[Track:Ritual 3/6]\n'
        '[/STATE]\n';
    final imp = parseLonelog(md, importedAt: _t);
    expect(imp.threads.map((t) => t.title), ['Slay the wyrm', 'Find the heir']);
    expect(imp.threads[0].open, isTrue);
    expect(imp.threads[1].open, isFalse);
    expect(imp.characters[0].name, 'Vance');
    expect(imp.characters[0].tags, ['gruff', 'ally']);
    expect(imp.characters[1].name, 'Mute');
    expect(imp.characters[1].tags, isEmpty);
    expect(imp.tracks.single.name, 'Ritual');
    expect(imp.tracks.single.filled, 3);
    expect(imp.tracks.single.max, 6);
  });

  test('scene header becomes a scene entry; chaos note attaches', () {
    const md = '## Session log\n\n### S1 *the ambush*\n(note: Chaos 5)\n';
    final imp = parseLonelog(md, importedAt: _t);
    final scene = imp.entries.single;
    expect(scene.kind, JournalKind.scene);
    expect(scene.title, 'the ambush');
    expect(scene.chaosFactor, 5);
  });

  test('a blank-separated group becomes one text entry (joined body)', () {
    const md = '## Session log\n\n'
        'd: Fate Check -> Yes\n=> The gate opens.\n\n'
        'A quiet moment.\n';
    final imp = parseLonelog(md, importedAt: _t);
    expect(imp.entries.length, 2);
    // Newest-first: 'A quiet moment.' is the last group -> first entry.
    expect(imp.entries[0].body, 'A quiet moment.');
    expect(imp.entries[0].kind, JournalKind.text);
    expect(imp.entries[1].body, 'd: Fate Check -> Yes\n=> The gate opens.');
  });

  test('empty-journal placeholder yields no entries; garbage tolerated', () {
    final a = parseLonelog('## Session log\n\n(note: empty journal)\n',
        importedAt: _t);
    expect(a.entries, isEmpty);
    // Non-Lonelog junk in the body does not throw.
    final b = parseLonelog('## Session log\n\n~~~ random !!!\n', importedAt: _t);
    expect(b.entries.single.body, '~~~ random !!!');
  });

  test('round-trips a campaignToLonelog export', () {
    final exported = campaignToLonelog(
      campaignName: 'Round Trip',
      threads: [
        const Thread(id: 'a', title: 'Open quest', open: true),
        const Thread(id: 'b', title: 'Done quest', open: false),
      ],
      characters: [const Character(id: 'c', name: 'Bob', tags: ['friendly'])],
      tracks: [const Track(id: 'd', name: 'Doom', filled: 2, max: 8)],
      entriesNewestFirst: [
        JournalEntry(
            id: '3',
            timestamp: _t,
            title: 'note',
            body: 'A quiet moment.',
            kind: JournalKind.text),
        JournalEntry(
            id: '2',
            timestamp: _t,
            title: 'Fate',
            body: 'Yes',
            kind: JournalKind.result),
        JournalEntry(
            id: '1',
            timestamp: _t,
            title: 'The Start',
            body: '',
            kind: JournalKind.scene),
      ],
      threadTitles: const {'a': 'Open quest', 'b': 'Done quest'},
      exportedAt: _t,
    );
    final imp = parseLonelog(exported, importedAt: _t);
    expect(imp.campaignName, 'Round Trip');
    expect(imp.threads.length, 2);
    expect(imp.threads.firstWhere((t) => t.title == 'Open quest').open, isTrue);
    expect(
        imp.threads.firstWhere((t) => t.title == 'Done quest').open, isFalse);
    expect(imp.tracks.single.name, 'Doom');
    expect(imp.tracks.single.filled, 2);
    expect(imp.characters.single.name, 'Bob');
    expect(imp.entries.length, 3); // scene + result-as-text + text
    final scenes =
        imp.entries.where((e) => e.kind == JournalKind.scene).toList();
    expect(scenes.single.title, 'The Start');
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `flutter test test/lonelog_import_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:juice_oracle/engine/lonelog_import.dart'`.

- [ ] **Step 3: Write `lib/engine/lonelog_import.dart`**

```dart
/// Tolerant, lossy parser: a Lonelog `.md` document into juice campaign data.
/// Pure — no Flutter, no clock (timestamps derive from [importedAt]). The
/// inverse of lonelog_export.dart. Unrecognized lines are ignored.
library;

import 'models.dart';

/// Parsed campaign data ready to write into a new session's stores.
class LonelogImport {
  const LonelogImport({
    required this.campaignName,
    required this.genre,
    required this.tone,
    required this.threads,
    required this.characters,
    required this.tracks,
    required this.entries,
  });
  final String campaignName;
  final String genre;
  final String tone;
  final List<Thread> threads;
  final List<Character> characters;
  final List<Track> tracks;
  final List<JournalEntry> entries; // newest-first (juice convention)
}

final _sceneRe = RegExp(r'^###\s+S\d+\s+(.*?)\s*$');
final _chaosRe = RegExp(r'^\(note:\s*Chaos\s+(\d+)\)$');
final _threadRe = RegExp(r'^\[Thread:(.*)\|(Open|Closed)\]$');
final _trackRe = RegExp(r'^\[Track:(.*)\s(\d+)/(\d+)\]$');
final _npcRe = RegExp(r'^\[N:([^|\]]*)(?:\|(.*))?\]$');

LonelogImport parseLonelog(String md, {required DateTime importedAt}) {
  final lines = md.split('\n');
  var i = 0;

  var campaignName = 'Imported Lonelog';
  var genre = '';
  var tone = '';
  if (i < lines.length && lines[i].trim() == '---') {
    i++;
    while (i < lines.length && lines[i].trim() != '---') {
      final line = lines[i];
      final colon = line.indexOf(':');
      if (colon > 0) {
        final key = line.substring(0, colon).trim();
        final val = _unquote(line.substring(colon + 1).trim());
        switch (key) {
          case 'title':
            if (val.isNotEmpty) campaignName = val;
          case 'genre':
            genre = val;
          case 'tone':
            tone = val;
        }
      }
      i++;
    }
    if (i < lines.length) i++; // skip the closing ---
  }

  final threads = <Thread>[];
  final characters = <Character>[];
  final tracks = <Track>[];
  final entries = <JournalEntry>[];
  final beat = <String>[];
  var inState = false;

  void flushBeat() {
    final body = beat.join('\n').trim();
    beat.clear();
    if (body.isEmpty || body == '(note: empty journal)') return;
    entries.add(JournalEntry(
      id: 'll-entry-${entries.length}',
      timestamp: importedAt.add(Duration(seconds: entries.length)),
      title: '',
      body: body,
      kind: JournalKind.text,
    ));
  }

  while (i < lines.length) {
    final line = lines[i].trim();

    if (line == '[STATE]') {
      inState = true;
      i++;
      continue;
    }
    if (line == '[/STATE]') {
      inState = false;
      i++;
      continue;
    }
    if (inState) {
      _parseTag(line, threads, characters, tracks);
      i++;
      continue;
    }
    if (line == '## Session log' || line.isEmpty) {
      flushBeat();
      i++;
      continue;
    }

    final sm = _sceneRe.firstMatch(line);
    if (sm != null) {
      flushBeat();
      var title = sm.group(1)!.trim();
      if (title.length >= 2 && title.startsWith('*') && title.endsWith('*')) {
        title = title.substring(1, title.length - 1).trim();
      }
      int? chaos;
      if (i + 1 < lines.length) {
        final cm = _chaosRe.firstMatch(lines[i + 1].trim());
        if (cm != null) {
          chaos = int.parse(cm.group(1)!);
          i++; // consume the chaos note line
        }
      }
      entries.add(JournalEntry(
        id: 'll-entry-${entries.length}',
        timestamp: importedAt.add(Duration(seconds: entries.length)),
        title: title,
        body: '',
        kind: JournalKind.scene,
        chaosFactor: chaos,
      ));
      i++;
      continue;
    }

    beat.add(lines[i]); // accumulate the raw line (preserve indentation)
    i++;
  }
  flushBeat();

  return LonelogImport(
    campaignName: campaignName,
    genre: genre,
    tone: tone,
    threads: threads,
    characters: characters,
    tracks: tracks,
    entries: entries.reversed.toList(), // newest-first
  );
}

void _parseTag(String line, List<Thread> threads, List<Character> characters,
    List<Track> tracks) {
  final th = _threadRe.firstMatch(line);
  if (th != null) {
    threads.add(Thread(
      id: 'll-thread-${threads.length}',
      title: th.group(1)!.trim(),
      open: th.group(2) == 'Open',
    ));
    return;
  }
  final tr = _trackRe.firstMatch(line);
  if (tr != null) {
    tracks.add(Track(
      id: 'll-track-${tracks.length}',
      name: tr.group(1)!.trim(),
      filled: int.parse(tr.group(2)!),
      max: int.parse(tr.group(3)!),
    ));
    return;
  }
  final n = _npcRe.firstMatch(line);
  if (n != null) {
    final tags = (n.group(2) ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    characters.add(Character(
      id: 'll-char-${characters.length}',
      name: n.group(1)!.trim(),
      tags: tags,
    ));
  }
}

/// Reverse the exporter's `_yaml` quoting: strip one pair of surrounding `"`
/// and unescape `\"` / `\\`.
String _unquote(String s) {
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    return s
        .substring(1, s.length - 1)
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', r'\');
  }
  return s;
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `flutter test test/lonelog_import_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/lonelog_import.dart test/lonelog_import_test.dart
git commit -m "feat(lonelog): tolerant Lonelog .md -> campaign parser"
```

---

### Task 2: Wiring — `SessionsNotifier.importLonelog`

**Files:**
- Modify: `lib/state/providers.dart` (import + new method on `SessionsNotifier`, after `importCampaign`)
- Modify: `test/sessions_test.dart` (smoke + FormatException tests)

- [ ] **Step 1: Write the failing test**

Append inside the `'Sessions provider'` group in `test/sessions_test.dart` (after the `exportActiveAsLonelog` test, before the group's closing `});`):

```dart
    test('importLonelog creates a new session from the header + STATE', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      const md = '---\ntitle: "Imported Game"\n---\n\n'
          '[STATE]\n[Thread:Find the heir|Open]\n[/STATE]\n\n'
          '## Session log\n\n### S1 *opening*\n';

      await container.read(sessionsProvider.notifier).importLonelog(md);
      final s = await container.read(sessionsProvider.future);
      expect(s.activeMeta.name, 'Imported Game');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('juice.threads.v1.${s.active}'),
          contains('Find the heir'));
    });

    test('importLonelog rejects a non-Lonelog file', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      expect(
        () => container
            .read(sessionsProvider.notifier)
            .importLonelog('just some prose, no markers'),
        throwsA(isA<FormatException>()),
      );
    });
```

- [ ] **Step 2: Run it and verify it fails**

Run: `flutter test test/sessions_test.dart`
Expected: FAIL — `The method 'importLonelog' isn't defined for the type 'SessionsNotifier'`.

- [ ] **Step 3: Add the import and method**

In `lib/state/providers.dart`, add the import beside the other engine imports (after `import '../engine/lonelog_export.dart';`):

```dart
import '../engine/lonelog_import.dart';
```

In `SessionsNotifier`, immediately after the `importCampaign` method (after its closing `}`), add:

```dart

  /// Import a Lonelog `.md` document as a NEW session and switch to it.
  /// Throws [FormatException] when the content is not Lonelog-shaped.
  Future<void> importLonelog(String content) async {
    if (!content.trimLeft().startsWith('---') &&
        !content.contains('[STATE]') &&
        !content.contains('## Session log')) {
      throw const FormatException('Not a Lonelog file');
    }
    final doc = parseLonelog(content, importedAt: DateTime.now());
    final s = state.valueOrNull ?? await future;
    final meta = SessionMeta(id: _newId(), name: doc.campaignName);
    final prefs = await SharedPreferences.getInstance();
    final rawByKey = <String, String>{
      'juice.journal.v2':
          jsonEncode(doc.entries.map((e) => e.toJson()).toList()),
      'juice.threads.v1':
          jsonEncode(doc.threads.map((t) => t.toJson()).toList()),
      'juice.characters.v1':
          jsonEncode(doc.characters.map((c) => c.toJson()).toList()),
      'juice.tracks.v1': jsonEncode(doc.tracks.map((t) => t.toJson()).toList()),
      'juice.settings.v1':
          jsonEncode(CampaignSettings(genre: doc.genre, tone: doc.tone).toJson()),
    };
    for (final e in rawByKey.entries) {
      await prefs.setString('${e.key}.${meta.id}', e.value);
    }
    await _save(
        SessionsState(active: meta.id, sessions: [...s.sessions, meta]));
  }
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `flutter test test/sessions_test.dart`
Expected: PASS (existing tests + the two new ones).

- [ ] **Step 5: Verify analysis is clean and commit**

Run: `dart analyze lib/state/providers.dart`
Expected: No issues found.

```bash
git add lib/state/providers.dart test/sessions_test.dart
git commit -m "feat(lonelog): SessionsNotifier.importLonelog (new session)"
```

---

### Task 3: Campaigns-menu action

**Files:**
- Modify: `lib/shared/home_shell.dart` (menu tile in `_showSessions` + `_importLonelog` handler beside `_importCampaign`)
- Modify: `test/lonelog_campaign_ui_test.dart` (menu-tile presence test)

- [ ] **Step 1: Write the failing test**

Append a `testWidgets` inside `void main()` in `test/lonelog_campaign_ui_test.dart` (after the "Export as Lonelog" one):

```dart
  testWidgets('Campaigns dialog offers Import Lonelog', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        verdantDataProvider.overrideWith((ref) async => _verdant),
        emulatorDataProvider.overrideWith((ref) async => _emu),
        lonelogDataProvider.overrideWith((ref) async => _lonelog),
      ],
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Campaigns'));
    await t.pumpAndSettle();
    expect(find.text('Import Lonelog (.md)'), findsOneWidget);
  });
```

- [ ] **Step 2: Run it and verify it fails**

Run: `flutter test test/lonelog_campaign_ui_test.dart`
Expected: FAIL — `Import Lonelog (.md)` not found.

- [ ] **Step 3: Add the menu tile**

In `lib/shared/home_shell.dart`, in `_showSessions`, immediately after the existing "Import campaign" `ListTile` (the one with `Icons.file_download_outlined` / `onTap: () => _importCampaign(dialogContext)`), add:

```dart
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Import Lonelog (.md)'),
                onTap: () => _importLonelog(dialogContext),
              ),
```

- [ ] **Step 4: Add the `_importLonelog` handler**

In `lib/shared/home_shell.dart`, immediately after the `_importCampaign` method (after its closing `}`), add:

```dart
  Future<void> _importLonelog(BuildContext dialogContext) async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: 'Import Lonelog',
        type: FileType.custom,
        allowedExtensions: ['md'],
        withData: true,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not access files: ${e.message}')),
      );
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      return;
    }
    final bytes = (result == null || result.files.isEmpty)
        ? null
        : result.files.first.bytes;
    if (bytes == null) return; // user cancelled
    try {
      await ref
          .read(sessionsProvider.notifier)
          .importLonelog(utf8.decode(bytes));
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    } on FormatException catch (e) {
      if (!mounted) return;
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        Navigator.of(dialogContext).pop();
      }
    }
  }
```

(`FilePicker`, `FilePickerResult`, `FileType`, `utf8`, `PlatformException` are already imported in `home_shell.dart` for `_importCampaign`.)

- [ ] **Step 5: Run the test and verify it passes**

Run: `flutter test test/lonelog_campaign_ui_test.dart`
Expected: PASS (all three tests).

- [ ] **Step 6: Verify analysis is clean and commit**

Run: `dart analyze lib/shared/home_shell.dart`
Expected: No issues found.

```bash
git add lib/shared/home_shell.dart test/lonelog_campaign_ui_test.dart
git commit -m "feat(lonelog): Import Lonelog (.md) campaign-menu action"
```

---

### Task 4: Full verification

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: PASS. (The previously pre-existing `help_data_test.dart` failure is resolved by an uncommitted working-tree fix; if that fix is absent in this checkout, that one test fails for reasons unrelated to this work.)

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`
Expected: No issues found.

---

## Self-review

**Spec coverage:**
- Pure parser `parseLonelog` → `LonelogImport` → Task 1. ✓
- YAML header (title/genre/tone, quoted + fallback) → Task 1. ✓
- `[STATE]` → threads/characters/tracks → Task 1. ✓
- Scene + chaos; grouped beats → text entries; empty-journal placeholder; tolerance → Task 1. ✓
- Round-trip of `campaignToLonelog` → Task 1. ✓
- Wiring `importLonelog` (new session, rawByKey, mirrors `importCampaign`) + `FormatException` → Task 2. ✓
- Campaigns-menu "Import Lonelog (.md)" → Task 3. ✓
- Newest-first ordering + synthetic IDs/timestamps → Task 1 impl. ✓
- Excluded: roll-payload reconstruction, merge, crawl/encounter/map/rumors — no task builds them. ✓

**Placeholder scan:** none — every code/test step has complete content.

**Type consistency:** `parseLonelog(String, {required DateTime importedAt}) -> LonelogImport` is identical in Task 1 impl, Task 1 tests, and Task 2 caller. `LonelogImport` fields (`campaignName`, `genre`, `tone`, `threads`, `characters`, `tracks`, `entries`) match between impl and the Task 2 `rawByKey` builder. `Thread(id,title,open)`, `Character(id,name,tags)`, `Track(id,name,filled,max)`, `JournalEntry(id,timestamp,title,body,kind,chaosFactor)`, `JournalKind.{scene,text,result}`, `CampaignSettings(genre,tone)` match the real models. Menu label `'Import Lonelog (.md)'` matches the Task 3 test. `importLonelog` returns `Future<void>` and throws `FormatException`, awaited/caught in Tasks 2/3.
