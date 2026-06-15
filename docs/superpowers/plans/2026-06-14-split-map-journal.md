# Side-by-Side Map + Journal — Implementation Plan

> **For agentic workers:** execute task-by-task, TDD, commit per task. Steps use `- [ ]`.

**Goal:** A wide-screen toggle that pins the Journal beside the selected destination (default Maps),
giving Map + Journal side by side. Off by default, persisted; phones unchanged.

**Architecture:** persisted `splitViewProvider` (global bool) → `HomeShell` app-bar toggle (shown
≥1000px) → `_shellBody` split branch renders `Rail │ left IndexedStack │ drag handle │ Journal`.

**Tech Stack:** Dart, flutter_riverpod, shared_preferences.

---

### Task 1: `splitViewProvider`

**Files:** Modify `lib/state/providers.dart`; Test `test/split_view_test.dart` (new).

- [ ] **Step 1:** Failing test `test/split_view_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('split view defaults false, toggles and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(splitViewProvider.future), isFalse);
    await c.read(splitViewProvider.notifier).toggle();
    expect(c.read(splitViewProvider).value, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('juice.splitview.v1'), isTrue);
  });
}
```

- [ ] **Step 2:** Run `flutter test test/split_view_test.dart` → FAIL.
- [ ] **Step 3:** Add after `rulesetsProvider` in `providers.dart`:

```dart
// -- Split view (global layout preference, not session-scoped) ---------------
class SplitViewNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.splitview.v1';
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> toggle() async {
    final next = !(state.valueOrNull ?? false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, next);
    state = AsyncData(next);
  }
}

final splitViewProvider =
    AsyncNotifierProvider<SplitViewNotifier, bool>(SplitViewNotifier.new);
```

- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit: `feat(shell): splitViewProvider (persisted layout toggle)`.

---

### Task 2: `_shellBody` split branch + drag handle + toggle

**Files:** Modify `lib/shared/home_shell.dart`.

- [ ] **Step 1:** Add transient width state to `_HomeShellState` (near `_bodyKey`):

```dart
  double _journalWidth = 400; // split-view journal panel width (draggable)
```

- [ ] **Step 2:** In `_shellBody`, read the toggle near the top (after `route`/`destinations`):

```dart
    final split = ref.watch(splitViewProvider).valueOrNull ?? false;
```

  Then, inside the `LayoutBuilder` builder, add a `canSplit` + split branch BEFORE the existing
  `if (wide)`:

```dart
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 840;
      final canSplit = c.maxWidth >= 1000;
      if (split && canSplit) {
        final leftDest = [
          for (final d in destinations)
            if (d != Destination.journal) d
        ];
        final leftIndex =
            leftDest.indexOf(route.destination).clamp(0, leftDest.length - 1);
        final maxJournal = c.maxWidth * 0.6;
        final journalW = _journalWidth.clamp(320.0, maxJournal);
        return Row(children: [
          NavigationRail(
            selectedIndex: leftIndex,
            onDestinationSelected: (i) =>
                ref.read(shellRouteProvider.notifier).goTo(leftDest[i]),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in leftDest)
                NavigationRailDestination(
                  icon: Icon(destinationMeta[d]!.icon),
                  label: Text(destinationMeta[d]!.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Row(children: [
              Expanded(
                child: IndexedStack(
                  index: leftIndex,
                  children: [for (final d in leftDest) _root(d, systems, family)],
                ),
              ),
              _DragHandle(
                onDelta: (dx) => setState(() =>
                    _journalWidth = (_journalWidth - dx).clamp(320.0, maxJournal)),
              ),
              SizedBox(width: journalW, child: const JournalScreen()),
            ]),
          ),
        ]);
      }
      if (wide) {
```

  (Leave the existing `if (wide) { … }` and the narrow `return Scaffold(…)` untouched below.) Note:
  the split `IndexedStack` deliberately has NO `_bodyKey` (that GlobalKey stays on the single-pane
  body; reusing it across the two layouts would move the element between differently-shaped stacks).

- [ ] **Step 3:** Add the `_DragHandle` widget at the bottom of the file (after `_HomeShellState`):

```dart
/// A thin, draggable vertical divider for resizing the split-view journal.
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.onDelta});
  final void Function(double dx) onDelta;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => onDelta(d.delta.dx),
        child: const SizedBox(
          width: 8,
          child: Center(child: VerticalDivider(width: 1)),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4:** In `build`, add the toggle action. Near the top of `build` add:

```dart
    final split = ref.watch(splitViewProvider).valueOrNull ?? false;
    final wideEnough = MediaQuery.sizeOf(context).width >= 1000;
```

  Then in the app bar `actions:` list, before the Campaigns `IconButton`, insert:

```dart
          if (wideEnough)
            IconButton(
              key: const Key('split-toggle'),
              icon: Icon(
                  split ? Icons.view_sidebar : Icons.view_sidebar_outlined),
              tooltip: split ? 'Single pane' : 'Split with journal',
              onPressed: () => ref.read(splitViewProvider.notifier).toggle(),
            ),
```

- [ ] **Step 5:** `dart analyze lib/shared/home_shell.dart` → no issues.
- [ ] **Step 6:** Commit: `feat(shell): side-by-side map+journal split view (toggle + drag)`.

---

### Task 3: HomeShell split widget tests

**Files:** Modify `test/home_shell_test.dart` (reuse the existing override harness).

- [ ] **Step 1:** Ensure imports for `MapsTab`/`JournalScreen` are present (add if missing):
  `import 'package:juice_oracle/features/maps_tab.dart';`,
  `import 'package:juice_oracle/features/journal_screen.dart';`.
- [ ] **Step 2:** Add two tests in `main()`:

```dart
  testWidgets('split view shows Maps + Journal side by side (wide)',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(
        {'flutter.juice.splitview.v1': true});
    await tester.pumpWidget(ProviderScope(
        overrides: [_verdantOverride, _emulatorOverride],
        child: MaterialApp(home: HomeShell(oracle: _oracle()))));
    await tester.pumpAndSettle();
    expect(find.byType(MapsTab), findsOneWidget);
    expect(find.byType(JournalScreen), findsOneWidget);
    expect(find.byKey(const Key('split-toggle')), findsOneWidget);
  });

  testWidgets('no split toggle on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
        overrides: [_verdantOverride, _emulatorOverride],
        child: MaterialApp(home: HomeShell(oracle: _oracle()))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('split-toggle')), findsNothing);
  });
```

- [ ] **Step 3:** Run `flutter test test/home_shell_test.dart` → PASS. (If the wide test can't find
  `JournalScreen` because the journal is offstage, confirm the split branch actually renders it; the
  IndexedStack `MapsTab` is index-selected so it mounts.)
- [ ] **Step 4:** Commit: `test(shell): split-view widget tests (wide shows both panes; narrow hides toggle)`.

---

### Task 4: Full verification + ship

- [ ] **Step 1:** `dart analyze` → No issues.
- [ ] **Step 2:** `flutter test` → all green (≥ 776 + new).
- [ ] **Step 3:** Web-verify: `flutter build web --debug`; `preview_start`; `preview_resize` to a wide
  viewport (e.g. 1400×900); screenshot to confirm the split toggle appears, toggling shows Maps +
  Journal side by side; resize narrow to confirm single-pane. Stop the server.
- [ ] **Step 4:** Reviewer pass (`caveman:cavecrew-reviewer`) on `git diff main..HEAD`; address findings.
- [ ] **Step 5:** Push, PR, watch CI, squash-merge, delete branch, sync `main`.

---

## Self-review notes
- `splitViewProvider` persisted global (mirrors `rulesetsProvider`); toggle flips + writes.
- Split renders only when `split && maxWidth >= 1000`; below that it silently falls back to the
  existing single-pane layout (toggle state preserved).
- Journal dropped from the split rail (it's pinned right); `leftIndex` clamps a Journal/!left route
  to index 0 = Maps, so the split opens on Maps.
- Split `IndexedStack` carries no `_bodyKey` (avoids GlobalKey reuse across the two layouts).
- Drag updates transient `_journalWidth` clamped to [320, 60%]; not persisted (v1).
- Toggle visibility uses `MediaQuery.sizeOf` width; the actual split uses `LayoutBuilder` maxWidth —
  same ~1000 threshold, same full-width body, so they agree.
