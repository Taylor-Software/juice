# LLM-Ranked Suggestion Chips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The assistant rail reorders its fixed suggestion chips by LLM relevance to the current scene and annotates the top pick with a one-line "why now", with a rule-order fallback.

**Architecture:** A `rankSuggestions` seam returning a tolerant `RankResult {order, why}`; a pure `applyRanking` that reorders the rule chips (drop unknown ids, append omitted) so the set never breaks; the rail triggers the LLM on expand+aiReady, cached by a play-state signature, and renders the reordered chips + a `💡` caption.

**Tech Stack:** Dart, Flutter, flutter_riverpod, flutter_test. Reuses `_flat`/`_capped`/`_pcLine`/`_stripThink`/`_isolateJson`/`kRecallMaxEntries`/`kRecallMaxChars`/`recallLines` (oracle_interpreter), `aiReadyProvider`/`interpreterServiceProvider`/`systemPrimerProvider`/`activeCharacterLineProvider`/`suggestionsProvider`.

---

## File Structure

- **Modify** `lib/engine/oracle_interpreter.dart` — `RankSuggestionsSeed`, `RankResult`, `buildRankPrompt`, `parseRankResult`.
- **Modify** `lib/state/interpreter.dart` — `rankSuggestions` on the interface.
- **Modify** `lib/state/interpreter_gemma.dart` — `rankSuggestions` impl.
- **Modify** `lib/engine/suggestions.dart` — `applyRanking` pure core (imports `RankResult`).
- **Modify** `test/fake_interpreter.dart` — `rankSuggestions` fake.
- **Modify** `lib/features/assistant_rail.dart` — rank trigger/cache + reordered render + why caption.
- **Test** `test/oracle_interpreter_test.dart`, `test/suggestions_test.dart`, `test/assistant_rail_test.dart`.

---

## Task 1: Seam — RankSuggestionsSeed + buildRankPrompt + parseRankResult

**Files:** Modify `lib/engine/oracle_interpreter.dart`; Test `test/oracle_interpreter_test.dart`.

- [ ] **Step 1: Write the failing test** — add inside `void main()` in `test/oracle_interpreter_test.dart`:

```dart
  group('buildRankPrompt / parseRankResult', () {
    test('renders grounding + candidate lines + JSON cue', () {
      final p = buildRankPrompt(const RankSuggestionsSeed(
        candidates: [
          (id: 'roll-oracle', label: 'Roll the oracle'),
          (id: 'scene-event', label: 'Scene event'),
        ],
        systemPrimer: 'Ironsworn: perilous Iron Lands.',
        sceneTitle: 'The crypt',
        activeCharacter: 'Taurin (PC)',
        journalContext: ['The door was barred.'],
      ));
      expect(p, contains('system: Ironsworn'));
      expect(p, contains('pc: Taurin (PC)'));
      expect(p, contains('scene: The crypt'));
      expect(p, contains('recall: The door was barred.'));
      expect(p, contains('- roll-oracle: Roll the oracle'));
      expect(p, contains('- scene-event: Scene event'));
      expect(p, contains('"order"'));
      expect(p.trimRight(), endsWith('OUTPUT:'));
    });

    test('parses a clean object (think/fence tolerant)', () {
      final r = parseRankResult(
          '<think>x</think>```json\n{"order":["scene-event","roll-oracle"],"why":"It is live"}\n```');
      expect(r.order, ['scene-event', 'roll-oracle']);
      expect(r.why, 'It is live');
    });

    test('garbage / missing JSON -> empty result, never throws', () {
      expect(parseRankResult('no json here').order, isEmpty);
      expect(parseRankResult('no json here').why, '');
      expect(parseRankResult('{"order":"notalist"}').order, isEmpty);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/oracle_interpreter_test.dart`
Expected: FAIL — `RankSuggestionsSeed`/`RankResult`/`buildRankPrompt`/`parseRankResult` undefined.

- [ ] **Step 3: Implement** — in `lib/engine/oracle_interpreter.dart`, after the flesh-out section (after `parseFleshOutResponse`), add:

```dart
// -- Ranked suggestions -------------------------------------------------------

class RankSuggestionsSeed {
  const RankSuggestionsSeed({
    required this.candidates,
    this.systemPrimer = '',
    this.sceneTitle,
    this.activeCharacter = '',
    this.journalContext = const [],
  });

  /// Candidate next-move chips in rule order: (stable id, display label).
  final List<({String id, String label})> candidates;
  final String systemPrimer;
  final String? sceneTitle;
  final String activeCharacter;
  final List<String> journalContext;
}

/// The model's ranking output. Best-effort: an empty [order] means "no opinion"
/// (the caller keeps rule order); [why] is the top pick's one-line rationale.
class RankResult {
  const RankResult({this.order = const [], this.why = ''});
  final List<String> order;
  final String why;
}

/// Instruction + the #1 grounding (system/pc/scene/recall) + the candidate
/// lines + a JSON cue. Caps mirror the other builders.
String buildRankPrompt(RankSuggestionsSeed seed) {
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
  final cand = StringBuffer();
  for (final c in seed.candidates) {
    cand.write('- ${c.id}: ${_flat(c.label)}\n');
  }
  return 'You are the game master for a solo tabletop RPG. Given the current '
      'scene and these candidate next moves, output the move ids ordered '
      'most-to-least useful right now, and one short sentence on why the top '
      'one fits. Output ONLY a JSON object, no prose: '
      '{"order":["id",...],"why":"..."}.\n\n'
      'INPUT:\n'
      '$systemLine'
      '${_pcLine(seed.activeCharacter)}'
      '$sceneLine'
      '$recall'
      'candidates:\n'
      '$cand'
      'OUTPUT:';
}

/// Tolerant parse — NEVER throws (ranking is best-effort; an empty result means
/// keep rule order). Isolates the first JSON object, coerces `order` to strings.
RankResult parseRankResult(String raw) {
  final json = _isolateJson(raw);
  if (json == null) return const RankResult();
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return const RankResult();
    final orderRaw = decoded['order'];
    final order = <String>[
      if (orderRaw is List)
        for (final e in orderRaw) e.toString(),
    ];
    final why = (decoded['why'] ?? '').toString().trim();
    return RankResult(order: order, why: why);
  } catch (_) {
    return const RankResult();
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/oracle_interpreter_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle_interpreter.dart test/oracle_interpreter_test.dart
git commit -m "feat(ai): rankSuggestions seam — RankSuggestionsSeed + buildRankPrompt + tolerant parse

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Interface + impls (rankSuggestions)

**Files:** Modify `lib/state/interpreter.dart`, `lib/state/interpreter_gemma.dart`, `test/fake_interpreter.dart`.

- [ ] **Step 1: Interface** — in `lib/state/interpreter.dart`, in `abstract class InterpreterService`, after the `fleshOut` declaration add:

```dart
  /// Rank candidate suggestion chips for the current play state. Best-effort:
  /// returns an empty [RankResult] rather than throwing on a model miss.
  Future<RankResult> rankSuggestions(RankSuggestionsSeed seed);
```

- [ ] **Step 2: Gemma impl** — in `lib/state/interpreter_gemma.dart`, after the `fleshOut` override add:

```dart
  @override
  Future<RankResult> rankSuggestions(RankSuggestionsSeed seed) async {
    return parseRankResult(await _generate(buildRankPrompt(seed)));
  }
```

- [ ] **Step 3: Fake impl** — in `test/fake_interpreter.dart`, beside the fleshOut fake fields add:

```dart
  final List<RankResult> queuedRank = [];
  RankSuggestionsSeed? lastRankSeed;
  int rankCalls = 0;
  Object? rankError;
```

and beside the `fleshOut` override add:

```dart
  @override
  Future<RankResult> rankSuggestions(RankSuggestionsSeed seed) async {
    lastRankSeed = seed;
    rankCalls++;
    if (rankError != null) throw rankError!;
    if (queuedRank.isEmpty) return const RankResult();
    return queuedRank.removeAt(0);
  }
```

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/state/interpreter.dart lib/state/interpreter_gemma.dart test/fake_interpreter.dart` → expect no issues.
Run: `flutter test test/oracle_interpreter_test.dart` → expect PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/interpreter.dart lib/state/interpreter_gemma.dart test/fake_interpreter.dart
git commit -m "feat(ai): rankSuggestions on InterpreterService (+ Gemma + fake)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Pure core — applyRanking

**Files:** Modify `lib/engine/suggestions.dart`; Test `test/suggestions_test.dart`.

- [ ] **Step 1: Write the failing test** — add inside `void main()` in `test/suggestions_test.dart` (add `import 'package:juice_oracle/engine/oracle_interpreter.dart';` at the top for `RankResult`):

```dart
  group('applyRanking', () {
    final rule = [
      const Suggestion('a', 'A', SuggestionAction.inline),
      const Suggestion('b', 'B', SuggestionAction.navigate),
      const Suggestion('c', 'C', SuggestionAction.navigate),
    ];

    test('reorders by order, drops unknown ids, appends omitted, trims why', () {
      final r =
          applyRanking(rule, const RankResult(order: ['c', 'zzz', 'a'], why: ' do C '));
      expect(r.chips.map((s) => s.id).toList(), ['c', 'a', 'b']);
      expect(r.why, 'do C');
    });

    test('empty result -> rule order, null why', () {
      final r = applyRanking(rule, const RankResult());
      expect(r.chips.map((s) => s.id).toList(), ['a', 'b', 'c']);
      expect(r.why, isNull);
    });

    test('duplicate ids in order are taken once', () {
      final r = applyRanking(rule, const RankResult(order: ['b', 'b', 'a']));
      expect(r.chips.map((s) => s.id).toList(), ['b', 'a', 'c']);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/suggestions_test.dart`
Expected: FAIL — `applyRanking` undefined.

- [ ] **Step 3: Implement** — in `lib/engine/suggestions.dart`:

(a) add the import at the top:
```dart
import 'oracle_interpreter.dart';
```

(b) at the end of the file add:
```dart
/// Reorders [ruleOrder] by an LLM [RankResult]: each known id once in the
/// model's order, then any rule chips the model omitted appended (the set never
/// shrinks); unknown ids are ignored (handlers always valid). `why` is the
/// trimmed rationale, or null when empty. Pure.
({List<Suggestion> chips, String? why}) applyRanking(
    List<Suggestion> ruleOrder, RankResult llm) {
  final byId = {for (final s in ruleOrder) s.id: s};
  final seen = <String>{};
  final ordered = <Suggestion>[];
  for (final id in llm.order) {
    final s = byId[id];
    if (s != null && seen.add(id)) ordered.add(s);
  }
  for (final s in ruleOrder) {
    if (seen.add(s.id)) ordered.add(s);
  }
  final why = llm.why.trim();
  return (chips: ordered, why: why.isEmpty ? null : why);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/suggestions_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/suggestions.dart test/suggestions_test.dart
git commit -m "feat(ai): applyRanking — reorder rule chips by RankResult (robust)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Rail wiring (trigger + cache + render)

**Files:** Modify `lib/features/assistant_rail.dart`; Test `test/assistant_rail_test.dart`.

- [ ] **Step 1: Write the failing test** — add to `test/assistant_rail_test.dart`. First add these imports if missing: `import 'package:juice_oracle/engine/oracle_interpreter.dart';`, `import 'package:flutter/material.dart';` (already present). Add a helper above `void main()`:

```dart
Future<ProviderContainer> _pumpRankRail(
    WidgetTester tester, FakeInterpreterService fake,
    {bool aiEnabled = true}) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.journal.v2.default':
        '[{"id":"s1","timestamp":"2026-06-12T10:00:00.000","title":"At the gate","body":"x","kind":"scene"}]',
    'juice.threads.v1.default': '[]',
    if (aiEnabled) 'juice.ai_enabled.v1': true,
  });
  final c = ProviderContainer(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AssistantRail()))));
  await tester.pumpAndSettle();
  return c;
}
```

and the tests inside `void main()`:

```dart
  testWidgets('AI-ranked: chips reordered + why caption when AI ready',
      (tester) async {
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    fake.queuedRank.add(const RankResult(
        order: ['scene-event', 'roll-oracle'], why: 'The scene is live'));
    await _pumpRankRail(tester, fake);
    await tester.tap(find.byKey(const Key('assistant-expand')));
    await tester.pumpAndSettle(); // expand + post-frame rank + setState
    final keys = tester
        .widgetList<ActionChip>(find.byType(ActionChip))
        .map((w) => (w.key as ValueKey).value)
        .toList();
    expect(keys.indexOf('suggest-scene-event'),
        lessThan(keys.indexOf('suggest-roll-oracle')));
    expect(find.byKey(const Key('suggest-why')), findsOneWidget);
    expect(find.textContaining('The scene is live'), findsOneWidget);
  });

  testWidgets('AI off: rule order, no why caption', (tester) async {
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.unsupported));
    await _pumpRankRail(tester, fake, aiEnabled: false);
    await tester.tap(find.byKey(const Key('assistant-expand')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('suggest-why')), findsNothing);
    final keys = tester
        .widgetList<ActionChip>(find.byType(ActionChip))
        .map((w) => (w.key as ValueKey).value)
        .toList();
    expect(keys.first, 'suggest-roll-oracle');
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/assistant_rail_test.dart`
Expected: FAIL — chips not reordered / no `suggest-why`.

- [ ] **Step 3: Implement** — in `lib/features/assistant_rail.dart`:

(a) add imports:
```dart
import '../engine/oracle_interpreter.dart';
import '../state/interpreter.dart';
import '../state/play_context.dart';
```

(b) in `_AssistantRailState`, add state fields beside `_expanded`:
```dart
  // LLM ranking, cached by a play-state signature so we call the model only
  // when the state actually changes. Empty cached result = keep rule order.
  final Map<String, RankResult> _rankCache = {};
  String? _rankingSig; // signature currently in flight
```

(c) add these methods to `_AssistantRailState`:
```dart
  String _signature(List<JournalEntry> journal, List<Suggestion> candidates) {
    final top = journal.isEmpty ? '' : journal.first.id;
    final scene = journal
            .where((e) => e.kind == JournalKind.scene)
            .map((e) => e.id)
            .firstOrNull ??
        '';
    return '$top|$scene|${candidates.map((s) => s.id).join(',')}';
  }

  Future<void> _maybeRank(String sig, List<JournalEntry> journal,
      List<Suggestion> candidates) async {
    if (_rankCache.containsKey(sig) || _rankingSig == sig) return;
    _rankingSig = sig;
    final scene =
        journal.where((e) => e.kind == JournalKind.scene).firstOrNull ??
            journal.firstOrNull;
    final seed = RankSuggestionsSeed(
      candidates: [for (final s in candidates) (id: s.id, label: s.label)],
      systemPrimer: ref.read(systemPrimerProvider),
      sceneTitle:
          scene == null ? null : (scene.title.isEmpty ? scene.body : scene.title),
      activeCharacter: ref.read(activeCharacterLineProvider),
      journalContext: scene == null ? const [] : recallLines(journal, scene),
    );
    RankResult result;
    try {
      result = await ref.read(interpreterServiceProvider).rankSuggestions(seed);
    } catch (_) {
      result = const RankResult(); // fall back to rule order; don't retry-loop
    }
    if (!mounted) return;
    setState(() {
      _rankCache[sig] = result;
      if (_rankingSig == sig) _rankingSig = null;
    });
  }
```

(d) in `build`, after the existing `final suggestions = ref.watch(suggestionsProvider);` and `final aiReady = ref.watch(aiReadyProvider);`, add:
```dart
    final journal =
        ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final sig = _signature(journal, suggestions);
    if (_expanded && aiReady && !_rankCache.containsKey(sig) && _rankingSig != sig) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeRank(sig, journal, suggestions);
      });
    }
    final ranked = (aiReady && _rankCache[sig] != null)
        ? applyRanking(suggestions, _rankCache[sig]!)
        : (chips: suggestions, why: null);
```

(e) change the chip `Wrap` to iterate `ranked.chips` instead of `suggestions`:
```dart
                    for (final s in ranked.chips)
                      ActionChip(
                        key: Key('suggest-${s.id}'),
                        label: Text(s.label),
                        onPressed: () => _onTap(s),
                      ),
```

(f) immediately AFTER the chip `Wrap` (before the `if (aiReady) ...[` ask-gm block), add the caption:
```dart
                if (ranked.why != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('💡 ${ranked.why}',
                        key: const Key('suggest-why'),
                        style: theme.textTheme.bodySmall),
                  ),
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/assistant_rail_test.dart`
Expected: PASS (existing rail tests + the two new ones). If the new ranked test flakes on timing, add one more `await tester.pump();` after the `pumpAndSettle()` that follows the expand tap.

- [ ] **Step 5: Full verification**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test` → expect All tests passed.

- [ ] **Step 6: Commit**

```bash
git add lib/features/assistant_rail.dart test/assistant_rail_test.dart
git commit -m "feat(ai): LLM-rank the assistant rail chips + why caption (cached, rule fallback)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: Doc sync — CLAUDE.md

**Files:** Modify `CLAUDE.md` (the assistant-rail note + the AI-expansion #4 note).

- [ ] **Step 1: Append the #5 note** — in `CLAUDE.md`, find the "AI expansion #4 (flesh out an entity)" paragraph (ends "Deferred AI affordance: LLM-ranked suggestion chips (#5)."). Replace that trailing "Deferred…" sentence with:

```
  **AI expansion #5 (LLM-ranked suggestion chips):** the assistant rail reorders
  its fixed rule-based chips by LLM relevance and annotates the top pick with a
  one-line `💡 why` caption. `rankSuggestions(RankSuggestionsSeed)` returns a
  tolerant `RankResult {order, why}` (`parseRankResult` never throws —
  best-effort); the pure `applyRanking` (`suggestions.dart`) reorders the rule
  chips (drops unknown ids, appends omitted, so the set + handlers never break).
  The rail (`assistant_rail.dart`) calls the seam only when expanded + aiReady,
  cached by a play-state signature (top entry id + scene id + candidate ids),
  with a rule-order fallback on loading/error/AI-off. See
  `docs/superpowers/specs/2026-06-24-ranked-suggestions-design.md`. This
  completes the AI-expansion epic (#1–#5).
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note LLM-ranked suggestions in CLAUDE.md (AI expansion #5)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 seam (`RankSuggestionsSeed`/`RankResult`/`buildRankPrompt`/`parseRankResult` tolerant) → Task 1; interface+impls → Task 2. ✓
- §2 pure `applyRanking` (reorder/drop-unknown/append-omitted/empty-why→null) → Task 3. ✓
- §3 rail integration (sync provider stays; trigger on expand+aiReady; signature cache; reordered render + `suggest-why` caption; fallback) → Task 4. ✓
- §4 robustness (unknown dropped, omitted appended, empty→rule order, generate-throw caught) → Tasks 1+3+4. ✓
- Testing: prompt/parse (Task 1), applyRanking (Task 3), fake (Task 2), rail widget (Task 4). ✓
- Doc → Task 5. ✓

**Type consistency:**
- `RankSuggestionsSeed{candidates:List<({String id,String label})>, systemPrimer, sceneTitle?, activeCharacter, journalContext}` + `RankResult{order:List<String>, why:String}` (Task 1) used by `rankSuggestions` (Task 2), `applyRanking` (Task 3, returns `({List<Suggestion> chips, String? why})`), and the rail (Task 4). ✓
- `rankSuggestions(RankSuggestionsSeed) -> Future<RankResult>` consistent across interface/Gemma/fake (Task 2) + rail caller (Task 4). ✓
- Keys `suggest-<id>` (unchanged) + new `suggest-why` consistent between Task 4 impl + test. ✓
- Fake default `const RankResult()` (Task 2) ↔ rule-order fallback asserted (Task 4). ✓

**Placeholder scan:** No TBD/TODO; complete code per step. The flake-mitigation note in Task 4 Step 4 is guidance, not a placeholder. ✓

**Risk notes:**
- The rank trigger uses `addPostFrameCallback` (no async-in-build); the signature cache + `_rankingSig` guard prevent re-fire loops. `_maybeRank` catches generation errors and caches an empty result (rule order) so a failing model doesn't retry every rebuild.
- The widget test asserts chip ORDER via `ActionChip` key positions; `find.byType(ActionChip)` returns them in tree (render) order, which is the `Wrap` child order.
