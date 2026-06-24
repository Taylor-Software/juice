# Scene Descriptions + Flesh-Out Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give scenes a visible, editable description and an aiReady-gated "flesh out" that AI-appends to it — extending the generic `fleshOut` seam to scenes.

**Architecture:** Extract the shared Append/Cancel review dialog; render the scene `body` in the journal divider + scenes-pane row; add a manual scene-edit dialog and a flesh-out button to each scenes-pane row (reusing `buildFleshOutSeed` + `fleshOut` + the extracted `showFleshOutReview`).

**Tech Stack:** Dart, Flutter, flutter_riverpod, flutter_test. Reuses `buildFleshOutSeed` (play_context), `fleshOut`/`interpreterServiceProvider`, `aiReadyProvider`, `JournalNotifier.replace`, `JournalEntry.copyWith(title:/body:)`.

---

## File Structure

- **Create** `lib/features/flesh_out_review.dart` — `showFleshOutReview` (moved from map_screen).
- **Modify** `lib/features/map_screen.dart` — drop the local `showFleshOutReview`, import the new file.
- **Modify** `lib/features/journal_screen.dart` — render the scene `body` under the scene divider.
- **Modify** `lib/features/scenes_pane.dart` — body in the row subtitle + `_SceneEditDialog` + `_editScene` + `_fleshOutScene` + the per-row edit + flesh-out buttons.
- **Test** `test/scene_description_test.dart` (new) — journal render, row render, edit, flesh-out, hidden-when-off.

**Note for UI tasks:** add imports as `flutter analyze` requires — `interpreterServiceProvider` is in `state/interpreter.dart`, `showFleshOutReview` in the new `flesh_out_review.dart`; `buildFleshOutSeed`/`aiReadyProvider`/`journalProvider` are already imported by `scenes_pane.dart` (via `play_context.dart` / `providers.dart`).

---

## Task 1: Extract the shared review dialog

**Files:**
- Create: `lib/features/flesh_out_review.dart`
- Modify: `lib/features/map_screen.dart`

- [ ] **Step 1: Create the new file** `lib/features/flesh_out_review.dart`:

```dart
import 'package:flutter/material.dart';

/// Append/Cancel review for an AI-generated flesh-out. Returns true on Append.
/// Shared by the map (room/hex), scenes, and any future flesh-out surface.
Future<bool> showFleshOutReview(BuildContext context, String generated) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      key: const Key('flesh-out-review'),
      title: const Text('Flesh out'),
      content: SingleChildScrollView(child: Text(generated)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
          key: const Key('flesh-out-append'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Append'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
```

- [ ] **Step 2: Remove the local copy from `map_screen.dart`** — delete the top-level `Future<bool> showFleshOutReview(...) { … }` function (the whole block) and add the import near the other relative imports:

```dart
import 'flesh_out_review.dart';
```

- [ ] **Step 3: Verify the move is behavior-preserving**

Run: `flutter analyze lib/features/map_screen.dart lib/features/flesh_out_review.dart`
Expected: `No issues found!`
Run: `flutter test test/flesh_out_test.dart`
Expected: PASS — the existing room + hex flesh-out tests still tap `flesh-out-append` (same key, now from the imported function).

- [ ] **Step 4: Commit**

```bash
git add lib/features/flesh_out_review.dart lib/features/map_screen.dart
git commit -m "refactor(ai): extract showFleshOutReview into a shared file

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Render the scene description

**Files:**
- Modify: `lib/features/journal_screen.dart`, `lib/features/scenes_pane.dart`
- Test: `test/scene_description_test.dart` (new)

- [ ] **Step 1: Write the failing tests** — create `test/scene_description_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/features/scenes_pane.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Oracle _oracle() => Oracle(
    OracleData(jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>),
    Dice(Random(1)));

void main() {
  testWidgets('journal renders a scene body when present', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default':
          '[{"id":"s1","timestamp":"2026-06-12T10:00:00.000","title":"At the gate","body":"A cold mist clings.","kind":"scene"}]',
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [oracleProvider.overrideWith((ref) async => _oracle())],
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: JournalScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scene-body-s1')), findsOneWidget);
    expect(find.text('A cold mist clings.'), findsOneWidget);
  });

  testWidgets('scenes pane shows the description in the row', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    final id = await c.read(journalProvider.notifier).addScene('At the gate');
    final scene = c
        .read(journalProvider)
        .value!
        .firstWhere((e) => e.id == id);
    await c
        .read(journalProvider.notifier)
        .replace(scene.copyWith(body: 'A cold mist clings.'));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ScenesPane())),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('A cold mist clings.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/scene_description_test.dart`
Expected: FAIL — no `scene-body-s1`; the row shows no body.

- [ ] **Step 3a: Render in the journal** — in `lib/features/journal_screen.dart`, the `case JournalKind.scene:` currently returns `Padding(... child: Row([Divider, title, chaos, Divider, menu]))`. Wrap the `Row` in a `Column` and append the body. Replace the `return Padding(...)` for that case with:

```dart
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(e.title, style: theme.textTheme.titleSmall),
                  ),
                  if (e.chaosFactor != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        label: Text('Chaos ${e.chaosFactor}'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  const Expanded(child: Divider()),
                  menu,
                ],
              ),
              if (e.body.trim().isNotEmpty)
                Padding(
                  key: Key('scene-body-${e.id}'),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(e.body, style: theme.textTheme.bodyMedium),
                ),
            ],
          ),
        );
```

- [ ] **Step 3b: Render in the scenes pane** — in `lib/features/scenes_pane.dart`, change the row's `subtitle` from the chaos-only Text to chaos + body:

```dart
                        subtitle: (s.chaosFactor != null ||
                                s.body.trim().isNotEmpty)
                            ? Text([
                                if (s.chaosFactor != null) 'Chaos ${s.chaosFactor}',
                                if (s.body.trim().isNotEmpty) s.body.trim(),
                              ].join('\n'))
                            : null,
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/scene_description_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/journal_screen.dart lib/features/scenes_pane.dart test/scene_description_test.dart
git commit -m "feat: render the scene description (journal divider + scenes-pane row)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Scene edit + flesh-out (scenes pane)

**Files:**
- Modify: `lib/features/scenes_pane.dart`
- Test: `test/scene_description_test.dart`

- [ ] **Step 1: Add the failing tests** — append to `void main()` in `test/scene_description_test.dart`:

```dart
  Future<ProviderContainer> pumpScenes(WidgetTester tester,
      {required bool aiReady}) async {
    SharedPreferences.setMockInitialValues(
        {if (aiReady) 'juice.ai_enabled.v1': true});
    final fake = FakeInterpreterService(
        initial: InterpreterStatus(
            aiReady ? InterpreterPhase.ready : InterpreterPhase.unsupported));
    final c = ProviderContainer(
        overrides: [interpreterServiceProvider.overrideWithValue(fake)]);
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    await c.read(journalProvider.notifier).addScene('At the gate');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ScenesPane())),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('flesh-out appends generated detail to the scene body',
      (tester) async {
    final c = await pumpScenes(tester, aiReady: true);
    final id = c.read(journalProvider).value!.first.id;
    await tester.tap(find.byKey(Key('flesh-out-scene-$id')));
    await tester.pumpAndSettle(); // fleshOut() + review dialog
    await tester.tap(find.byKey(const Key('flesh-out-append')));
    await tester.pumpAndSettle();
    final scene = c.read(journalProvider).value!.firstWhere((e) => e.id == id);
    expect(scene.body, contains('Fleshed-out detail.'));
  });

  testWidgets('flesh-out button hidden when AI not ready', (tester) async {
    final c = await pumpScenes(tester, aiReady: false);
    final id = c.read(journalProvider).value!.first.id;
    expect(find.byKey(Key('flesh-out-scene-$id')), findsNothing);
  });

  testWidgets('manual edit sets the scene description', (tester) async {
    final c = await pumpScenes(tester, aiReady: false);
    final id = c.read(journalProvider).value!.first.id;
    await tester.tap(find.byKey(Key('scene-edit-$id')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('scene-edit-body')), 'Hand-written detail.');
    await tester.tap(find.byKey(const Key('scene-edit-save')));
    await tester.pumpAndSettle();
    final scene = c.read(journalProvider).value!.firstWhere((e) => e.id == id);
    expect(scene.body, 'Hand-written detail.');
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/scene_description_test.dart`
Expected: FAIL — no `flesh-out-scene-<id>` / `scene-edit-<id>` widgets.

- [ ] **Step 3a: Add imports** to `lib/features/scenes_pane.dart`:

```dart
import '../state/interpreter.dart';
import 'flesh_out_review.dart';
```

- [ ] **Step 3b: Add the per-row buttons** — in `scenes_pane.dart`, give the scene `ListTile` a `trailing` Row (the row currently has no trailing):

```dart
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: Key('scene-edit-${s.id}'),
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit scene',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _editScene(context, ref, s),
                            ),
                            if (ref.watch(aiReadyProvider))
                              IconButton(
                                key: Key('flesh-out-scene-${s.id}'),
                                icon: const Icon(Icons.auto_fix_high_outlined),
                                tooltip: 'Flesh out (AI)',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _fleshOutScene(context, ref, s),
                              ),
                          ],
                        ),
```

- [ ] **Step 3c: Add the methods** — in the `ScenesPane` class (beside `_newScene`):

```dart
  Future<void> _editScene(
      BuildContext context, WidgetRef ref, JournalEntry s) async {
    final result = await showDialog<({String title, String body})>(
      context: context,
      builder: (_) => _SceneEditDialog(initialTitle: s.title, initialBody: s.body),
    );
    if (result == null || result.title.trim().isEmpty) return;
    await ref.read(journalProvider.notifier).replace(
        s.copyWith(title: result.title.trim(), body: result.body.trim()));
  }

  Future<void> _fleshOutScene(
      BuildContext context, WidgetRef ref, JournalEntry s) async {
    final seed = buildFleshOutSeed(ref,
        entityKind: 'scene', name: s.title, existingDetail: s.body);
    final String detail;
    try {
      detail = await ref.read(interpreterServiceProvider).fleshOut(seed);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Flesh out failed: $e')));
      }
      return;
    }
    if (!context.mounted) return;
    if (await showFleshOutReview(context, detail) != true) return;
    final body =
        [s.body, detail].where((t) => t.trim().isNotEmpty).join('\n\n');
    await ref.read(journalProvider.notifier).replace(s.copyWith(body: body));
  }
```

- [ ] **Step 3d: Add the dialog** — at the end of `scenes_pane.dart` (after `_NewSceneDialog`):

```dart
/// Edit a scene's title + free-text description. Pops `({title, body})` or null.
class _SceneEditDialog extends StatefulWidget {
  const _SceneEditDialog({required this.initialTitle, required this.initialBody});
  final String initialTitle;
  final String initialBody;

  @override
  State<_SceneEditDialog> createState() => _SceneEditDialogState();
}

class _SceneEditDialogState extends State<_SceneEditDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.initialTitle);
  late final TextEditingController _body =
      TextEditingController(text: widget.initialBody);

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit scene'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('scene-edit-title'),
            controller: _title,
            decoration: const InputDecoration(labelText: 'Scene title'),
          ),
          TextField(
            key: const Key('scene-edit-body'),
            controller: _body,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          key: const Key('scene-edit-save'),
          onPressed: () =>
              Navigator.pop(context, (title: _title.text, body: _body.text)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/scene_description_test.dart`
Expected: PASS (all five tests).

- [ ] **Step 5: Full verification**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test` → expect All tests passed.

- [ ] **Step 6: Commit**

```bash
git add lib/features/scenes_pane.dart test/scene_description_test.dart
git commit -m "feat(ai): scene edit + flesh-out in the scenes pane

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Doc sync — CLAUDE.md

**Files:** Modify `CLAUDE.md` (the AI expansion #4 note).

- [ ] **Step 1: Append a scene-extension sentence** — in `CLAUDE.md`, find the "AI expansion #4 (flesh out an entity)" paragraph (ends "`MapNotifier.appendSiteLine` mirrors `appendRoomDetail`. See `…flesh-out-entity-design.md`. Deferred AI affordance: LLM-ranked suggestion chips (#5)." — note #5 has since shipped, so it now ends with the #5 paragraph). Locate the #4 paragraph's `appendRoomDetail` sentence and append after the #4 spec reference:

```
  **Scene descriptions (flesh-out #4 extended to scenes):** scene journal
  entries (`JournalKind.scene`, previously a title+chaos divider with an
  always-empty unrendered `body`) now carry a visible, editable description —
  rendered under the journal scene divider (`scene-body-<id>`) and in the
  scenes-pane row subtitle. The scenes pane gained a per-row manual edit
  (`scene-edit-<id>` → `_SceneEditDialog` title+description → `replace`) and an
  aiReady-gated `flesh-out-scene-<id>` (generic `fleshOut` with
  `entityKind: 'scene'` → `showFleshOutReview` → append to `body`). The
  Append/Cancel review dialog `showFleshOutReview` was extracted to the shared
  `lib/features/flesh_out_review.dart` (now used by room/hex/scene). See
  `docs/superpowers/specs/2026-06-24-scene-description-flesh-out-design.md`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note scene descriptions + flesh-out in CLAUDE.md

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 extract `showFleshOutReview` → Task 1. ✓
- §2 visible scene body (journal divider + scenes-pane row) → Task 2. ✓
- §3 manual edit (`_SceneEditDialog` + `_editScene` + `scene-edit-<id>`) → Task 3. ✓
- §4 flesh-out scene (`_fleshOutScene` + `flesh-out-scene-<id>`, aiReady-gated, review→append) → Task 3. ✓
- Testing (journal render, row render, flesh-out append, hidden-when-off, manual edit) → Tasks 2, 3. ✓
- Doc → Task 4. ✓

**Type consistency:**
- `_SceneEditDialog({initialTitle, initialBody})` returns `({String title, String body})` — defined Task 3 Step 3d, consumed Task 3 Step 3c `_editScene`. ✓
- `_editScene`/`_fleshOutScene(context, ref, JournalEntry s)` — defined Step 3c, called from the buttons Step 3b. ✓
- `buildFleshOutSeed(ref, entityKind:, name:, existingDetail:)` matches the existing #4 signature. ✓
- `showFleshOutReview(context, generated) -> Future<bool>` — Task 1 definition, Task 3 call. ✓
- Keys `scene-body-<id>` / `scene-edit-<id>` / `scene-edit-title`/`-body`/`-save` / `flesh-out-scene-<id>` / `flesh-out-append` consistent between impl + tests. ✓
- Fake default `'Fleshed-out detail.'` ↔ asserted in Task 3. ✓

**Placeholder scan:** No TBD/TODO; complete code per step. ✓

**Risk notes:**
- The journal render test pumps `JournalScreen` with only the `oracleProvider` override + mock prefs (mirrors the proven `recap_test` harness — the default no-systems campaign doesn't trigger the verdant/ruleset/emulator loads that would hang).
- `ScenesPane` is a `ConsumerWidget` (no `State.mounted`), so `_fleshOutScene` uses `context.mounted` (matches the #4 thread entry point).
- Task 2 and Task 3 both edit the scene `ListTile` (subtitle vs trailing) — run sequentially; no overlap in the lines touched.
