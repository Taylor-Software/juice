# Active-Scene Grounding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every AI seam ground on the spine's pinned `activeScene` (not always the newest scene entry), via one shared resolver — so the HUD and the AI agree on "which scene."

**Architecture:** Extract the HUD's scene-resolution into a pure `activeSceneEntry(journal, activeSceneId)` helper; route the HUD + `_sceneContext` (narrate/interpret/voice) + `fleshOutSeedFrom` (flesh-out) + the assistant rail (ranked chips) through it. `recap` is untouched.

**Tech Stack:** Dart, Flutter, flutter_riverpod, flutter_test.

---

## File Structure

- **Modify** `lib/state/play_context.dart` — `activeSceneEntry` resolver; `fleshOutSeedFrom`/`buildFleshOutSeed` use it.
- **Modify** `lib/shared/play_context_hud.dart` — DRY onto `activeSceneEntry`.
- **Modify** `lib/features/journal_screen.dart` — `_sceneContext()` resolves via the spine.
- **Modify** `lib/features/assistant_rail.dart` — `_signature` + `_maybeRank` resolve via the spine.
- **Test** `test/flesh_out_seed_test.dart` (resolver + pinned flesh-out), `test/narrate_test.dart` (pinned narrate).

---

## Task 1: Shared resolver + HUD DRY

**Files:**
- Modify: `lib/state/play_context.dart`, `lib/shared/play_context_hud.dart`
- Test: `test/flesh_out_seed_test.dart`

- [ ] **Step 1: Write the failing test** — add to `test/flesh_out_seed_test.dart` inside `void main()` (the `_e(id, title, body, kind)` helper already exists; it builds a `JournalEntry`):

```dart
  group('activeSceneEntry', () {
    final journal = [
      _e('3', 'Scene Three', 'newest', 'scene'),
      _e('2', 'Note', 'a note', 'text'),
      _e('1', 'Scene One', 'oldest', 'scene'),
    ];
    test('pinned id present -> that scene', () {
      expect(activeSceneEntry(journal, '1')?.title, 'Scene One');
    });
    test('null pin -> newest scene', () {
      expect(activeSceneEntry(journal, null)?.title, 'Scene Three');
    });
    test('pin not found -> newest scene', () {
      expect(activeSceneEntry(journal, 'zzz')?.title, 'Scene Three');
    });
    test('no scene entries -> null', () {
      expect(activeSceneEntry([_e('2', 'Note', 'x', 'text')], '1'), isNull);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/flesh_out_seed_test.dart`
Expected: FAIL — `activeSceneEntry` undefined.

- [ ] **Step 3: Implement the resolver** — in `lib/state/play_context.dart`, add (near `fleshOutSeedFrom`):

```dart
/// The campaign's current scene: the spine's pinned [activeSceneId] when set
/// and present, else the newest scene entry (journal is newest-first), else
/// null. The single source of truth for "which scene" across the HUD + AI seams.
JournalEntry? activeSceneEntry(
    List<JournalEntry> journal, String? activeSceneId) {
  final scenes = journal.where((e) => e.kind == JournalKind.scene);
  return (activeSceneId == null
          ? null
          : scenes.where((e) => e.id == activeSceneId).firstOrNull) ??
      scenes.firstOrNull;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/flesh_out_seed_test.dart`
Expected: PASS.

- [ ] **Step 5: DRY the HUD** — in `lib/shared/play_context_hud.dart`, replace the inline block:

```dart
    final activeSceneId =
        ref.watch(playContextProvider).valueOrNull?.activeSceneId;
    final sceneEntries =
        entries.where((e) => e.kind == JournalKind.scene).toList();
    final scene = (activeSceneId == null
            ? null
            : sceneEntries.where((e) => e.id == activeSceneId).firstOrNull) ??
        sceneEntries.firstOrNull;
```

with:

```dart
    final scene = activeSceneEntry(entries,
        ref.watch(playContextProvider).valueOrNull?.activeSceneId);
```

(`activeSceneEntry` resolves via `play_context.dart`, which the HUD already
imports for `playContextProvider`. If analyze flags it, add the import.)

- [ ] **Step 6: Verify the HUD is unchanged behaviorally**

Run: `flutter analyze lib/shared/play_context_hud.dart lib/state/play_context.dart`
Expected: `No issues found!`
Run: `flutter test test/campaign_header_test.dart`
Expected: PASS (the resolver is behavior-identical to the inlined logic).

- [ ] **Step 7: Commit**

```bash
git add lib/state/play_context.dart lib/shared/play_context_hud.dart test/flesh_out_seed_test.dart
git commit -m "feat: activeSceneEntry resolver (extract the HUD's scene logic)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Narrate/interpret/voice + flesh-out grounding

**Files:**
- Modify: `lib/features/journal_screen.dart`, `lib/state/play_context.dart`
- Test: `test/narrate_test.dart`, `test/flesh_out_seed_test.dart`

- [ ] **Step 1: Write the failing flesh-out test** — add to `test/flesh_out_seed_test.dart` inside `void main()`:

```dart
  test('fleshOutSeedFrom: activeSceneId pins an older scene as sceneTitle', () {
    final journal = [
      _e('s2', 'Newer Scene', 'recent', 'scene'),
      _e('s1', 'Pinned Scene', 'older', 'scene'),
    ];
    final seed = fleshOutSeedFrom(
      entityKind: 'NPC',
      name: 'Vane',
      existingDetail: '',
      systemPrimer: '',
      activeCharacter: '',
      journal: journal,
      activeSceneId: 's1',
    );
    expect(seed.sceneTitle, 'Pinned Scene'); // the pinned older scene, not newest
  });
```

- [ ] **Step 2: Write the failing narrate test** — add to `test/narrate_test.dart` inside `void main()`:

```dart
  testWidgets('narrate grounds on the pinned (older) scene', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default':
          '[{"id":"s2","timestamp":"2026-06-12T10:02:00.000","title":"Newer Scene","body":"","kind":"scene"},'
              '{"id":"s1","timestamp":"2026-06-12T10:00:00.000","title":"Pinned Scene","body":"","kind":"scene"}]',
      'juice.ai_enabled.v1': true,
    });
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    final data = OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>);
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        oracleProvider.overrideWith((ref) async => Oracle(data, Dice(Random(1)))),
        interpreterServiceProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: JournalScreen())),
    ));
    await tester.pumpAndSettle();
    final c =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    // Pin the OLDER scene.
    await c.read(playContextProvider.notifier).setActiveScene('s1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer-narrate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('narrate-continue')));
    await tester.pumpAndSettle();
    expect(fake.lastNarrateSeed!.sceneTitle, contains('Pinned Scene'));
  });
```

Add any imports the test needs at the top of `narrate_test.dart` (it already
imports most; ensure `dart:convert`, `dart:io`, `dart:math`, `oracle_data.dart`,
`dice.dart`, `oracle.dart`, `play_context.dart`, and `fake_interpreter.dart` are
present).

- [ ] **Step 3: Run to verify they fail**

Run: `flutter test test/flesh_out_seed_test.dart test/narrate_test.dart`
Expected: FAIL — `fleshOutSeedFrom` has no `activeSceneId`; narrate still uses the newest scene.

- [ ] **Step 4: Implement `_sceneContext`** — in `lib/features/journal_screen.dart`, replace `_sceneContext()` with:

```dart
  String _sceneContext() {
    final journal = ref.read(journalProvider).valueOrNull ?? const [];
    final scene = activeSceneEntry(
        journal, ref.read(playContextProvider).valueOrNull?.activeSceneId);
    if (scene == null) return '';
    final chaos =
        scene.chaosFactor != null ? ' (Chaos ${scene.chaosFactor})' : '';
    return 'Scene: ${scene.title}$chaos';
  }
```

(`activeSceneEntry` + `playContextProvider` resolve via the existing
`play_context.dart` import.)

- [ ] **Step 5: Implement the flesh-out grounding** — in `lib/state/play_context.dart`:

(a) in `fleshOutSeedFrom`, add the param + use the resolver. Change the signature to add `String? activeSceneId,` (after `excludeId`), and replace the `sceneTitle` derivation:

```dart
  // was: journal.where(scene && title non-empty).map(title).firstOrNull
  final sceneEntry = activeSceneEntry(journal, activeSceneId);
  final sceneTitle =
      (sceneEntry != null && sceneEntry.title.trim().isNotEmpty)
          ? sceneEntry.title
          : null;
```

(b) in `buildFleshOutSeed`, pass the spine's pointer:

```dart
      excludeId: excludeId,
      activeSceneId: ref.read(playContextProvider).valueOrNull?.activeSceneId,
```

- [ ] **Step 6: Run to verify they pass**

Run: `flutter test test/flesh_out_seed_test.dart test/narrate_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/journal_screen.dart lib/state/play_context.dart test/flesh_out_seed_test.dart test/narrate_test.dart
git commit -m "feat: narrate/interpret/voice + flesh-out ground on the pinned active scene

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Assistant rail (ranked chips) grounding

**Files:**
- Modify: `lib/features/assistant_rail.dart`

- [ ] **Step 1: Thread `activeSceneId` through `_signature`/`_maybeRank`/`build`** — in `lib/features/assistant_rail.dart`:

(a) `_signature` — add the param + resolve via the helper:

```dart
  String _signature(List<JournalEntry> journal, List<Suggestion> candidates,
      String? activeSceneId) {
    final top = journal.isEmpty ? '' : journal.first.id;
    final scene = activeSceneEntry(journal, activeSceneId)?.id ?? '';
    return '$top|$scene|${candidates.map((s) => s.id).join(',')}';
  }
```

(b) `_maybeRank` — add the param + resolve via the helper (replace the
`journal.where(scene).firstOrNull ?? journal.firstOrNull` line):

```dart
  Future<void> _maybeRank(String sig, List<JournalEntry> journal,
      List<Suggestion> candidates, String? activeSceneId) async {
    if (_rankCache.containsKey(sig) || _rankingSig == sig) return;
    _rankingSig = sig;
    final scene =
        activeSceneEntry(journal, activeSceneId) ?? journal.firstOrNull;
    // … the rest of _maybeRank is unchanged (seed build + rankSuggestions) …
```

(c) `build` — read the pointer and pass it to both:

```dart
    final journal =
        ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final activeSceneId =
        ref.watch(playContextProvider).valueOrNull?.activeSceneId;
    final sig = _signature(journal, suggestions, activeSceneId);
    if (_expanded &&
        aiReady &&
        !_rankCache.containsKey(sig) &&
        _rankingSig != sig) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeRank(sig, journal, suggestions, activeSceneId);
      });
    }
```

(`activeSceneEntry` + `playContextProvider` resolve via the existing
`play_context.dart` import in the rail.)

- [ ] **Step 2: Verify**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test` → expect All tests passed. (The existing `assistant_rail_test` seeds one scene, so newest == pinned == null-pin — behavior unchanged; the resolver logic is covered by the Task 1 unit test.)

- [ ] **Step 3: Commit**

```bash
git add lib/features/assistant_rail.dart
git commit -m "feat: ranked-chip grounding + signature key on the pinned active scene

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Doc sync — CLAUDE.md

**Files:** Modify `CLAUDE.md`

- [ ] **Step 1: Note the resolver** — in `CLAUDE.md`, find the PlayContext-spine bullet (mentions `activeSceneId` / the HUD scene line following it). Append a sentence:

```
  A shared `activeSceneEntry(journal, activeSceneId)` (`play_context.dart`) is
  the single source of truth for "which scene" — the pinned `activeSceneId` else
  the newest scene entry. The HUD + every AI seam that needs the current scene
  (`_sceneContext` → narrate/interpret/voice; `fleshOutSeedFrom` → flesh-out; the
  assistant rail → ranked chips) resolve through it, so a pinned scene grounds
  the AI consistently. (`recap`'s since-last-scene-divider logic is independent.)
  See `docs/superpowers/specs/2026-06-24-active-scene-grounding-design.md`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note the activeSceneEntry resolver in CLAUDE.md

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 `activeSceneEntry` resolver → Task 1. ✓
- §2 HUD DRY → Task 1; `_sceneContext` (narrate/interpret/voice) → Task 2; `fleshOutSeedFrom`/`buildFleshOutSeed` → Task 2; assistant rail → Task 3. ✓
- recap untouched → not in any task. ✓
- Testing: `activeSceneEntry` unit (Task 1), `fleshOutSeedFrom` pinned (Task 2), narrate pinned (Task 2), HUD/rail behavior-preserved (Tasks 1/3). ✓
- Doc → Task 4. ✓

**Type consistency:**
- `activeSceneEntry(List<JournalEntry>, String?) -> JournalEntry?` (Task 1) used in HUD (Task 1), `_sceneContext` (Task 2), `fleshOutSeedFrom` (Task 2), `_signature`/`_maybeRank` (Task 3). ✓
- `fleshOutSeedFrom`'s new `String? activeSceneId` (Task 2) is passed by `buildFleshOutSeed` (Task 2) and the unit test (Task 2). ✓
- `_signature`/`_maybeRank` gain a trailing `String? activeSceneId` param consistently (Task 3, defined + called in `build`). ✓

**Placeholder scan:** No TBD/TODO. The `// … unchanged …` in Task 3 Step 1(b) refers to code the engineer must preserve verbatim from the existing method — the changed lines are shown in full.

**Risk notes:**
- The narrate pinned test pins via `playContextProvider.notifier.setActiveScene('s1')` on the real container (robust; no guessing the persisted JSON shape).
- `fleshOutSeedFrom`'s `activeSceneId` is optional (defaults null → newest scene), so the existing direct-call test and any other caller stay valid.
