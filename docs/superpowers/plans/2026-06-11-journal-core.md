# Journal Core (Redesign Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat roll log with a journal data model (text / result / scene entries), migrate existing data, and replace the Tracker's Log tab with a journal screen with a composer.

**Architecture:** Rename `LogEntry`→`JournalEntry` adding a `kind` field whose JSON default is `result` (so old persisted entries parse unchanged); `JournalNotifier` persists under a new session-scoped key `juice.journal.v2` and one-shot-migrates from `juice.log.v1`; campaign files bump to schemaVersion 2 while still importing v1. The journal screen lives in a new file and replaces the Log tab inside the Tracker (the shell swap is phase 2, not this plan).

**Tech Stack:** Flutter + flutter_riverpod + shared_preferences (existing rails only). Spec: `docs/superpowers/specs/2026-06-11-journal-redesign-design.md`.

**Conventions that bind every task:** TDD; `flutter analyze --no-fatal-infos` must report only the 4 pre-existing infos (models.dart dangling doc comment + 3 tracker_screen const lints — though task 4 may legitimately remove the tracker ones by rewriting those lines); `flutter test` green before every commit.

---

### Task 1: JournalEntry model

**Files:**
- Modify: `lib/engine/models.dart` (replace the `LogEntry` class, lines 68–112)
- Test: `test/journal_test.dart`

- [ ] **Step 1: Write failing tests**

In `test/journal_test.dart`, replace the `LogEntry` import usage with `JournalEntry` and add a new group (keep the existing threadId tests, renaming `LogEntry`→`JournalEntry`):

```dart
group('JournalEntry kinds', () {
  test('kind defaults to result when absent in JSON (legacy entries)', () {
    final e = JournalEntry.fromJson({
      'id': '1',
      'timestamp': '2026-06-11T10:00:00.000',
      'title': 'Fate Check',
      'body': 'Yes',
    });
    expect(e.kind, JournalKind.result);
    expect(e.chaosFactor, isNull);
  });

  test('text and scene kinds round-trip with chaos factor', () {
    final scene = JournalEntry(
      id: '2',
      timestamp: DateTime(2026, 6, 11),
      title: 'The gatehouse',
      body: '',
      kind: JournalKind.scene,
      chaosFactor: 6,
    );
    final back = JournalEntry.fromJson(scene.toJson());
    expect(back.kind, JournalKind.scene);
    expect(back.chaosFactor, 6);
    final text = JournalEntry(
      id: '3',
      timestamp: DateTime(2026, 6, 11),
      title: '',
      body: 'We slip inside.',
      kind: JournalKind.text,
    );
    expect(JournalEntry.fromJson(text.toJson()).kind, JournalKind.text);
  });

  test('copyWith preserves kind and chaosFactor', () {
    final e = JournalEntry(
      id: '4',
      timestamp: DateTime(2026, 6, 11),
      title: 'Scene',
      body: '',
      kind: JournalKind.scene,
      chaosFactor: 4,
    );
    final edited = e.copyWith(title: 'Scene 2');
    expect(edited.kind, JournalKind.scene);
    expect(edited.chaosFactor, 4);
  });
});
```

- [ ] **Step 2: Run, verify failure**

Run: `flutter test test/journal_test.dart`
Expected: compile error — `JournalEntry` undefined.

- [ ] **Step 3: Implement the model**

In `lib/engine/models.dart`, replace the whole `LogEntry` class with:

```dart
/// Kind of journal entry: player prose, a tool result, or a scene divider.
enum JournalKind { text, result, scene }

/// Persisted journal entry (formerly LogEntry; old JSON parses as `result`).
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.timestamp,
    required this.title,
    required this.body,
    this.threadId,
    this.kind = JournalKind.result,
    this.chaosFactor,
  });
  final String id;
  final DateTime timestamp;
  final String title;
  final String body;
  final String? threadId;
  final JournalKind kind;

  /// Chaos factor snapshot for scene dividers (Mythic), else null.
  final int? chaosFactor;

  JournalEntry copyWith({
    String? title,
    String? body,
    String? threadId,
    bool clearThreadId = false,
  }) =>
      JournalEntry(
        id: id,
        timestamp: timestamp,
        title: title ?? this.title,
        body: body ?? this.body,
        threadId: clearThreadId ? null : (threadId ?? this.threadId),
        kind: kind,
        chaosFactor: chaosFactor,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'title': title,
        'body': body,
        'threadId': threadId,
        'kind': kind.name,
        if (chaosFactor != null) 'chaosFactor': chaosFactor,
      };

  factory JournalEntry.fromJson(Map<String, dynamic> j) => JournalEntry(
        id: j['id'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        title: j['title'] as String,
        body: j['body'] as String,
        threadId: j['threadId'] as String?,
        kind: JournalKind.values.asNameMap()[j['kind']] ?? JournalKind.result,
        chaosFactor: j['chaosFactor'] as int?,
      );
}
```

Do NOT touch other call sites yet — the project will not compile until Task 2 finishes the rename. That is expected mid-task-sequence; Tasks 1–2 land as one commit pair in quick succession, and only `test/journal_test.dart` is run in between.

- [ ] **Step 4: Run model tests only**

Run: `flutter test test/journal_test.dart`
Expected: the new model group PASSES; the provider group in the same file still FAILS to compile (it references `logProvider`) — comment nothing out; proceed straight to Task 2 which fixes it.

If the provider-group compile failure blocks the model group from running, temporarily run only the model tests by moving the provider group to Task 2's step 1 edit. Do not commit yet.

### Task 2: JournalNotifier, provider rename, migration

**Files:**
- Modify: `lib/state/providers.dart` (LogNotifier block lines 50–83, sessionScopedKeys lines 182–188, SessionsNotifier.remove lines 234–244)
- Modify (mechanical rename `logProvider`→`journalProvider`, `LogEntry`→`JournalEntry`): `lib/features/fate_screen.dart`, `lib/features/generators_screen.dart`, `lib/features/tables_screen.dart`, `lib/features/moves_screen.dart`, `lib/features/tracker_screen.dart`
- Test: `test/journal_test.dart`

- [ ] **Step 1: Write failing tests**

In `test/journal_test.dart`, update the existing provider group to `journalProvider` and add:

```dart
test('migrates juice.log.v1 data into juice.journal.v2 once', () async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.log.v1.default':
        '[{"id":"a","timestamp":"2026-06-11T09:00:00.000","title":"Old","body":"Yes"}]',
  });
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final entries = await container.read(journalProvider.future);
  expect(entries.single.title, 'Old');
  expect(entries.single.kind, JournalKind.result);
  final prefs = await SharedPreferences.getInstance();
  expect(prefs.getString('juice.journal.v2.default'), isNotNull);
  // Non-destructive: legacy key still present.
  expect(prefs.getString('juice.log.v1.default'), isNotNull);
});

test('addText and addScene append typed entries', () async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
  });
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await container.read(journalProvider.future);
  final n = container.read(journalProvider.notifier);
  await n.addText('We slip inside.');
  await n.addScene('The gatehouse', chaosFactor: 6);
  final entries = await container.read(journalProvider.future);
  // Newest-first storage (same as before; the UI reverses for display).
  expect(entries.first.kind, JournalKind.scene);
  expect(entries.first.chaosFactor, 6);
  expect(entries[1].kind, JournalKind.text);
  expect(entries[1].body, 'We slip inside.');
});
```

- [ ] **Step 2: Run, verify failure**

Run: `flutter test test/journal_test.dart`
Expected: FAIL — `journalProvider` undefined.

- [ ] **Step 3: Implement notifier + renames**

In `lib/state/providers.dart`, replace the `LogNotifier` block with:

```dart
// -- Journal ----------------------------------------------------------------
class JournalNotifier extends _PersistedList<JournalEntry> {
  @override
  String get prefsKey => 'juice.journal.v2';
  @override
  JournalEntry fromJson(Map<String, dynamic> json) =>
      JournalEntry.fromJson(json);
  @override
  Map<String, dynamic> toJsonMap(JournalEntry item) => item.toJson();

  static const _legacyKey = 'juice.log.v1';

  @override
  Future<List<JournalEntry>> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    final prefs = await SharedPreferences.getInstance();
    final scoped = '$prefsKey.${sessions.active}';
    // One-shot, non-destructive migration from the legacy log key. Old
    // entries lack 'kind' and parse as JournalKind.result.
    if (prefs.getString(scoped) == null) {
      final legacy = prefs.getString('$_legacyKey.${sessions.active}');
      if (legacy != null) await prefs.setString(scoped, legacy);
    }
    return super.build();
  }

  Future<void> add(String title, String body) async {
    await _persist([
      JournalEntry(
          id: _newId(), timestamp: DateTime.now(), title: title, body: body),
      ..._current,
    ]);
  }

  Future<void> addText(String body) async {
    await _persist([
      JournalEntry(
          id: _newId(),
          timestamp: DateTime.now(),
          title: '',
          body: body,
          kind: JournalKind.text),
      ..._current,
    ]);
  }

  Future<void> addScene(String title, {int? chaosFactor}) async {
    await _persist([
      JournalEntry(
          id: _newId(),
          timestamp: DateTime.now(),
          title: title,
          body: '',
          kind: JournalKind.scene,
          chaosFactor: chaosFactor),
      ..._current,
    ]);
  }

  Future<void> replace(JournalEntry entry) async {
    await _persist([
      for (final e in _current) if (e.id == entry.id) entry else e,
    ]);
  }

  Future<void> remove(String id) async {
    await _persist(_current.where((e) => e.id != id).toList());
  }

  Future<void> clear() async => _persist(<JournalEntry>[]);
}

final journalProvider =
    AsyncNotifierProvider<JournalNotifier, List<JournalEntry>>(
        JournalNotifier.new);
```

Note `build()` calls `super.build()` after seeding the key — `_PersistedList.build` then loads it and sets `_scopedKey`. Verify `_PersistedList.build` is invocable via `super` (it is — same class hierarchy).

Update `sessionScopedKeys` (export/remove/legacy-adoption all read this list; keep the legacy key so v1 campaign imports still carry log data, which the migration then adopts):

```dart
const sessionScopedKeys = [
  'juice.journal.v2',
  'juice.log.v1', // legacy; kept so v1 campaign imports round-trip
  'juice.threads.v1',
  'juice.characters.v1',
  'juice.crawl.v1',
];
```

Then mechanical rename in the five feature files: `logProvider`→`journalProvider`, `LogEntry`→`JournalEntry` (grep to find all: `grep -rn "logProvider\|LogEntry" lib/`).

- [ ] **Step 4: Run full test suite**

Run: `flutter test`
Expected: PASS (68 tests + new ones). `sessions_test.dart` uses `'juice.log.v1'` literals — still valid since the key remains in `sessionScopedKeys`.

- [ ] **Step 5: Commit**

```bash
git add -A lib test
git commit -m "feat: journal entry model + provider (kind, scene chaos, log migration)"
```

### Task 3: Campaign schema v2

**Files:**
- Modify: `lib/state/campaign_io.dart`
- Test: `test/campaign_io_test.dart`

- [ ] **Step 1: Write failing tests**

Add to `test/campaign_io_test.dart`:

```dart
test('writes schemaVersion 2 and journal data', () {
  final out = encodeCampaign(
    name: 'C1',
    savedAt: DateTime(2026, 6, 11),
    rawByKey: {
      'juice.journal.v2':
          '[{"id":"a","timestamp":"2026-06-11T09:00:00.000","title":"T","body":"B","kind":"text"}]',
    },
  );
  final decoded = jsonDecode(out) as Map<String, dynamic>;
  expect(decoded['schemaVersion'], 2);
  expect(decoded['data'], contains('juice.journal.v2'));
});

test('imports a v1 campaign file (log key only)', () {
  final v1 = jsonEncode({
    'app': 'juice-oracle',
    'schemaVersion': 1,
    'savedAt': '2026-06-11T00:00:00.000',
    'name': 'Old campaign',
    'data': {
      'juice.log.v1': [
        {
          'id': 'a',
          'timestamp': '2026-06-11T09:00:00.000',
          'title': 'T',
          'body': 'B'
        }
      ],
    },
  });
  final parsed = parseCampaign(v1);
  expect(parsed.rawByKey, contains('juice.log.v1'));
});

test('rejects malformed journal payloads', () {
  final bad = jsonEncode({
    'app': 'juice-oracle',
    'schemaVersion': 2,
    'savedAt': '2026-06-11T00:00:00.000',
    'name': 'X',
    'data': {
      'juice.journal.v2': [{'id': 42}],
    },
  });
  expect(() => parseCampaign(bad), throwsFormatException);
});
```

- [ ] **Step 2: Run, verify failure**

Run: `flutter test test/campaign_io_test.dart`
Expected: FAIL — schemaVersion is 1; journal key not validated.

- [ ] **Step 3: Implement**

In `lib/state/campaign_io.dart`:

```dart
const campaignSchemaVersion = 2;
```

In `parseCampaign`'s per-key validation, add a branch before the `juice.log.v1` one:

```dart
if (key == 'juice.journal.v2') {
  (value as List)
      .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
      .toList();
} else if (key == 'juice.log.v1') {
  (value as List)
      .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
      .toList();
} ...
```

(`LogEntry` no longer exists; both keys validate through `JournalEntry.fromJson`, which accepts legacy shapes.) The version check `version > campaignSchemaVersion` already accepts 1 and 2 — no change needed there.

- [ ] **Step 4: Run full suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/campaign_io.dart test/campaign_io_test.dart
git commit -m "feat: campaign schema v2 with journal data (v1 still imports)"
```

### Task 4: Journal screen replacing the Log tab

**Files:**
- Create: `lib/features/journal_screen.dart`
- Modify: `lib/features/tracker_screen.dart` (remove `_LogTab`/`_LogTabState`, tab wiring at top)
- Test: `test/widget_smoke_test.dart` (or new `test/journal_screen_test.dart` if smoke file doesn't pump Tracker)

- [ ] **Step 1: Write failing widget test**

Create `test/journal_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('composer adds a text entry; scene divider renders chaos',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: JournalScreen()))));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('journal-composer')),
        'We slip inside.');
    await tester.tap(find.byKey(const Key('journal-send')));
    await tester.pumpAndSettle();
    expect(find.text('We slip inside.'), findsOneWidget);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(JournalScreen)));
    await container
        .read(journalProvider.notifier)
        .addScene('The gatehouse', chaosFactor: 6);
    await tester.pumpAndSettle();
    expect(find.text('The gatehouse'), findsOneWidget);
    expect(find.text('Chaos 6'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, verify failure**

Run: `flutter test test/journal_screen_test.dart`
Expected: FAIL — `journal_screen.dart` doesn't exist.

- [ ] **Step 3: Implement JournalScreen**

Create `lib/features/journal_screen.dart`. Content: adapt `_LogTabState` from `tracker_screen.dart` with these changes (full skeleton below — flesh out list-item rendering by moving the existing Card/ListTile + PopupMenu code over unchanged, including `_onAction` with its link/edit/delete dialogs):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';

/// Journal stream: oldest at top, newest at bottom, composer pinned below.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  String? _filterThreadId;
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    await ref.read(journalProvider.notifier).addText(text);
    _composer.clear();
  }

  Future<void> _newScene() async {
    final chaos = ref.read(crawlProvider).valueOrNull?.chaosFactor;
    final title = await showDialog<String>(
      context: context,
      builder: (context) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('New scene'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Scene title'),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(c.text),
                child: const Text('Start scene')),
          ],
        );
      },
    );
    if (title == null || title.trim().isEmpty) return;
    await ref
        .read(journalProvider.notifier)
        .addScene(title.trim(), chaosFactor: chaos);
  }

  @override
  Widget build(BuildContext context) {
    // Structure:
    //  Column(
    //    [thread filter chips — moved over from _LogTab unchanged],
    //    Expanded(ListView.builder(controller: _scroll,
    //      entries REVERSED relative to storage: storage is newest-first,
    //      display is oldest-first => iterate entries.reversed)),
    //    composer row: TextField(key: Key('journal-composer'),
    //      controller: _composer, minLines: 1, maxLines: 4,
    //      onSubmitted: (_) => _send())
    //      + IconButton(key: Key('journal-send'), icon: Icons.send, onPressed: _send)
    //      + IconButton(tooltip: 'New scene', icon: Icons.movie_outlined,
    //          onPressed: _newScene),
    //  )
    // Entry rendering by kind:
    //  - scene: full-width divider — Row(Expanded(Divider()), Text(title),
    //      if (chaosFactor != null) Chip(label: Text('Chaos $chaosFactor')),
    //      Expanded(Divider())) with the entry PopupMenu kept for edit/delete.
    //  - text: Card with just the body (no title line).
    //  - result: existing Card/ListTile rendering moved from _LogTab.
    // The existing _onAction(link/edit/delete) moves over verbatim with
    // LogEntry -> JournalEntry.
    ...
  }
}
```

The implementer writes the real `build` from this structure plus the moved `_LogTab` code — every behavior (filter chips, threadTitle fallback, Clear button, edit/link/delete menu) is preserved, only order reversed, composer added, kind-aware rendering added.

In `tracker_screen.dart`: delete `_LogTab`/`_LogTabState`, import `journal_screen.dart`, and replace the tab content with `JournalScreen()`; tab label stays first but renames `Log`→`Journal`.

- [ ] **Step 4: Run widget test + full suite**

Run: `flutter test`
Expected: PASS, including the existing `widget_smoke_test.dart` (update any `Log` label finders to `Journal`).

- [ ] **Step 5: Rename user-facing "Log" affordances**

Grep: `grep -rn "'Logged'\|Log this result" lib/`. In `lib/shared/result_card.dart` and `lib/features/fate_screen.dart` (and any other hit): tooltip `Log this result`→`Add to journal`, snackbar `Logged`→`Added to journal`. Run `flutter test` again.

- [ ] **Step 6: Commit**

```bash
git add -A lib test
git commit -m "feat: journal screen with composer + scene dividers replaces Log tab"
```

### Task 5: Verify, docs, ship

**Files:**
- Modify: `README.md` (tracker feature bullet, success-criteria row 4), `CLAUDE.md` (persistence note: add `juice.journal.v2`, mention legacy log migration)

- [ ] **Step 1: Full local verification**

```bash
flutter analyze --no-fatal-infos   # only pre-existing infos
flutter test                        # all green
python3 build_oracle.py             # still passes (untouched, sanity)
flutter build web                   # builds
```

- [ ] **Step 2: Browser verify**

Serve `build/web` (`.claude/launch.json` → `flutter-web`), enable semantics, then: Tracker tab → Journal tab shows migrated/empty state; roll a Fate Check → "Add to journal" → entry appears at the bottom of the journal. Composer text input cannot be driven headless — covered by `journal_screen_test.dart`; say so in the PR.

- [ ] **Step 3: Update docs**

README: row 4 of success criteria mentions journal (text/scene/result entries); feature paragraph: "persistent threads / characters / roll-log" → "journal (prose, scenes, and rolls)". CLAUDE.md persistence bullet: sessionScopedKeys now includes `juice.journal.v2` (with `juice.log.v1` kept for legacy import + one-shot migration).

- [ ] **Step 4: Commit + PR + merge after green CI**

```bash
git add README.md CLAUDE.md
git commit -m "docs: journal core notes"
git push -u origin feat/journal-core
gh pr create --title "Journal core (redesign phase 1)" --body "..."
# WAIT for CI completed+success on the branch BEFORE merging:
#   until gh run list --branch feat/journal-core --limit 1 --json status \
#     --jq '.[0].status' | grep -q completed; do sleep 15; done
gh pr merge --squash --delete-branch
```
