# Campaign Launcher L1 — Gate + LauncherScreen (enter flows) — Implementation Plan

> **For agentic workers:** execute task-by-task, TDD, commit per task. Steps use `- [ ]`.

**Goal:** A full-screen **startup launcher** shown on every cold start: **Continue** the active
campaign, **switch** to another, start a **New** one (name + systems), or **Import** from file. Each
action dismisses an in-memory gate → the journal. No new SessionsNotifier logic (reuses
create/switchTo/importCampaign); genre/tone, rename, delete are L2.

**Architecture:** `launcherGateProvider` (transient `Notifier<bool>`, default true) → `app.dart`
gate branch picks `LauncherScreen` vs `HomeShell` → `LauncherScreen` reuses `SessionsNotifier` +
the (made-public) `NewCampaignDialog` + the existing FilePicker import flow.

**Tech Stack:** Dart, flutter_riverpod, shared_preferences, file_picker.

---

### Task 1: `launcherGateProvider`

**Files:** Modify `lib/state/providers.dart`; Test `test/launcher_gate_test.dart` (new).

- [ ] **Step 1:** Failing test in `test/launcher_gate_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  test('launcher gate defaults shown, dismiss hides it', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(launcherGateProvider), isTrue);
    c.read(launcherGateProvider.notifier).dismiss();
    expect(c.read(launcherGateProvider), isFalse);
  });
}
```

- [ ] **Step 2:** Run `flutter test test/launcher_gate_test.dart` → FAIL (undefined).
- [ ] **Step 3:** Add near the sessions providers in `providers.dart`:

```dart
/// Transient launcher gate: shown on every cold start (in-memory, not
/// persisted). Any launcher entry action calls [dismiss] to enter the journal.
class LauncherGateNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void dismiss() => state = false;
}

final launcherGateProvider =
    NotifierProvider<LauncherGateNotifier, bool>(LauncherGateNotifier.new);
```

- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit: `feat(launcher): launcherGateProvider (L1)`.

---

### Task 2: make `NewCampaignDialog` public (reuse from the launcher)

**Files:** Modify `lib/shared/home_shell.dart`.

- [ ] **Step 1:** Rename the private class `_NewCampaignDialog` → `NewCampaignDialog` (class
  declaration + its constructor `const NewCampaignDialog(...)`). Update the single usage in
  `_createSession` (`builder: (context) => const NewCampaignDialog()`).
- [ ] **Step 2:** `dart analyze lib/shared/home_shell.dart` → no issues.
- [ ] **Step 3:** `flutter test` → all green (no behaviour change).
- [ ] **Step 4:** Commit: `refactor(launcher): make NewCampaignDialog public for reuse (L1)`.

---

### Task 3: `LauncherScreen`

**Files:** Create `lib/features/launcher_screen.dart`; Test `test/launcher_screen_test.dart` (new).

- [ ] **Step 1:** Write the failing widget test `test/launcher_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/features/launcher_screen.dart';
import 'package:juice_oracle/state/providers.dart';

class _FixedSessions extends SessionsNotifier {
  _FixedSessions(this.state0);
  final SessionsState state0;
  @override
  Future<SessionsState> build() async => state0;
}

ProviderContainer _container() {
  SharedPreferences.setMockInitialValues({});
  return ProviderContainer(overrides: [
    sessionsProvider.overrideWith(() => _FixedSessions(const SessionsState(
          active: 'a',
          sessions: [
            SessionMeta(id: 'a', name: 'Alpha'),
            SessionMeta(id: 'b', name: 'Beta'),
          ],
        ))),
  ]);
}

Future<void> _pump(WidgetTester t, ProviderContainer c) async {
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: LauncherScreen()),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Continue shows the active campaign and dismisses the gate',
      (t) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(t, c);
    expect(find.textContaining('Alpha'), findsWidgets);
    expect(c.read(launcherGateProvider), isTrue);
    await t.tap(find.byKey(const Key('launcher-continue')));
    await t.pumpAndSettle();
    expect(c.read(launcherGateProvider), isFalse);
  });

  testWidgets('tapping another campaign switches and dismisses', (t) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(t, c);
    await t.tap(find.byKey(const Key('launcher-campaign-b')));
    await t.pumpAndSettle();
    expect(c.read(sessionsProvider).valueOrNull?.active, 'b');
    expect(c.read(launcherGateProvider), isFalse);
  });

  testWidgets('New and Import actions are present', (t) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(t, c);
    expect(find.byKey(const Key('launcher-new')), findsOneWidget);
    expect(find.byKey(const Key('launcher-import')), findsOneWidget);
  });
}
```

- [ ] **Step 2:** Run → FAIL (no `LauncherScreen`).
- [ ] **Step 3:** Create `lib/features/launcher_screen.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/home_shell.dart' show NewCampaignDialog;
import '../state/providers.dart';

/// Startup campaign menu: Continue / switch / New / Import. Shown while
/// [launcherGateProvider] is true; every entry action dismisses the gate.
class LauncherScreen extends ConsumerWidget {
  const LauncherScreen({super.key});

  void _enter(WidgetRef ref) =>
      ref.read(launcherGateProvider.notifier).dismiss();

  Future<void> _switch(WidgetRef ref, String id) async {
    await ref.read(sessionsProvider.notifier).switchTo(id);
    _enter(ref);
  }

  Future<void> _new(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({String name, Set<String> systems})>(
      context: context,
      builder: (context) => const NewCampaignDialog(),
    );
    if (result == null || result.name.trim().isEmpty) return;
    await ref
        .read(sessionsProvider.notifier)
        .create(result.name.trim(), systems: result.systems);
    _enter(ref);
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: 'Import campaign',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
    } on PlatformException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not access files: ${e.message}')));
      }
      return;
    }
    final bytes = (result == null || result.files.isEmpty)
        ? null
        : result.files.first.bytes;
    if (bytes == null) return; // cancelled
    try {
      await ref
          .read(sessionsProvider.notifier)
          .importCampaign(utf8.decode(bytes));
      _enter(ref);
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sessions = ref.watch(sessionsProvider).valueOrNull;
    if (sessions == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final active = sessions.activeMeta;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Text('Juice', style: theme.textTheme.headlineMedium),
                Text('Solo TTRPG toolkit',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('launcher-continue'),
                  onPressed: () => _enter(ref),
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Continue · ${active.name}'),
                ),
                const SizedBox(height: 16),
                Text('Campaigns', style: theme.textTheme.titleSmall),
                for (final s in sessions.sessions)
                  ListTile(
                    key: Key('launcher-campaign-${s.id}'),
                    leading: Icon(s.id == sessions.active
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off),
                    title: Text(s.name),
                    onTap: () => _switch(ref, s.id),
                  ),
                const Divider(),
                ListTile(
                  key: const Key('launcher-new'),
                  leading: const Icon(Icons.add),
                  title: const Text('New campaign'),
                  onTap: () => _new(context, ref),
                ),
                ListTile(
                  key: const Key('launcher-import'),
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Import from file'),
                  onTap: () => _import(context, ref),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4:** `dart analyze lib/features/launcher_screen.dart` → no issues.
- [ ] **Step 5:** Run `flutter test test/launcher_screen_test.dart` → PASS.
- [ ] **Step 6:** Commit: `feat(launcher): LauncherScreen with Continue/switch/New/Import (L1)`.

---

### Task 4: wire the gate into `app.dart`

**Files:** Modify `lib/app.dart`.

- [ ] **Step 1:** Add the import: `import 'features/launcher_screen.dart';`.
- [ ] **Step 2:** Replace the `data:` branch with the gate:

```dart
        data: (o) => ref.watch(launcherGateProvider)
            ? const LauncherScreen()
            : HomeShell(oracle: o),
```

- [ ] **Step 3:** `dart analyze lib/app.dart` → no issues.
- [ ] **Step 4:** Commit: `feat(launcher): gate app startup on the launcher (L1)`.

---

### Task 5: Full verification + ship

- [ ] **Step 1:** `dart analyze` → No issues.
- [ ] **Step 2:** `flutter test` → all green (≥ 767 + new).
- [ ] **Step 3:** Web-verify: `flutter build web --debug`; `preview_start flutter-web`;
  `preview_eval` reload + read the DOM/snapshot to confirm the launcher renders first (Continue
  visible) and that dismissing reaches the journal. Since the Flutter canvas can't take synthetic
  taps, at minimum confirm the app boots without console errors and the launcher is the first paint
  (screenshot). Stop the server.
- [ ] **Step 4:** Reviewer pass (`caveman:cavecrew-reviewer`) on `git diff main..HEAD`; address findings.
- [ ] **Step 5:** Push, open PR, watch CI, squash-merge, delete branch, sync `main`.

---

## Self-review notes
- Gate is in-memory (`Notifier<bool>` default true) → shows every cold start; `dismiss()` is the only
  mutation. Not persisted.
- LauncherScreen reuses `switchTo`/`create`/`importCampaign` and the now-public `NewCampaignDialog`;
  no new SessionsNotifier logic in L1.
- Widget tests run LauncherScreen in isolation (override `sessionsProvider`, real
  `launcherGateProvider`) — never pump `HomeShell` (rootBundle-hang rule); assert the gate bool flips.
- L1 list rows are tap-to-switch only; rename/delete + genre/tone are L2.
- All buttons/tiles are in a bounded `ListView`/`ConstrainedBox` (loose-constraint safe).
