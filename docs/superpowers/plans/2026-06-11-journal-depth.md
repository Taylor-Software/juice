# Journal Depth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Log entries can be linked to a Thread, filtered by Thread, and edited — the journal becomes campaign memory instead of a flat roll list.

**Architecture:** Additive `threadId` on `LogEntry` (campaign files stay schema v1 — parser tolerates absence). `LogNotifier.replace` mirrors the Thread/Character pattern. `_LogTab` becomes stateful with a thread filter chip row and a per-entry menu (link / edit / delete).

**Tech Stack:** existing only.

---

### Task 1: Model + notifier (TDD)

**Files:**
- Modify: `lib/engine/models.dart` (LogEntry)
- Modify: `lib/state/providers.dart` (LogNotifier)
- Test: `test/journal_test.dart` (create)

- [ ] **Step 1: Failing test** — create `test/journal_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LogEntry threadId', () {
    test('round-trips and defaults to null on old json', () {
      final e = LogEntry(
        id: '1',
        timestamp: DateTime.utc(2026),
        title: 't',
        body: 'b',
        threadId: 'th1',
      );
      expect(LogEntry.fromJson(e.toJson()).threadId, 'th1');
      expect(
        LogEntry.fromJson(
            {'id': '1', 'timestamp': '2026-01-01T00:00:00Z', 'title': 't', 'body': 'b'}).threadId,
        isNull,
      );
    });

    test('copyWith can set and clear the link', () {
      final e = LogEntry(
          id: '1', timestamp: DateTime.utc(2026), title: 't', body: 'b');
      final linked = e.copyWith(threadId: 'th1');
      expect(linked.threadId, 'th1');
      expect(linked.copyWith(clearThreadId: true).threadId, isNull);
      expect(linked.copyWith(body: 'edited').threadId, 'th1');
    });
  });

  group('LogNotifier.replace', () {
    test('replaces an entry in place and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      await container.read(logProvider.future);
      final notifier = container.read(logProvider.notifier);
      await notifier.add('Roll', 'body');
      final entry = (await container.read(logProvider.future)).single;
      await notifier.replace(entry.copyWith(threadId: 'th9', body: 'edited'));
      final after = (await container.read(logProvider.future)).single;
      expect(after.threadId, 'th9');
      expect(after.body, 'edited');
      expect(after.id, entry.id);
    });
  });
}
```

- [ ] **Step 2:** `flutter test test/journal_test.dart` → FAIL (threadId/copyWith/replace undefined).

- [ ] **Step 3: Implement.** `LogEntry` in `lib/engine/models.dart` gains `final String? threadId;` (constructor optional param), a `copyWith`:

```dart
  LogEntry copyWith({
    String? title,
    String? body,
    String? threadId,
    bool clearThreadId = false,
  }) =>
      LogEntry(
        id: id,
        timestamp: timestamp,
        title: title ?? this.title,
        body: body ?? this.body,
        threadId: clearThreadId ? null : (threadId ?? this.threadId),
      );
```

`toJson` adds `'threadId': threadId`; `fromJson` reads `j['threadId'] as String?`.

`LogNotifier` in `lib/state/providers.dart` gains (mirror ThreadNotifier.replace):

```dart
  Future<void> replace(LogEntry entry) async {
    await _persist([
      for (final e in _current) if (e.id == entry.id) entry else e,
    ]);
  }
```

- [ ] **Step 4:** full `flutter test` → 55 passing (52 + 3). `flutter analyze` → 4 infos.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart lib/state/providers.dart test/journal_test.dart
git commit -m "feat: log entries link to threads and support in-place edits"
```

### Task 2: Log tab UI — filter, link, edit

**Files:**
- Modify: `lib/features/tracker_screen.dart` (`_LogTab`)

- [ ] **Step 1: Rewrite `_LogTab`** as a ConsumerStatefulWidget:

```dart
class _LogTab extends ConsumerStatefulWidget {
  const _LogTab();

  @override
  ConsumerState<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends ConsumerState<_LogTab> {
  String? _filterThreadId;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(logProvider);
    final threads = (ref.watch(threadsProvider).valueOrNull ?? const <Thread>[])
        .where((t) => t.open)
        .toList();
    String threadTitle(String id) => threads
        .firstWhere((t) => t.id == id,
            orElse: () => Thread(id: id, title: '(closed thread)'))
        .title;
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (entries) {
        if (entries.isEmpty) {
          return const _Empty('No logged rolls yet. Tap the bookmark on a result.');
        }
        final visible = _filterThreadId == null
            ? entries
            : entries.where((e) => e.threadId == _filterThreadId).toList();
        return Column(
          children: [
            if (threads.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('All'),
                        selected: _filterThreadId == null,
                        onSelected: (_) =>
                            setState(() => _filterThreadId = null),
                      ),
                    ),
                    for (final t in threads)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(t.title),
                          selected: _filterThreadId == t.id,
                          onSelected: (_) =>
                              setState(() => _filterThreadId = t.id),
                        ),
                      ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
                child: TextButton.icon(
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear'),
                  onPressed: () => ref.read(logProvider.notifier).clear(),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: visible.length,
                itemBuilder: (context, i) {
                  final e = visible[i];
                  return Card(
                    child: ListTile(
                      title: Text(e.title),
                      subtitle: Text(e.threadId != null
                          ? '${e.body}\n⤷ ${threadTitle(e.threadId!)}'
                          : e.body),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) => _onAction(action, e, threads),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'link', child: Text('Link to thread…')),
                          const PopupMenuItem(
                              value: 'edit', child: Text('Edit note…')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Delete')),
                        ],
                      ),
                      isThreeLine:
                          e.body.contains('\n') || e.threadId != null,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onAction(
      String action, LogEntry entry, List<Thread> threads) async {
    final notifier = ref.read(logProvider.notifier);
    switch (action) {
      case 'delete':
        await notifier.remove(entry.id);
      case 'link':
        final picked = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Link to thread'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop('__none__'),
                child: const Text('No thread'),
              ),
              for (final t in threads)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(t.id),
                  child: Text(t.title),
                ),
            ],
          ),
        );
        if (picked == null) return;
        await notifier.replace(picked == '__none__'
            ? entry.copyWith(clearThreadId: true)
            : entry.copyWith(threadId: picked));
      case 'edit':
        final result = await showDialog<({String title, String note})>(
          context: context,
          builder: (_) => _EditDialog(
            heading: 'Edit log entry',
            labelA: 'Title',
            labelB: 'Note',
            initialA: entry.title,
            initialB: entry.body,
          ),
        );
        if (result == null || result.title.trim().isEmpty) return;
        await notifier.replace(entry.copyWith(
            title: result.title.trim(), body: result.note));
    }
  }
}
```

(Check `_EditDialog`'s actual return record field names — the Threads tab call
site uses `result.title` / `result.note`; match it. `Thread` import already
present in the file.)

- [ ] **Step 2:** `flutter analyze && flutter test` → 4 infos, 55 passing.

- [ ] **Step 3: Commit**

```bash
git add lib/features/tracker_screen.dart
git commit -m "feat: log filter by thread, link and edit entries"
```

### Task 3: Docs

- README: extend the tracker feature row mention with "log entries link to threads, filter + edit". Minimal edit. Commit `docs: journal depth`.

## Self-review notes
- Roadmap clause "link log entries to threads/characters, filter log by thread, richer notes": thread linking + filter + edit delivered; character-linking deliberately cut (threads are Mythic's narrative spine; characters add a second picker for little gain — note in commit body if asked).
- `threadId` additive: old persisted logs and campaign files parse unchanged (campaign_io validates via LogEntry.fromJson which tolerates absence).
- Closed threads: filter chips show open threads only; linked entries to closed threads still render title via fallback.
