# Flesh Out An Entity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A one-tap AI "flesh out" affordance that expands a thin entity (roster character, thread, dungeon room, world hex site) into concrete detail, grounded in the #1 campaign context.

**Architecture:** One generic `fleshOut` seam (`FleshOutSeed`/`buildFleshOutPrompt`) reusing the #1 grounding + the stateless `_generate`; a pure `fleshOutSeedFrom` assembler (name-query recall) with a thin `buildFleshOutSeed(ref)` wrapper; four aiReady-gated entry points that append generated detail after a review step.

**Tech Stack:** Dart, Flutter, flutter_riverpod, flutter_test. Reuses `_flat`/`_capped`/`_stripThink`/`kRecallMaxEntries`/`kRecallMaxChars`/`searchEntries`, `aiReadyProvider`/`interpreterServiceProvider`/`systemPrimerProvider`/`journalProvider`, `_EditDialog`, `appendRoomDetail`.

---

## File Structure

- **Modify** `lib/engine/oracle_interpreter.dart` — `FleshOutSeed`, `buildFleshOutPrompt`, `parseFleshOutResponse`.
- **Modify** `lib/state/interpreter.dart` — `fleshOut` on the interface.
- **Modify** `lib/state/interpreter_gemma.dart` — `fleshOut` impl.
- **Modify** `lib/state/play_context.dart` — `fleshOutSeedFrom` (pure) + `buildFleshOutSeed` (wrapper).
- **Modify** `lib/state/providers.dart` — `appendSiteLine` on `MapNotifier`.
- **Modify** `test/fake_interpreter.dart` — `fleshOut` fake.
- **Modify** `lib/features/tracker_screen.dart` — character + thread entry points.
- **Modify** `lib/features/map_screen.dart` — room + hex entry points + `showFleshOutReview`.
- **Test** `test/oracle_interpreter_test.dart`, `test/flesh_out_seed_test.dart` (new), `test/flesh_out_test.dart` (new).

**Notes for all UI tasks:** add imports as `flutter analyze` requires — `aiReadyProvider`/`appendSiteLine` live in `state/providers.dart`, `interpreterServiceProvider` in `state/interpreter.dart`, `buildFleshOutSeed` in `state/play_context.dart`, `FleshOutSeed` in `engine/oracle_interpreter.dart`.

**SharedPreferences mock-key quirk:** this codebase is inconsistent — the map key is stored **with** the `flutter.` prefix (`flutter.juice.map.v1.default`), while `juice.sessions.v1` / `juice.ai_enabled.v1` are **unprefixed**. Mirror the exact format each sibling test uses (shown in the test code below). If `aiReady` doesn't engage in a map test, re-check the `ai_enabled` key.

---

## Task 1: Seam — FleshOutSeed + buildFleshOutPrompt

**Files:** Modify `lib/engine/oracle_interpreter.dart`; Test `test/oracle_interpreter_test.dart`.

- [ ] **Step 1: Write the failing test** — add inside `void main()` in `test/oracle_interpreter_test.dart`:

```dart
  group('buildFleshOutPrompt', () {
    test('renders instruction + grounding + name/existing + Detail cue', () {
      final p = buildFleshOutPrompt(const FleshOutSeed(
        entityKind: 'NPC',
        name: 'Sister Vane',
        existingDetail: 'A grim cleric.',
        systemPrimer: 'Ironsworn: perilous Iron Lands.',
        sceneTitle: 'The crypt',
        journalContext: ['Sister Vane barred the door.'],
      ));
      expect(p, contains('Flesh out the following NPC'));
      expect(p, contains('system: Ironsworn'));
      expect(p, contains('scene: The crypt'));
      expect(p, contains('recall: Sister Vane barred the door.'));
      expect(p, contains('name: Sister Vane'));
      expect(p, contains('existing: A grim cleric.'));
      expect(p.trimRight(), endsWith('Detail:'));
    });

    test('omits the existing line + empty grounding', () {
      final p = buildFleshOutPrompt(
          const FleshOutSeed(entityKind: 'location', name: 'The Old Mill'));
      expect(p, contains('Flesh out the following location'));
      expect(p, isNot(contains('existing:')));
      expect(p, isNot(contains('system:')));
      expect(p.trimRight(), endsWith('Detail:'));
    });

    test('parseFleshOutResponse strips think + throws on empty', () {
      expect(parseFleshOutResponse('<think>x</think> A damp vault. '),
          'A damp vault.');
      expect(() => parseFleshOutResponse('   '), throwsFormatException);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/oracle_interpreter_test.dart`
Expected: FAIL — `FleshOutSeed`/`buildFleshOutPrompt`/`parseFleshOutResponse` undefined.

- [ ] **Step 3: Implement** — in `lib/engine/oracle_interpreter.dart`, after the GM-narration section (after `parseNarrateResponse`), add:

```dart
// -- Flesh out an entity ------------------------------------------------------

class FleshOutSeed {
  const FleshOutSeed({
    required this.entityKind,
    required this.name,
    this.existingDetail = '',
    this.systemPrimer = '',
    this.sceneTitle,
    this.journalContext = const [],
  });

  /// Human label for the prompt, e.g. 'NPC' / 'story thread' / 'location'.
  final String entityKind;
  final String name;
  final String existingDetail;
  final String systemPrimer;
  final String? sceneTitle;
  final List<String> journalContext;
}

/// A fixed instruction + the #1 grounding (system/scene/recall via the shared
/// helpers) + name/existing lines + a trailing `Detail:` cue. Caps mirror
/// [buildAskGmPrompt].
String buildFleshOutPrompt(FleshOutSeed seed) {
  final primer = _flat(seed.systemPrimer);
  final systemLine = primer.isEmpty ? '' : 'system: ${_capped(primer)}\n';
  final scene = seed.sceneTitle;
  final sceneLine = (scene == null || scene.trim().isEmpty)
      ? ''
      : 'scene: ${_capped(_flat(scene))}\n';
  final recall = StringBuffer();
  for (final context in seed.journalContext.take(kRecallMaxEntries)) {
    final f = _flat(context);
    if (f.isEmpty) continue;
    final cut =
        f.length > kRecallMaxChars ? '${f.substring(0, kRecallMaxChars)}…' : f;
    recall.write('recall: $cut\n');
  }
  final existing = _flat(seed.existingDetail);
  final existingLine =
      existing.isEmpty ? '' : 'existing: ${_capped(existing)}\n';
  return 'You are the game master for a solo tabletop RPG. Flesh out the '
      'following ${seed.entityKind} with 2-4 sentences of vivid, concrete '
      'detail consistent with the established facts. Build on any existing '
      'notes — do not contradict them. Output only the description — no '
      'preamble, no headers, no lists.\n\n'
      'INPUT:\n'
      '$systemLine'
      '$sceneLine'
      '$recall'
      'name: ${_capped(_flat(seed.name))}\n'
      '$existingLine'
      'Detail:';
}

/// Plain-text parse (like parseNarrateResponse): strip think, trim, throw empty.
String parseFleshOutResponse(String raw) {
  final out = _stripThink(raw).trim();
  if (out.isEmpty) throw const FormatException('Empty flesh-out response');
  return out;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/oracle_interpreter_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle_interpreter.dart test/oracle_interpreter_test.dart
git commit -m "feat(ai): fleshOut seam — FleshOutSeed + buildFleshOutPrompt

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Interface + impls (fleshOut)

**Files:** Modify `lib/state/interpreter.dart`, `lib/state/interpreter_gemma.dart`, `test/fake_interpreter.dart`.

- [ ] **Step 1: Interface** — in `lib/state/interpreter.dart`, in `abstract class InterpreterService`, after the `narrate` declaration add:

```dart
  /// Flesh out an entity (NPC / thread / location) into richer detail (plain
  /// text). Same readiness contract as the other seams. Requires ready.
  Future<String> fleshOut(FleshOutSeed seed);
```

- [ ] **Step 2: Gemma impl** — in `lib/state/interpreter_gemma.dart`, after the `narrate` override add:

```dart
  @override
  Future<String> fleshOut(FleshOutSeed seed) async {
    return parseFleshOutResponse(await _generate(buildFleshOutPrompt(seed)));
  }
```

- [ ] **Step 3: Fake impl** — in `test/fake_interpreter.dart`, beside the narrate fake fields add:

```dart
  final List<String> queuedFleshOut = [];
  FleshOutSeed? lastFleshOutSeed;
  int fleshOutCalls = 0;
  Object? fleshOutError;
```

and beside the `narrate` override add:

```dart
  @override
  Future<String> fleshOut(FleshOutSeed seed) async {
    lastFleshOutSeed = seed;
    fleshOutCalls++;
    if (fleshOutError != null) throw fleshOutError!;
    if (queuedFleshOut.isEmpty) return 'Fleshed-out detail.';
    return queuedFleshOut.removeAt(0);
  }
```

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/state/interpreter.dart lib/state/interpreter_gemma.dart test/fake_interpreter.dart` → expect no issues.
Run: `flutter test test/oracle_interpreter_test.dart` → expect PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/interpreter.dart lib/state/interpreter_gemma.dart test/fake_interpreter.dart
git commit -m "feat(ai): fleshOut on InterpreterService (+ Gemma + fake)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Seed assembler (pure + wrapper)

**Files:** Modify `lib/state/play_context.dart`; Test `test/flesh_out_seed_test.dart`.

- [ ] **Step 1: Write the failing test** — create `test/flesh_out_seed_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/play_context.dart';

JournalEntry _e(String id, String title, String body, String kind) =>
    JournalEntry.fromJson({
      'id': id,
      'timestamp': '2026-06-12T10:00:00.000',
      'title': title,
      'body': body,
      'kind': kind,
    });

void main() {
  test('fleshOutSeedFrom: name recall + newest scene + primer passthrough', () {
    // journal is newest-first
    final journal = [
      _e('3', 'Scene Two', 'A new place', 'scene'),
      _e('2', 'Vane speaks', 'Sister Vane warns the party', 'text'),
      _e('1', 'Scene One', 'The crypt', 'scene'),
    ];
    final seed = fleshOutSeedFrom(
      entityKind: 'NPC',
      name: 'Vane',
      existingDetail: 'grim',
      systemPrimer: 'Ironsworn',
      activeCharacter: 'Taurin (PC)',
      journal: journal,
    );
    expect(seed.entityKind, 'NPC');
    expect(seed.name, 'Vane');
    expect(seed.existingDetail, 'grim');
    expect(seed.systemPrimer, 'Ironsworn');
    expect(seed.activeCharacter, 'Taurin (PC)');
    expect(seed.sceneTitle, 'Scene Two'); // newest scene's title
    expect(seed.journalContext.any((l) => l.contains('Vane')), isTrue);
  });

  test('fleshOutSeedFrom: empty journal -> null scene + empty context', () {
    final seed = fleshOutSeedFrom(
      entityKind: 'location',
      name: 'Mill',
      existingDetail: '',
      systemPrimer: '',
      activeCharacter: '',
      journal: const [],
    );
    expect(seed.sceneTitle, isNull);
    expect(seed.journalContext, isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/flesh_out_seed_test.dart`
Expected: FAIL — `fleshOutSeedFrom` undefined.

- [ ] **Step 3: Implement** — in `lib/state/play_context.dart`:

(a) add the import (with the other engine imports):

```dart
import '../engine/journal_search.dart';
```

(b) at the end of the file add:

```dart
/// Pure: assemble a [FleshOutSeed] from already-read campaign state.
/// `sceneTitle` = the newest scene entry's title (journal is newest-first);
/// `journalContext` = entries mentioning [name] by text (name-query recall).
FleshOutSeed fleshOutSeedFrom({
  required String entityKind,
  required String name,
  required String existingDetail,
  required String systemPrimer,
  required String activeCharacter,
  required List<JournalEntry> journal,
}) {
  final sceneTitle = journal
      .where((e) => e.kind == JournalKind.scene && e.title.trim().isNotEmpty)
      .map((e) => e.title)
      .firstOrNull;
  final related = searchEntries(journal, name)
      .take(kRecallMaxEntries)
      .map((e) => e.title.isEmpty ? e.body : '${e.title}: ${e.body}')
      .toList();
  return FleshOutSeed(
    entityKind: entityKind,
    name: name,
    existingDetail: existingDetail,
    systemPrimer: systemPrimer,
    activeCharacter: activeCharacter,
    sceneTitle: sceneTitle,
    journalContext: related,
  );
}

/// Wrapper for widgets: read the providers, delegate to [fleshOutSeedFrom].
FleshOutSeed buildFleshOutSeed(
  WidgetRef ref, {
  required String entityKind,
  required String name,
  required String existingDetail,
}) =>
    fleshOutSeedFrom(
      entityKind: entityKind,
      name: name,
      existingDetail: existingDetail,
      systemPrimer: ref.read(systemPrimerProvider),
      activeCharacter: ref.read(activeCharacterLineProvider),
      journal: ref.read(journalProvider).valueOrNull ?? const [],
    );
```

(`firstOrNull` is already used elsewhere in the codebase; if analyze flags it here, add `import 'package:collection/collection.dart';`.)

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/flesh_out_seed_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/play_context.dart test/flesh_out_seed_test.dart
git commit -m "feat(ai): fleshOutSeedFrom assembler (name-query recall) + ref wrapper

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Character entry point

**Files:** Modify `lib/features/tracker_screen.dart`; Test `test/flesh_out_test.dart` (new — created here, extended in Tasks 5-6).

- [ ] **Step 1: Write the failing test** — create `test/flesh_out_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/tracker_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

FakeInterpreterService _fake() =>
    FakeInterpreterService(initial: const InterpreterStatus(InterpreterPhase.ready));

Future<ProviderContainer> _pumpCharacters(
    WidgetTester tester, FakeInterpreterService fake) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default':
        '[{"id":"c1","name":"Ash","note":"A scout.","stats":[],"tracks":[],"tags":[],"role":"npc"}]',
    'juice.ai_enabled.v1': true,
  });
  await tester.pumpWidget(ProviderScope(
    overrides: [interpreterServiceProvider.overrideWithValue(fake)],
    child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: CharactersPane())),
  ));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(CharactersPane)));
}

void main() {
  testWidgets('character flesh-out appends detail to the note', (tester) async {
    final c = await _pumpCharacters(tester, _fake());
    await tester.tap(find.text('Ash')); // open the sheet
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('flesh-out-character')));
    await tester.pumpAndSettle(); // fleshOut() + the _EditDialog
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final chars = c.read(charactersProvider).valueOrNull!;
    expect(chars.single.note, contains('A scout.')); // preserved
    expect(chars.single.note, contains('Fleshed-out detail.')); // appended
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/flesh_out_test.dart`
Expected: FAIL — no `flesh-out-character` widget.

- [ ] **Step 3: Implement** — in `lib/features/tracker_screen.dart`, in `CharactersPaneState`:

(a) add the method (right after `_editNameNote`):

```dart
  Future<void> _fleshOutCharacter(BuildContext context, Character c) async {
    final seed = buildFleshOutSeed(ref,
        entityKind: c.role == CharacterRole.npc ? 'NPC' : 'character',
        name: c.name,
        existingDetail: c.note);
    final String detail;
    try {
      detail = await ref.read(interpreterServiceProvider).fleshOut(seed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Flesh out failed: $e')));
      }
      return;
    }
    if (!mounted) return;
    final note =
        [c.note, detail].where((s) => s.trim().isNotEmpty).join('\n\n');
    final result = await showDialog<({String title, String note})>(
      context: context,
      builder: (_) => _EditDialog(
        heading: 'Flesh out — ${c.name}',
        labelA: 'Name',
        labelB: 'Note',
        initialA: c.name,
        initialB: note,
      ),
    );
    if (result == null || result.title.trim().isEmpty) return;
    await ref.read(charactersProvider.notifier).replace(
        c.copyWith(name: result.title.trim(), note: result.note.trim()));
  }
```

(b) in `_buildSheet`, beside the "Edit name & notes" `IconButton` (the one with `onPressed: () => _editNameNote(context, c)`), add before/after it:

```dart
            if (ref.watch(aiReadyProvider))
              IconButton(
                key: const Key('flesh-out-character'),
                icon: const Icon(Icons.auto_fix_high_outlined),
                tooltip: 'Flesh out (AI)',
                onPressed: () => _fleshOutCharacter(context, c),
              ),
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/flesh_out_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/tracker_screen.dart test/flesh_out_test.dart
git commit -m "feat(ai): flesh-out character (roster sheet)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: Thread entry point

**Files:** Modify `lib/features/tracker_screen.dart`; Test `test/flesh_out_test.dart`.

- [ ] **Step 1: Add the failing test** — append to `void main()` in `test/flesh_out_test.dart`:

```dart
  testWidgets('thread flesh-out appends detail to the note', (tester) async {
    final fake = _fake();
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.threads.v1.default':
          '[{"id":"t1","title":"Find the Relic","note":"Rumored lost.","open":true}]',
      'juice.ai_enabled.v1': true,
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ThreadsPane())),
    ));
    await tester.pumpAndSettle();
    final c =
        ProviderScope.containerOf(tester.element(find.byType(ThreadsPane)));
    await tester.tap(find.byKey(const Key('flesh-out-thread-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final threads = c.read(threadsProvider).valueOrNull!;
    expect(threads.single.note, contains('Rumored lost.'));
    expect(threads.single.note, contains('Fleshed-out detail.'));
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/flesh_out_test.dart`
Expected: FAIL — no `flesh-out-thread-t1` widget.

- [ ] **Step 3: Implement** — in `lib/features/tracker_screen.dart`, in `ThreadsPane`:

(a) add the method (after `_editThread`):

```dart
  Future<void> _fleshOutThread(
      BuildContext context, WidgetRef ref, Thread t) async {
    final seed = buildFleshOutSeed(ref,
        entityKind: 'story thread', name: t.title, existingDetail: t.note);
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
    final note =
        [t.note, detail].where((s) => s.trim().isNotEmpty).join('\n\n');
    final result = await showDialog<({String title, String note})>(
      context: context,
      builder: (_) => _EditDialog(
        heading: 'Flesh out — ${t.title}',
        labelA: 'Title',
        labelB: 'Note',
        initialA: t.title,
        initialB: note,
      ),
    );
    if (result == null || result.title.trim().isEmpty) return;
    await ref.read(threadsProvider.notifier).replace(
        t.copyWith(title: result.title.trim(), note: result.note.trim()));
  }
```

(b) in the thread row's trailing `Row` (the one with the pin + delete `IconButton`s), add as the first child:

```dart
                      if (ref.watch(aiReadyProvider))
                        IconButton(
                          key: Key('flesh-out-thread-${t.id}'),
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.auto_fix_high_outlined),
                          tooltip: 'Flesh out (AI)',
                          onPressed: () => _fleshOutThread(context, ref, t),
                        ),
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/flesh_out_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/tracker_screen.dart test/flesh_out_test.dart
git commit -m "feat(ai): flesh-out thread (Threads pane)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 6: Room + Hex entry points (+ appendSiteLine + review dialog)

**Files:** Modify `lib/state/providers.dart`, `lib/features/map_screen.dart`; Test `test/flesh_out_test.dart`.

- [ ] **Step 1: Add the failing tests** — append to `void main()` in `test/flesh_out_test.dart`. First add these imports at the top of the file:

```dart
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/map_screen.dart';
```

and these helpers (above `void main()`):

```dart
Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));
HexcrawlData _hexData() => HexcrawlData(
    jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
        as Map<String, dynamic>);

class _FixedSessions extends SessionsNotifier {
  _FixedSessions(this.systems);
  final List<String> systems;
  @override
  Future<SessionsState> build() async => SessionsState(
        active: 'default',
        sessions: [SessionMeta(id: 'default', name: 'M', systems: systems)],
      );
}
```

and the tests:

```dart
  testWidgets('room flesh-out appends to room.detail after Append',
      (tester) async {
    final fake = _fake();
    const seeded = MapState(
      rooms: [DungeonRoom(id: 'r1', x: 0, y: 0, title: 'Crypt', detail: 'Dim.')],
      currentRoomId: 'r1',
    );
    SharedPreferences.setMockInitialValues({
      'flutter.juice.map.v1.default': jsonEncode(seeded.toJson()),
      'juice.ai_enabled.v1': true,
    });
    final c = ProviderContainer(overrides: [
      hexcrawlDataProvider.overrideWith((ref) async => _hexData()),
      sessionsProvider.overrideWith(() => _FixedSessions(['juice', 'hexcrawl'])),
      interpreterServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: Scaffold(body: DungeonMapPane(oracle: _oracle()))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('flesh-out-room')));
    await tester.pumpAndSettle(); // fleshOut() + review dialog
    await tester.tap(find.byKey(const Key('flesh-out-append')));
    await tester.pumpAndSettle();
    final s = await c.read(mapProvider.future);
    expect(s.rooms.single.detail, contains('Dim.'));
    expect(s.rooms.single.detail, contains('Fleshed-out detail.'));
  });

  testWidgets('hex-site flesh-out appends a siteLine after Append',
      (tester) async {
    final fake = _fake();
    const seeded = MapState(
      hexes: [
        HexCell(col: 0, row: 0, envRow: 1, terrain: 'hills', site: 'Cave')
      ],
      currentHexCol: 0,
      currentHexRow: 0,
    );
    SharedPreferences.setMockInitialValues({
      'flutter.juice.map.v1.default': jsonEncode(seeded.toJson()),
      'juice.ai_enabled.v1': true,
    });
    final c = ProviderContainer(overrides: [
      hexcrawlDataProvider.overrideWith((ref) async => _hexData()),
      sessionsProvider.overrideWith(() => _FixedSessions(['juice', 'hexcrawl'])),
      interpreterServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: Scaffold(body: HexMapPane(oracle: _oracle()))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('flesh-out-site')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('flesh-out-append')));
    await tester.pumpAndSettle();
    final s = await c.read(mapProvider.future);
    expect(s.hexes.single.siteLines, contains('Fleshed-out detail.'));
  });
```

> If `flesh-out-room`'s card isn't visible (the dungeon pane didn't auto-select `r1`), add `await tester.tap(find.text('Crypt'));` + `pumpAndSettle()` before tapping the button. Verify by reading what `DungeonMapPane` renders for `currentRoomId`.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/flesh_out_test.dart`
Expected: FAIL — `appendSiteLine` undefined and/or no `flesh-out-room`/`flesh-out-site` widgets.

- [ ] **Step 3a: Implement `appendSiteLine`** — in `lib/state/providers.dart`, in `MapNotifier`, after `appendRoomDetail` add:

```dart
  /// Append an arbitrary line to a hex site's writeup (AI flesh-out). No-op if
  /// the hex is absent or has no site.
  Future<void> appendSiteLine(int col, int row, String text) async {
    await _updateHex(col, row, (h) {
      if (h.site == null) return null;
      return h.copyWith(siteLines: [...h.siteLines, text]);
    });
  }
```

- [ ] **Step 3b: Implement the shared review dialog** — in `lib/features/map_screen.dart`, add a top-level function (outside any class):

```dart
/// Append/Cancel review for an AI-generated flesh-out. Returns true on Append.
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

- [ ] **Step 3c: Room entry point** — in `lib/features/map_screen.dart`, in `DungeonMapPaneState`, add the method:

```dart
  Future<void> _fleshOutRoom(DungeonRoom room) async {
    final seed = buildFleshOutSeed(ref,
        entityKind: 'location', name: room.title, existingDetail: room.detail);
    final String detail;
    try {
      detail = await ref.read(interpreterServiceProvider).fleshOut(seed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Flesh out failed: $e')));
      }
      return;
    }
    if (!mounted) return;
    if (await showFleshOutReview(context, detail) != true) return;
    await ref.read(mapProvider.notifier).appendRoomDetail(room.id, detail);
  }
```

and in `_detailCard`'s button `Wrap` (beside the `linger` `OutlinedButton`) add:

```dart
                if (ref.watch(aiReadyProvider))
                  OutlinedButton(
                    key: const Key('flesh-out-room'),
                    onPressed: () => _fleshOutRoom(room),
                    child: const Text('Flesh out'),
                  ),
```

- [ ] **Step 3d: Hex entry point** — in `lib/features/map_screen.dart`, in `HexMapPaneState`, add the method:

```dart
  Future<void> _fleshOutSite(HexCell h) async {
    final seed = buildFleshOutSeed(ref,
        entityKind: 'location',
        name: h.site ?? 'site',
        existingDetail: h.siteLines.join('\n'));
    final String detail;
    try {
      detail = await ref.read(interpreterServiceProvider).fleshOut(seed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Flesh out failed: $e')));
      }
      return;
    }
    if (!mounted) return;
    if (await showFleshOutReview(context, detail) != true) return;
    await ref.read(mapProvider.notifier).appendSiteLine(h.col, h.row, detail);
  }
```

and in the hex card's `if (h.site != null) ...[` button list (beside `site-crawl`/`site-full`) add:

```dart
                if (ref.watch(aiReadyProvider))
                  FilledButton.tonal(
                    key: const Key('flesh-out-site'),
                    onPressed: () => _fleshOutSite(h),
                    child: const Text('Flesh out'),
                  ),
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/flesh_out_test.dart`
Expected: PASS (all four tests).

- [ ] **Step 5: Full verification**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test` → expect All tests passed.

- [ ] **Step 6: Commit**

```bash
git add lib/state/providers.dart lib/features/map_screen.dart test/flesh_out_test.dart
git commit -m "feat(ai): flesh-out dungeon room + hex site (+ appendSiteLine, review dialog)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 7: Doc sync — CLAUDE.md

**Files:** Modify `CLAUDE.md` (the AI-expansion #3 note).

- [ ] **Step 1: Append the #4 note** — in `CLAUDE.md`, find the "AI expansion #3 (GM narration)" paragraph (ends "flesh-out an entity (#4), LLM-ranked suggestion chips (#5)."). Immediately after it, append:

```
  **AI expansion #4 (flesh out an entity):** a one generic `fleshOut(FleshOutSeed)`
  seam (`buildFleshOutPrompt` — instruction + #1 grounding + `name:`/`existing:`
  + `Detail:` cue) over four aiReady-gated entry points — roster character +
  thread (append via the `_EditDialog`), dungeon room + world hex site (append
  after a `showFleshOutReview` Append/Cancel). Grounding via the pure
  `fleshOutSeedFrom` / `buildFleshOutSeed` (`play_context.dart`) using
  name-query `searchEntries` recall; `MapNotifier.appendSiteLine` mirrors
  `appendRoomDetail`. See
  `docs/superpowers/specs/2026-06-24-flesh-out-entity-design.md`. Deferred:
  LLM-ranked suggestion chips (#5).
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note flesh-out-entity in CLAUDE.md (AI expansion #4)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 seam (`FleshOutSeed`/`buildFleshOutPrompt`/`parseFleshOutResponse`) → Task 1; interface+impls → Task 2. ✓
- §2 assembler (pure `fleshOutSeedFrom` + `buildFleshOutSeed` wrapper, name-query recall, scene from newest scene) → Task 3. ✓
- §3 entry points: character → Task 4, thread → Task 5, room + hex → Task 6 (all aiReady-gated, append-after-review). ✓
- §4 `appendSiteLine` → Task 6 (Step 3a). ✓
- §5 `showFleshOutReview` → Task 6 (Step 3b). ✓
- Testing: prompt (Task 1), assembler (Task 3), 4 entry-point widget tests (Tasks 4-6). ✓
- Doc → Task 7. ✓

**Type consistency:**
- `FleshOutSeed{entityKind,name,existingDetail,systemPrimer,sceneTitle,journalContext}` (Task 1) used in `fleshOut`/`buildFleshOutPrompt` (Tasks 1-2), `fleshOutSeedFrom`/`buildFleshOutSeed` (Task 3), all four entry points (Tasks 4-6). ✓
- `fleshOut(FleshOutSeed) -> Future<String>` consistent across interface/Gemma/fake (Task 2) + all callers. ✓
- `buildFleshOutSeed(ref, entityKind:, name:, existingDetail:)` signature consistent across Tasks 4-6. ✓
- `appendSiteLine(col, row, text)` defined Task 6 Step 3a, called Task 6 Step 3d. ✓
- `showFleshOutReview(context, generated)` defined Task 6 Step 3b, called Steps 3c/3d. ✓
- Keys: `flesh-out-character`/`flesh-out-thread-<id>`/`flesh-out-room`/`flesh-out-site`/`flesh-out-append` consistent between impl + tests. ✓
- Canned fake reply `'Fleshed-out detail.'` (Task 2) asserted in Tasks 4-6. ✓

**Placeholder scan:** No TBD/TODO; complete code per step. The two inline NOTE callouts (room-card visibility, prefs-key prefix) are de-risking guidance, not placeholders. ✓

**Risk notes:**
- The map widget tests use `UncontrolledProviderScope` + a pre-built `ProviderContainer` so the test can `c.read(mapProvider.future)` the same container the widget uses (mirrors how the hexcrawl tests assert state).
- Each entry point mirrors the established `_recap`/narrate gate+error+persist shape; `mounted`/`context.mounted` guards match the host widget type (State vs ConsumerWidget).
