# Campaign Launcher L2 — Manage Flows — Implementation Plan

> **For agentic workers:** execute task-by-task, TDD, commit per task. Steps use `- [ ]`.

**Goal:** Complete the launcher's campaign management: the **New** form gains optional **genre/tone**
(seeded at creation), and the campaign list gains **Rename** (new API) and **Delete** (existing
`remove`).

**Architecture:** `SessionsNotifier.create` gains optional `genre`/`tone` that seed the new session's
`juice.settings.v1.<id>` directly (avoids the settings cascade-timing hazard); a new
`SessionsNotifier.rename`; `NewCampaignDialog` gains genre/tone fields + grouped systems and a wider
return record (both callers updated); `LauncherScreen` rows gain rename/delete affordances.

**Tech Stack:** Dart, flutter_riverpod, shared_preferences.

---

### Task 1: `rename` + `create` genre/tone seed

**Files:** Modify `lib/state/providers.dart`; Test `test/sessions_manage_test.dart` (new).

- [ ] **Step 1:** Failing tests in `test/sessions_manage_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rename changes the target name only', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(sessionsProvider.notifier);
    await c.read(sessionsProvider.future);
    await n.create('Beta');
    final id = c.read(sessionsProvider).value!.active;
    await n.rename(id, 'Renamed');
    var s = c.read(sessionsProvider).value!;
    expect(s.sessions.firstWhere((m) => m.id == id).name, 'Renamed');
    // no-op on blank / unknown
    await n.rename(id, '   ');
    await n.rename('nope', 'X');
    s = c.read(sessionsProvider).value!;
    expect(s.sessions.firstWhere((m) => m.id == id).name, 'Renamed');
  });

  test('create seeds genre/tone into the new session settings', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(sessionsProvider.notifier);
    await c.read(sessionsProvider.future);
    await n.create('Grim', genre: 'grimdark', tone: 'tense');
    final id = c.read(sessionsProvider).value!.active;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('juice.settings.v1.$id');
    expect(raw, isNotNull);
    final cs = CampaignSettings.fromJson(jsonDecode(raw!) as Map<String, dynamic>);
    expect(cs.genre, 'grimdark');
    expect(cs.tone, 'tense');

    await n.create('Plain');
    final id2 = c.read(sessionsProvider).value!.active;
    expect(prefs.getString('juice.settings.v1.$id2'), isNull);
  });
}
```

- [ ] **Step 2:** Run `flutter test test/sessions_manage_test.dart` → FAIL.
- [ ] **Step 3:** Extend `create` and add `rename` in `SessionsNotifier`. Replace the existing
  `create` with:

```dart
  Future<void> create(String name,
      {Set<String>? systems, String genre = '', String tone = ''}) async {
    final s = state.valueOrNull;
    if (s == null) return;
    final meta =
        SessionMeta(id: _newId(), name: name, systems: systems?.toList());
    if (genre.isNotEmpty || tone.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('juice.settings.v1.${meta.id}',
          jsonEncode(CampaignSettings(genre: genre, tone: tone).toJson()));
    }
    await _save(
        SessionsState(active: meta.id, sessions: [...s.sessions, meta]));
  }

  /// Rename session [id]; no-op for unknown ids or a blank name.
  Future<void> rename(String id, String name) async {
    final s = state.valueOrNull;
    if (s == null || name.trim().isEmpty) return;
    final updated = [
      for (final m in s.sessions)
        if (m.id == id)
          SessionMeta(id: m.id, name: name.trim(), systems: m.systems)
        else
          m,
    ];
    await _save(SessionsState(active: s.active, sessions: updated));
  }
```

  (`CampaignSettings` and `jsonEncode` are already imported in `providers.dart`.)

- [ ] **Step 4:** Run → PASS. `flutter test` → all green (existing create callers unaffected — new
  params default to empty).
- [ ] **Step 5:** Commit: `feat(launcher): SessionsNotifier.rename + create genre/tone seed (L2)`.

---

### Task 2: `NewCampaignDialog` genre/tone + grouped systems

**Files:** Modify `lib/shared/home_shell.dart`, `lib/features/launcher_screen.dart`;
Test `test/new_campaign_dialog_test.dart` (new).

- [ ] **Step 1:** Failing dialog test `test/new_campaign_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/home_shell.dart';

void main() {
  testWidgets('returns name + systems + genre + tone', (t) async {
    ({String name, Set<String> systems, String genre, String tone})? out;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => out = await showDialog<
                  ({String name, Set<String> systems, String genre, String tone})>(
                context: ctx,
                builder: (_) => const NewCampaignDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('new-campaign-name')), 'My');
    await t.enterText(find.byKey(const Key('new-campaign-genre')), 'grimdark');
    await t.enterText(find.byKey(const Key('new-campaign-tone')), 'tense');
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();
    expect(out!.name, 'My');
    expect(out!.genre, 'grimdark');
    expect(out!.tone, 'tense');
    expect(out!.systems, contains('juice'));
  });
}
```

- [ ] **Step 2:** Run → FAIL (no genre/tone fields, record type mismatch).
- [ ] **Step 3:** In `_NewCampaignDialogState` add controllers + dispose + the two fields + grouping,
  and widen the return record:
  - Add fields: `final _genre = TextEditingController(); final _tone = TextEditingController();`
  - In `dispose()`: also `_genre.dispose(); _tone.dispose();`.
  - In `_submit()` change the pop to:
    `Navigator.of(context).pop((name: _controller.text, systems: picked, genre: _genre.text.trim(), tone: _tone.text.trim()));`
  - In `build`, after the name `TextField`, insert the genre/tone fields:

```dart
            TextField(
              key: const Key('new-campaign-genre'),
              controller: _genre,
              decoration: const InputDecoration(
                  labelText: 'Genre (optional)', hintText: 'e.g. grimdark fantasy'),
            ),
            TextField(
              key: const Key('new-campaign-tone'),
              controller: _tone,
              decoration: const InputDecoration(
                  labelText: 'Tone (optional)', hintText: 'e.g. tense and dangerous'),
            ),
            const SizedBox(height: 8),
            const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Default systems'))),
```

  - Before the `sys-lonelog` checkbox, insert a second group label:

```dart
            const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Add-ons'))),
```

- [ ] **Step 4:** Update the `_createSession` caller in `home_shell.dart` — change the `showDialog`
  type and the create call:

```dart
  Future<void> _createSession(BuildContext dialogContext) async {
    final result = await showDialog<
        ({String name, Set<String> systems, String genre, String tone})>(
      context: dialogContext,
      builder: (context) => const NewCampaignDialog(),
    );
    if (result == null || result.name.trim().isEmpty) return;
    await ref.read(sessionsProvider.notifier).create(result.name.trim(),
        systems: result.systems, genre: result.genre, tone: result.tone);
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
  }
```

- [ ] **Step 5:** Update the launcher `_new` in `launcher_screen.dart` the same way (record type +
  pass genre/tone to `create`):

```dart
  Future<void> _new(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<
        ({String name, Set<String> systems, String genre, String tone})>(
      context: context,
      builder: (context) => const NewCampaignDialog(),
    );
    if (result == null || result.name.trim().isEmpty) return;
    await ref.read(sessionsProvider.notifier).create(result.name.trim(),
        systems: result.systems, genre: result.genre, tone: result.tone);
    _enter(ref);
  }
```

- [ ] **Step 6:** `dart analyze lib/shared/home_shell.dart lib/features/launcher_screen.dart` → no issues.
- [ ] **Step 7:** Run `flutter test test/new_campaign_dialog_test.dart` → PASS. `flutter test` → green.
- [ ] **Step 8:** Commit: `feat(launcher): genre/tone + grouped systems in NewCampaignDialog (L2)`.

---

### Task 3: Launcher campaign list — rename + delete

**Files:** Modify `lib/features/launcher_screen.dart`; Test `test/launcher_screen_test.dart` (extend).

- [ ] **Step 1:** Add handlers to `LauncherScreen`:

```dart
  Future<void> _rename(BuildContext context, WidgetRef ref, SessionMeta m) async {
    final controller = TextEditingController(text: m.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename campaign'),
        content: TextField(
          key: const Key('rename-field'),
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('rename-confirm'),
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(sessionsProvider.notifier).rename(m.id, name);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, SessionMeta m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${m.name}"?'),
        content: const Text(
            'Its journal, threads, characters, and maps are removed permanently.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('delete-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await ref.read(sessionsProvider.notifier).remove(m.id);
  }
```

- [ ] **Step 2:** Give each campaign `ListTile` a trailing rename/delete `Row` (delete only when >1).
  Replace the campaign-list `ListTile` in `build` with:

```dart
                for (final s in sessions.sessions)
                  ListTile(
                    key: Key('launcher-campaign-${s.id}'),
                    leading: Icon(s.id == sessions.active
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off),
                    title: Text(s.name),
                    onTap: () => _switch(ref, s.id),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: Key('launcher-rename-${s.id}'),
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Rename',
                          onPressed: () => _rename(context, ref, s),
                        ),
                        if (sessions.sessions.length > 1)
                          IconButton(
                            key: Key('launcher-delete-${s.id}'),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Delete',
                            onPressed: () => _delete(context, ref, s),
                          ),
                      ],
                    ),
                  ),
```

  Add `import '../engine/models.dart';` for `SessionMeta` if not present.
- [ ] **Step 3:** `dart analyze lib/features/launcher_screen.dart` → no issues.
- [ ] **Step 4:** Extend `test/launcher_screen_test.dart` with rename + delete:

```dart
  testWidgets('rename updates the campaign name', (t) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(t, c);
    await t.tap(find.byKey(const Key('launcher-rename-b')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('rename-field')), 'Gamma');
    await t.tap(find.byKey(const Key('rename-confirm')));
    await t.pumpAndSettle();
    expect(
        c.read(sessionsProvider).valueOrNull!.sessions
            .firstWhere((m) => m.id == 'b').name,
        'Gamma');
  });

  testWidgets('delete removes a campaign', (t) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(t, c);
    await t.tap(find.byKey(const Key('launcher-delete-b')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('delete-confirm')));
    await t.pumpAndSettle();
    expect(c.read(sessionsProvider).valueOrNull!.sessions.any((m) => m.id == 'b'),
        isFalse);
  });
```

- [ ] **Step 5:** Run `flutter test test/launcher_screen_test.dart` → PASS.
- [ ] **Step 6:** Commit: `feat(launcher): rename + delete in the launcher campaign list (L2)`.

---

### Task 4: Full verification + ship

- [ ] **Step 1:** `dart analyze` → No issues.
- [ ] **Step 2:** `flutter test` → all green.
- [ ] **Step 3:** Web-verify: `flutter build web --debug`; `preview_start`; screenshot the launcher
  (New dialog shows genre/tone; rows show rename/delete). Stop the server.
- [ ] **Step 4:** Reviewer pass on `git diff main..HEAD`; address findings.
- [ ] **Step 5:** Push, PR, watch CI, squash-merge, delete branch, sync `main`.

---

## Self-review notes
- `create` seeds genre/tone directly into the new session's settings key — robust against the
  settings cascade-timing hazard; empty genre/tone write nothing (existing callers unaffected).
- `rename` is the only new SessionsNotifier method; `remove` (delete) already reassigns active + keeps ≥1.
- The dialog's return record widened to 4 fields; BOTH callers (`_createSession`, launcher `_new`)
  updated in the same task so nothing compiles against the old shape.
- Rename/Delete in the launcher do NOT dismiss the gate (managing ≠ entering); switching/continuing do.
- All buttons in bounded layouts (dialog `SingleChildScrollView`, launcher `ListView`).
