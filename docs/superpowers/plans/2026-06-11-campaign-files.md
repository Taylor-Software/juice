# Campaign File Save/Open (BYO Cloud) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export the active campaign to a JSON file and import one back, via the system document picker — users get cloud sync by saving into a folder their own cloud client syncs; the app stays offline with no server.

**Architecture:** A pure serialization module (`campaign_io.dart`) defines the file format (schemaVersion 1, app marker, session name, the four data payloads). `SessionsNotifier` gains `exportActive()` / `importCampaign()` — import always creates a NEW session (no overwrite semantics, no conflict UX). The Campaigns dialog gains Export/Import tiles wired to `file_picker` (v11: `saveFile` with bytes works on Android/iOS/web/desktop; `pickFiles(withData: true)` for reading).

**Tech Stack:** Dart/Flutter, `file_picker: ^11.0.2` (the one new dependency — justified by the roadmap's BYO-cloud item), existing riverpod + shared_preferences.

---

**File format (schemaVersion 1):**

```json
{
  "app": "juice-oracle",
  "schemaVersion": 1,
  "savedAt": "2026-06-11T12:00:00.000Z",
  "name": "Campaign 1",
  "data": {
    "juice.log.v1": [ ...log entries... ],
    "juice.threads.v1": [ ...threads... ],
    "juice.characters.v1": [ ...characters... ],
    "juice.crawl.v1": { ...crawl state... }
  }
}
```

`data` values are the decoded JSON the stores already persist (not double-encoded strings). Missing keys are allowed (empty stores aren't exported). Import rejects: unparseable JSON, missing/wrong `app` marker, missing `schemaVersion`, `schemaVersion` greater than 1, `data` not an object.

### Task 1: Serialization module

**Files:**
- Create: `lib/state/campaign_io.dart`
- Test: `test/campaign_io_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/campaign_io_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:juice_oracle/state/campaign_io.dart';

void main() {
  group('Campaign file encode/parse', () {
    test('round-trip preserves name and per-key payloads', () {
      final encoded = encodeCampaign(
        name: 'West Marches',
        savedAt: DateTime.utc(2026, 6, 11),
        rawByKey: {
          'juice.threads.v1': '[{"id":"t1","title":"Vow","note":"","open":true}]',
          'juice.crawl.v1': '{"envRow":7,"lost":true,"dialogRow":2,"dialogCol":2}',
        },
      );
      final parsed = parseCampaign(encoded);
      expect(parsed.name, 'West Marches');
      expect(parsed.rawByKey.keys,
          unorderedEquals(['juice.threads.v1', 'juice.crawl.v1']));
      expect(parsed.rawByKey['juice.threads.v1'], contains('"title":"Vow"'));
      expect(parsed.rawByKey['juice.crawl.v1'], contains('"envRow":7'));
    });

    test('rejects non-JSON, wrong app marker, and newer schema versions', () {
      expect(() => parseCampaign('not json'), throwsFormatException);
      expect(
        () => parseCampaign(
            '{"app":"other","schemaVersion":1,"name":"x","data":{}}'),
        throwsFormatException,
      );
      expect(
        () => parseCampaign(
            '{"app":"juice-oracle","schemaVersion":2,"name":"x","data":{}}'),
        throwsFormatException,
      );
      expect(
        () => parseCampaign(
            '{"app":"juice-oracle","schemaVersion":1,"name":"x","data":[]}'),
        throwsFormatException,
      );
    });

    test('unknown data keys are ignored on parse', () {
      final parsed = parseCampaign(
          '{"app":"juice-oracle","schemaVersion":1,"name":"x",'
          '"data":{"juice.threads.v1":[],"someday.v9":{}}}');
      expect(parsed.rawByKey.keys, ['juice.threads.v1']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/campaign_io_test.dart`
Expected: FAIL — `campaign_io.dart` doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/state/campaign_io.dart`:

```dart
import 'dart:convert';

import 'providers.dart' show sessionScopedKeys;

/// Campaign file format version this build writes and the max it reads.
const campaignSchemaVersion = 1;

const _appMarker = 'juice-oracle';

/// Parsed campaign file: session name + raw JSON string per base key,
/// ready to write into session-scoped SharedPreferences entries.
class CampaignImport {
  const CampaignImport({required this.name, required this.rawByKey});
  final String name;
  final Map<String, String> rawByKey;
}

/// Encode a campaign to the .juice.json file content.
/// [rawByKey] holds the stores' persisted JSON strings by base key;
/// null/absent stores are omitted.
String encodeCampaign({
  required String name,
  required DateTime savedAt,
  required Map<String, String> rawByKey,
}) {
  return const JsonEncoder.withIndent('  ').convert({
    'app': _appMarker,
    'schemaVersion': campaignSchemaVersion,
    'savedAt': savedAt.toIso8601String(),
    'name': name,
    'data': {
      for (final e in rawByKey.entries) e.key: jsonDecode(e.value),
    },
  });
}

/// Parse and validate a campaign file. Throws [FormatException] with a
/// user-readable message on anything invalid.
CampaignImport parseCampaign(String raw) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw const FormatException('Not a JSON file');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Not a campaign file');
  }
  if (decoded['app'] != _appMarker) {
    throw const FormatException('Not a Juice Oracle campaign file');
  }
  final version = decoded['schemaVersion'];
  if (version is! int || version > campaignSchemaVersion) {
    throw FormatException(
        'Campaign file version $version is newer than this app supports');
  }
  final data = decoded['data'];
  if (data is! Map<String, dynamic>) {
    throw const FormatException('Campaign file has no data section');
  }
  return CampaignImport(
    name: (decoded['name'] as String?)?.trim().isNotEmpty == true
        ? (decoded['name'] as String).trim()
        : 'Imported campaign',
    rawByKey: {
      for (final key in sessionScopedKeys)
        if (data.containsKey(key)) key: jsonEncode(data[key]),
    },
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/campaign_io_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/state/campaign_io.dart test/campaign_io_test.dart
git commit -m "feat: campaign file format encode/parse (schemaVersion 1)"
```

### Task 2: Export/import on the sessions provider

**Files:**
- Modify: `lib/state/providers.dart` (SessionsNotifier; add import for campaign_io)
- Test: `test/campaign_io_test.dart` (append)

- [ ] **Step 1: Write the failing test**

Append to `test/campaign_io_test.dart` (add imports: `package:flutter_riverpod/flutter_riverpod.dart`, `package:shared_preferences/shared_preferences.dart`, `package:juice_oracle/state/providers.dart`; add `TestWidgetsFlutterBinding.ensureInitialized();` first in `main()`):

```dart
  group('Provider export/import', () {
    test('exportActive embeds the active session data', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"Campaign 1"}]}',
        'juice.threads.v1.default':
            '[{"id":"t1","title":"Slay the wyrm","note":"","open":true}]',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      final file =
          await container.read(sessionsProvider.notifier).exportActive();
      expect(file, contains('"app": "juice-oracle"'));
      expect(file, contains('Slay the wyrm'));
      expect(file, contains('"name": "Campaign 1"'));
    });

    test('importCampaign creates a new isolated active session', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);

      final file = encodeCampaign(
        name: 'From File',
        savedAt: DateTime.utc(2026, 6, 11),
        rawByKey: {
          'juice.threads.v1': '[{"id":"x","title":"Imported vow","note":"","open":true}]',
        },
      );
      await container.read(sessionsProvider.notifier).importCampaign(file);

      final s = await container.read(sessionsProvider.future);
      expect(s.sessions.length, 2);
      expect(s.activeMeta.name, 'From File');
      final threads = await container.read(threadsProvider.future);
      expect(threads.single.title, 'Imported vow');

      // original session untouched
      await container.read(sessionsProvider.notifier).switchTo('default');
      expect(await container.read(threadsProvider.future), isEmpty);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/campaign_io_test.dart`
Expected: FAIL — `exportActive`/`importCampaign` not defined.

- [ ] **Step 3: Implement**

In `lib/state/providers.dart`: add `import 'campaign_io.dart';` at the top, then add to `SessionsNotifier`:

```dart
  /// Serialize the active session to the campaign file format.
  Future<String> exportActive() async {
    final s = state.valueOrNull ?? await future;
    final prefs = await SharedPreferences.getInstance();
    final rawByKey = <String, String>{
      for (final base in sessionScopedKeys)
        if (prefs.getString('$base.${s.active}') case final String raw)
          base: raw,
    };
    return encodeCampaign(
      name: s.activeMeta.name,
      savedAt: DateTime.now(),
      rawByKey: rawByKey,
    );
  }

  /// Import a campaign file as a NEW session and switch to it.
  /// Throws [FormatException] on invalid files.
  Future<void> importCampaign(String fileContent) async {
    final parsed = parseCampaign(fileContent);
    final s = state.valueOrNull ?? await future;
    final meta = SessionMeta(id: _newId(), name: parsed.name);
    final prefs = await SharedPreferences.getInstance();
    for (final e in parsed.rawByKey.entries) {
      await prefs.setString('${e.key}.${meta.id}', e.value);
    }
    await _save(
        SessionsState(active: meta.id, sessions: [...s.sessions, meta]));
  }
```

(If the `case final String raw` pattern bothers the analyzer on this SDK, use the classic form: `final raw = prefs.getString('$base.${s.active}'); if (raw != null) rawByKey[base] = raw;` in a loop.)

- [ ] **Step 4: Run the full suite**

Run: `flutter test && flutter analyze`
Expected: all pass (38 + 5 new = 43); 4 pre-existing infos only.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/campaign_io_test.dart
git commit -m "feat: export active campaign / import as new session"
```

### Task 3: file_picker dependency + dialog tiles

**Files:**
- Modify: `pubspec.yaml` (dependencies)
- Modify: `lib/shared/home_shell.dart` (Campaigns dialog + handlers)

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml` under `dependencies:` add (keep alphabetical placement near the others):

```yaml
  file_picker: ^11.0.2
```

Run: `flutter pub get`
Expected: resolves cleanly. If it pins a lower 11.x, fine; if it fails on SDK constraints, report BLOCKED.

- [ ] **Step 2: Wire the dialog**

In `lib/shared/home_shell.dart`:

Add imports at the top:

```dart
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
```

In `_showSessions`'s `SimpleDialog`, after the `New campaign` ListTile, add:

```dart
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('Export campaign'),
                onTap: () => _exportCampaign(dialogContext),
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('Import campaign'),
                onTap: () => _importCampaign(dialogContext),
              ),
```

Add the handlers to `_HomeShellState`:

```dart
  Future<void> _exportCampaign(BuildContext dialogContext) async {
    final content =
        await ref.read(sessionsProvider.notifier).exportActive();
    final name = ref.read(sessionsProvider).valueOrNull?.activeMeta.name ??
        'campaign';
    final fileName =
        '${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}.juice.json';
    await FilePicker.platform.saveFile(
      dialogTitle: 'Export campaign',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: utf8.encode(content),
    );
    if (dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
  }

  Future<void> _importCampaign(BuildContext dialogContext) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import campaign',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return; // user cancelled
    try {
      await ref
          .read(sessionsProvider.notifier)
          .importCampaign(utf8.decode(bytes));
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    } on FormatException catch (e) {
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        Navigator.of(dialogContext).pop();
      }
    }
  }
```

Notes:
- `saveFile` with `bytes` writes the file itself on Android/iOS/web (web = browser download); on desktop v11 also writes the bytes to the chosen path. A null return = user cancelled — nothing to do.
- The snackbar uses the State's `context` (still mounted under the dialog), not `dialogContext`.
- `utf8.encode` returns `Uint8List` on current SDKs — if the analyzer complains about `List<int>` vs `Uint8List`, wrap: `Uint8List.fromList(utf8.encode(content))` and import `dart:typed_data`.

- [ ] **Step 3: Analyze + full tests**

Run: `flutter analyze && flutter test`
Expected: 4 pre-existing infos only; 43 tests pass.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/shared/home_shell.dart
git commit -m "feat: export/import campaign files via system picker"
```

### Task 4: Documentation sync

**Files:**
- Modify: `CLAUDE.md` (stack note — required by conventions on new dependency)
- Modify: `README.md` (feature mention)
- Modify: `ROADMAP.md` is the controller's post-merge bookkeeping; skip here.

- [ ] **Step 1: Update docs**

- CLAUDE.md "Project notes" stack bullet: the lean-stack line currently reads "`flutter_riverpod` + `shared_preferences` only" — amend to "`flutter_riverpod` + `shared_preferences` + `file_picker` (campaign file export/import) only".
- README: in the feature/success-criteria area where sessions were mentioned, add a sentence or extend the row: campaigns can be exported to / imported from JSON files via the system picker (save into any cloud-synced folder for BYO sync). Read the file; minimal coherent edit.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: campaign file export/import (BYO cloud)"
```

## Self-review notes

- Roadmap acceptance ("save/open as JSON files via system document picker, BYO cloud") — Tasks 1–3. `schemaVersion` + `savedAt` per the documented cloud stance; "last-write-wins conflict warning" from the stance is moot because import never overwrites — it always creates a new session.
- Type consistency: `encodeCampaign(name:, savedAt:, rawByKey:)` used identically in tests and `exportActive`; `CampaignImport.rawByKey` keys are base keys consumed by `importCampaign`'s `'${e.key}.${meta.id}'` writes; `sessionScopedKeys` imported from providers (single source for the four bases).
- Duplicate-name imports are allowed (ids stay unique) — acceptable, visible in the switcher, no extra UX.
- Deliberate cuts: no export-all-campaigns bundle, no auto-save-to-folder (needs persistent URI grants — separate item if ever), no import-merge.
