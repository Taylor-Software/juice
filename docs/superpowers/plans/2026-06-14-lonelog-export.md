# Lonelog Export (P2a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export the active campaign as a faithful, parseable Lonelog `.md` (YAML front matter + `[STATE]` block + journal beats) from the Campaigns menu.

**Architecture:** A pure engine `lib/engine/lonelog_export.dart` (no Flutter, no clock, mirrors `journal_export.dart`) renders the document; `SessionsNotifier.exportActiveAsLonelog()` gathers the active session's journal/threads/characters/tracks/settings via Riverpod and calls it; the Campaigns dialog adds an "Export as Lonelog (.md)" tile that saves it via the file picker.

**Tech Stack:** Dart/Flutter, flutter_riverpod, shared_preferences, file_picker, package:flutter_test.

**Scope guard:** export only. Lonelog `.md` import is P2b. crawl/encounter/map/rumors are excluded.

---

## File structure

**New:** `lib/engine/lonelog_export.dart` (pure renderer), `test/lonelog_export_test.dart`.
**Edit:** `lib/state/providers.dart` (`SessionsNotifier.exportActiveAsLonelog` + import), `lib/shared/home_shell.dart` (menu tile + `_exportLonelog` handler).

---

### Task 1: Pure export engine

**Files:**
- Create: `lib/engine/lonelog_export.dart`
- Create: `test/lonelog_export_test.dart`

- [ ] **Step 1: Write the failing test**

`test/lonelog_export_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/lonelog_export.dart';
import 'package:juice_oracle/engine/models.dart';

String _export({
  String name = 'My Campaign',
  String genre = '',
  String tone = '',
  List<Thread> threads = const [],
  List<Character> characters = const [],
  List<Track> tracks = const [],
  List<JournalEntry> entries = const [],
}) =>
    campaignToLonelog(
      campaignName: name,
      genre: genre,
      tone: tone,
      threads: threads,
      characters: characters,
      tracks: tracks,
      entriesNewestFirst: entries,
      threadTitles: {for (final t in threads) t.id: t.title},
      exportedAt: DateTime(2026, 6, 14),
    );

JournalEntry _entry(JournalKind kind, String title, String body,
        {String? threadId, List<String> tags = const [], int? chaos}) =>
    JournalEntry(
      id: title,
      timestamp: DateTime(2026, 6, 14),
      title: title,
      body: body,
      kind: kind,
      threadId: threadId,
      tags: tags,
      chaosFactor: chaos,
    );

void main() {
  test('YAML front matter has title, tools, date; genre/tone only when set', () {
    final out = _export(name: 'West Marches', genre: 'sword & sorcery');
    expect(out, startsWith('---\n'));
    expect(out, contains('title: West Marches'));
    expect(out, contains('genre: sword & sorcery'));
    expect(out, isNot(contains('tone:')));
    expect(out, contains('tools: juice-oracle'));
    expect(out, contains('exported: 2026-06-14'));
  });

  test('STATE block lists threads, characters, tracks as tags', () {
    final out = _export(
      threads: [
        const Thread(id: 't1', title: 'Slay the wyrm', open: true),
        const Thread(id: 't2', title: 'Find the heir', open: false),
      ],
      characters: [
        const Character(id: 'c1', name: 'Vance', tags: ['gruff', 'ally']),
        const Character(id: 'c2', name: 'Mute'),
      ],
      tracks: [const Track(id: 'k1', name: 'Ritual', filled: 3, max: 6)],
    );
    expect(out, contains('[STATE]'));
    expect(out, contains('[Thread:Slay the wyrm|Open]'));
    expect(out, contains('[Thread:Find the heir|Closed]'));
    expect(out, contains('[N:Vance|gruff, ally]'));
    expect(out, contains('[N:Mute]'));
    expect(out, contains('[Track:Ritual 3/6]'));
    expect(out, contains('[/STATE]'));
  });

  test('scene numbering increments and renders chaos note', () {
    final out = _export(entries: [
      _entry(JournalKind.scene, 'Second', '', chaos: 5),
      _entry(JournalKind.scene, 'First', ''),
    ]); // newest-first input -> oldest-first output
    final firstIdx = out.indexOf('### S1 *First*');
    final secondIdx = out.indexOf('### S2 *Second*');
    expect(firstIdx, isNonNegative);
    expect(secondIdx, greaterThan(firstIdx));
    expect(out, contains('(note: Chaos 5)'));
  });

  test('result beat renders as d: title -> first body line', () {
    final out = _export(entries: [
      _entry(JournalKind.result, 'Fate Check — Likely', 'Yes, but...\nextra'),
    ]);
    expect(out, contains('d: Fate Check — Likely -> Yes, but...'));
    expect(out, isNot(contains('extra')));
  });

  test('result with empty body renders bare d: title', () {
    final out = _export(entries: [_entry(JournalKind.result, 'Rolled d20=17', '')]);
    expect(out, contains('d: Rolled d20=17'));
    expect(out, isNot(contains('d: Rolled d20=17 ->')));
  });

  test('text beat renders prose; threadId and tags render as trailers', () {
    final out = _export(
      threads: [const Thread(id: 't1', title: 'Rescue Jonah', open: true)],
      entries: [
        _entry(JournalKind.text, 'note', 'The door creaks open.',
            threadId: 't1', tags: ['quiet', 'night']),
      ],
    );
    expect(out, contains('The door creaks open.'));
    expect(out, contains('=> [#Thread:Rescue Jonah]'));
    expect(out, contains('(note: #quiet #night)'));
  });

  test('empty journal yields a placeholder under the log heading', () {
    final out = _export();
    expect(out, contains('## Session log'));
    expect(out, contains('(note: empty journal)'));
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `flutter test test/lonelog_export_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:juice_oracle/engine/lonelog_export.dart'`.

- [ ] **Step 3: Write `lib/engine/lonelog_export.dart`**

```dart
/// Pure renderer that turns a campaign into a faithful Lonelog `.md` document
/// (YAML front matter + a juice-defined [STATE] block + journal beats). No
/// Flutter, no clock — `exportedAt` is passed in. Mirrors journal_export.dart.
/// Export only; Lonelog import is P2b.
library;

import 'mention_parser.dart';
import 'models.dart';

String campaignToLonelog({
  required String campaignName,
  String genre = '',
  String tone = '',
  required List<Thread> threads,
  required List<Character> characters,
  required List<Track> tracks,
  required List<JournalEntry> entriesNewestFirst,
  required Map<String, String> threadTitles,
  required DateTime exportedAt,
}) {
  final buf = StringBuffer()
    ..writeln('---')
    ..writeln('title: $campaignName');
  if (genre.isNotEmpty) buf.writeln('genre: $genre');
  if (tone.isNotEmpty) buf.writeln('tone: $tone');
  buf
    ..writeln('tools: juice-oracle')
    ..writeln('exported: ${_date(exportedAt)}')
    ..writeln('---')
    ..writeln()
    ..writeln('[STATE]');
  for (final t in threads) {
    buf.writeln('[Thread:${t.title}|${t.open ? 'Open' : 'Closed'}]');
  }
  for (final c in characters) {
    final tags = c.tags.where((s) => s.trim().isNotEmpty).join(', ');
    buf.writeln(tags.isEmpty ? '[N:${c.name}]' : '[N:${c.name}|$tags]');
  }
  for (final k in tracks) {
    buf.writeln('[Track:${k.name} ${k.filled}/${k.max}]');
  }
  buf
    ..writeln('[/STATE]')
    ..writeln()
    ..writeln('## Session log');

  if (entriesNewestFirst.isEmpty) {
    buf
      ..writeln()
      ..writeln('(note: empty journal)');
    return buf.toString();
  }

  var scene = 0;
  for (final e in entriesNewestFirst.reversed) {
    final lines = _beatLines(e, threadTitles, () => ++scene);
    if (lines.isEmpty) continue;
    buf.writeln();
    for (final line in lines) {
      buf.writeln(line);
    }
  }
  return buf.toString();
}

List<String> _beatLines(
  JournalEntry e,
  Map<String, String> threadTitles,
  int Function() nextScene,
) {
  final lines = <String>[];
  final body = mentionsToPlain(e.body);
  switch (e.kind) {
    case JournalKind.scene:
      lines.add('### S${nextScene()} *${e.title}*');
      if (e.chaosFactor != null) lines.add('(note: Chaos ${e.chaosFactor})');
    case JournalKind.result:
      final first = body.isEmpty ? '' : body.split('\n').first;
      lines.add(first.isEmpty ? 'd: ${e.title}' : 'd: ${e.title} -> $first');
    case JournalKind.text:
      if (body.isNotEmpty) lines.add(body);
  }
  if (e.threadId != null) {
    final title = threadTitles[e.threadId] ?? '(closed thread)';
    lines.add('=> [#Thread:$title]');
  }
  if (e.tags.isNotEmpty) {
    lines.add('(note: ${e.tags.map((t) => '#$t').join(' ')})');
  }
  return lines;
}

String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `flutter test test/lonelog_export_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/lonelog_export.dart test/lonelog_export_test.dart
git commit -m "feat(lonelog): pure campaign -> Lonelog .md export engine"
```

---

### Task 2: Wiring — `SessionsNotifier.exportActiveAsLonelog`

**Files:**
- Modify: `lib/state/providers.dart` (import + new method on `SessionsNotifier`, after `exportActive`, ~line 743)
- Modify: `test/sessions_test.dart` (smoke test)

- [ ] **Step 1: Write the failing test**

Append inside the `'Sessions provider'` group in `test/sessions_test.dart` (after the `editSystems` test, before the group's closing `});`):

```dart
    test('exportActiveAsLonelog renders title + a thread tag', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"Lonelog Camp"}]}',
        'juice.threads.v1.default':
            '[{"id":"t1","title":"Slay the wyrm","note":"","open":true}]',
        'juice.journal.v2.default':
            '[{"id":"n","timestamp":"2026-06-11T10:00:00.000","title":"Note","body":"hi","kind":"text"}]',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);

      final md =
          await container.read(sessionsProvider.notifier).exportActiveAsLonelog();
      expect(md, contains('title: Lonelog Camp'));
      expect(md, contains('[Thread:Slay the wyrm|Open]'));
      expect(md, contains('## Session log'));
    });
```

- [ ] **Step 2: Run it and verify it fails**

Run: `flutter test test/sessions_test.dart`
Expected: FAIL — `The method 'exportActiveAsLonelog' isn't defined for the type 'SessionsNotifier'`.

- [ ] **Step 3: Add the import and method**

In `lib/state/providers.dart`, add the import beside the other engine imports (after `import '../engine/journal_export.dart';` if present, else alphabetically near the top engine imports):

```dart
import '../engine/lonelog_export.dart';
```

In `SessionsNotifier`, immediately after the `exportActive()` method (after its closing `}` near line 743), add:

```dart

  /// Serialize the active session to a Lonelog `.md` document.
  Future<String> exportActiveAsLonelog() async {
    final s = state.valueOrNull ?? await future;
    final journal = await ref.read(journalProvider.future);
    final threads = await ref.read(threadsProvider.future);
    final characters = await ref.read(charactersProvider.future);
    final tracks = await ref.read(tracksProvider.future);
    final settings = await ref.read(settingsProvider.future);
    return campaignToLonelog(
      campaignName: s.activeMeta.name,
      genre: settings.genre,
      tone: settings.tone,
      threads: threads,
      characters: characters,
      tracks: tracks,
      entriesNewestFirst: journal,
      threadTitles: {for (final t in threads) t.id: t.title},
      exportedAt: DateTime.now(),
    );
  }
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `flutter test test/sessions_test.dart`
Expected: PASS (existing tests + the new smoke test).

- [ ] **Step 5: Verify analysis is clean and commit**

Run: `dart analyze lib/state/providers.dart`
Expected: No issues found.

```bash
git add lib/state/providers.dart test/sessions_test.dart
git commit -m "feat(lonelog): SessionsNotifier.exportActiveAsLonelog"
```

---

### Task 3: Campaigns-menu action

**Files:**
- Modify: `lib/shared/home_shell.dart` (menu tile in `_showSessions` + `_exportLonelog` handler beside `_exportCampaign`)
- Modify: `test/lonelog_campaign_ui_test.dart` (menu-tile presence test)

- [ ] **Step 1: Write the failing test**

Append a second `testWidgets` inside `void main()` in `test/lonelog_campaign_ui_test.dart` (after the existing one):

```dart
  testWidgets('Campaigns dialog offers Export as Lonelog', (t) async {
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
    expect(find.text('Export as Lonelog (.md)'), findsOneWidget);
  });
```

- [ ] **Step 2: Run it and verify it fails**

Run: `flutter test test/lonelog_campaign_ui_test.dart`
Expected: FAIL — `Export as Lonelog (.md)` not found.

- [ ] **Step 3: Add the menu tile**

In `lib/shared/home_shell.dart`, in `_showSessions`, immediately after the existing "Export campaign" `ListTile` (the one with `Icons.file_upload_outlined` / `onTap: () => _exportCampaign(dialogContext)`), add:

```dart
              ListTile(
                leading: const Icon(Icons.notes_outlined),
                title: const Text('Export as Lonelog (.md)'),
                onTap: () => _exportLonelog(dialogContext),
              ),
```

- [ ] **Step 4: Add the `_exportLonelog` handler**

In `lib/shared/home_shell.dart`, immediately after the `_exportCampaign` method (after its closing `}`), add:

```dart
  Future<void> _exportLonelog(BuildContext dialogContext) async {
    final content =
        await ref.read(sessionsProvider.notifier).exportActiveAsLonelog();
    final name =
        ref.read(sessionsProvider).valueOrNull?.activeMeta.name ?? 'campaign';
    final fileName = '${slugify(name)}.lonelog.md';
    try {
      await FilePicker.saveFile(
        dialogTitle: 'Export as Lonelog',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['md'],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not access files: ${e.message}')),
      );
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    }
  }
```

(`slugify`, `FilePicker`, `FileType`, `Uint8List`, `utf8`, `PlatformException` are already imported in `home_shell.dart` for `_exportCampaign`.)

- [ ] **Step 5: Run the test and verify it passes**

Run: `flutter test test/lonelog_campaign_ui_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Verify analysis is clean and commit**

Run: `dart analyze lib/shared/home_shell.dart`
Expected: No issues found.

```bash
git add lib/shared/home_shell.dart test/lonelog_campaign_ui_test.dart
git commit -m "feat(lonelog): Export as Lonelog (.md) campaign-menu action"
```

---

### Task 4: Full verification

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: PASS except the **pre-existing** `help_data_test.dart` failure (`'Move around'` vs `'Open a tool'`), which is unrelated to this work and fails on `main` too.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`
Expected: No issues found.

---

## Self-review

**Spec coverage:**
- Pure engine `campaignToLonelog` → Task 1. ✓
- YAML header (title/genre/tone/tools/exported) → Task 1 test + impl. ✓
- `[STATE]` block (threads/characters/tracks) → Task 1. ✓
- Beat mapping (scene numbering + chaos, result→`d:`, text prose, threadId trailer, tags trailer, empty placeholder) → Task 1. ✓
- Wiring `exportActiveAsLonelog` reading active-session providers → Task 2. ✓
- Campaigns-menu action saving `<slug>.lonelog.md` → Task 3. ✓
- Excluded: import (P2b), crawl/encounter/map/rumors — no task builds them. ✓

**Placeholder scan:** none — every code/test step has complete content.

**Type consistency:** `campaignToLonelog` signature (named params `campaignName`, `genre`, `tone`, `threads`, `characters`, `tracks`, `entriesNewestFirst`, `threadTitles`, `exportedAt`) is identical in Task 1 impl, Task 1 test helper, and Task 2 caller. `exportActiveAsLonelog` returns `Future<String>` in Task 2 and is awaited in Tasks 2/3. `Thread.open`, `Character.tags`/`name`, `Track.name`/`filled`/`max`, `JournalEntry.kind`/`title`/`body`/`threadId`/`tags`/`chaosFactor`, `JournalKind.{scene,result,text}` match the real models. `CampaignSettings.genre`/`tone` match. Menu tile label `'Export as Lonelog (.md)'` matches the Task 3 test.
