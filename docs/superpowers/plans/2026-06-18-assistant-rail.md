# Assistant Rail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A collapsible assistant rail on the Journal verb — rule-based suggestion chips (driven by the PlayContext spine) plus a budget-safe LLM "ask the GM" box, with inline chips writing to the journal and navigate chips deep-linking.

**Architecture:** A pure `SuggestionEngine` (`suggestionsFor`, no Flutter/LLM) returns ordered `Suggestion{id,label,action}` values; a `suggestionsProvider` derives its boolean inputs from existing providers. The `AssistantRail` widget renders chips + an ask field on `JournalScreen`; it maps each suggestion `id` to a concrete inline roll (reusing the existing `oracle → journalProvider.addResult` pipeline) or a `shellRouteProvider.goTo` navigation. A new `askGm` seam on `InterpreterService` (mirroring `voiceLine`/`summarize`) powers the ask box within the ~1280-token budget.

**Tech Stack:** Flutter, `flutter_riverpod`, on-device `flutter_gemma` (behind `InterpreterService`), `package:flutter_test`.

---

## File Structure

**Create:**
- `lib/engine/suggestions.dart` — `Suggestion`, `SuggestionAction`, `suggestionsFor` (pure).
- `lib/state/suggestions_provider.dart` — `suggestionsProvider`.
- `lib/features/assistant_rail.dart` — `AssistantRail` widget.
- `test/suggestions_test.dart`, `test/suggestions_provider_test.dart`, `test/assistant_rail_test.dart`.

**Modify:**
- `lib/engine/oracle.dart` — `fateCheckGenResult(FateResult)` pure helper (extracted from `fate_screen.dart`).
- `lib/features/fate_screen.dart` — use the extracted helper (DRY).
- `lib/engine/oracle_interpreter.dart` — `AskGmSeed`, `buildAskGmPrompt`, `parseAskGmResponse`.
- `lib/state/interpreter.dart` — abstract `askGm`.
- `lib/state/interpreter_gemma.dart` — real `askGm` (mirror `voiceLine`).
- `test/fake_interpreter.dart` — fake `askGm`.
- `lib/features/journal_screen.dart` — mount `AssistantRail` atop the journal `Column`.
- `CLAUDE.md` — project note.

---

### Task 1: Suggestion model + suggestionsFor (pure engine)

Pure, no Flutter imports. `Suggestion.id` is the stable key the rail switches on; the engine never imports `Destination` (keeps `lib/engine` free of `lib/shared`).

**Files:**
- Create: `lib/engine/suggestions.dart`
- Test: `test/suggestions_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/suggestions.dart';

List<String> ids(List<Suggestion> s) => s.map((e) => e.id).toList();

void main() {
  group('suggestionsFor', () {
    test('roll-oracle is always present and first', () {
      final s = suggestionsFor(
        hasScenes: false,
        hasOpenThreads: false,
        encounterActive: false,
        ironswornFamily: false,
        hasFocusCharacter: false,
      );
      expect(s.first.id, 'roll-oracle');
      expect(s.first.action, SuggestionAction.inline);
    });

    test('no scenes → start-scene (navigate), not scene-event', () {
      final s = suggestionsFor(
        hasScenes: false, hasOpenThreads: false, encounterActive: false,
        ironswornFamily: false, hasFocusCharacter: false,
      );
      expect(ids(s), contains('start-scene'));
      expect(ids(s), isNot(contains('scene-event')));
    });

    test('has scenes → scene-event (inline), not start-scene', () {
      final s = suggestionsFor(
        hasScenes: true, hasOpenThreads: false, encounterActive: false,
        ironswornFamily: false, hasFocusCharacter: false,
      );
      expect(ids(s), contains('scene-event'));
      expect(ids(s), isNot(contains('start-scene')));
      expect(s.firstWhere((e) => e.id == 'scene-event').action,
          SuggestionAction.inline);
    });

    test('open threads → advance-thread', () {
      final s = suggestionsFor(
        hasScenes: true, hasOpenThreads: true, encounterActive: false,
        ironswornFamily: false, hasFocusCharacter: false,
      );
      expect(ids(s), contains('advance-thread'));
    });

    test('encounter active → combat-turn', () {
      final s = suggestionsFor(
        hasScenes: true, hasOpenThreads: false, encounterActive: true,
        ironswornFamily: false, hasFocusCharacter: false,
      );
      expect(ids(s), contains('combat-turn'));
    });

    test('make-move only when ironsworn family AND a focus character', () {
      List<String> run(bool fam, bool foc) => ids(suggestionsFor(
            hasScenes: true, hasOpenThreads: false, encounterActive: false,
            ironswornFamily: fam, hasFocusCharacter: foc,
          ));
      expect(run(true, true), contains('make-move'));
      expect(run(true, false), isNot(contains('make-move')));
      expect(run(false, true), isNot(contains('make-move')));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/suggestions_test.dart`
Expected: FAIL — `suggestions.dart` / `suggestionsFor` not found.

- [ ] **Step 3: Write minimal implementation**

Create `lib/engine/suggestions.dart`:

```dart
/// How a [Suggestion] resolves when tapped. The rail maps the suggestion's
/// [Suggestion.id] to the concrete inline roll or navigation target; the
/// engine stays free of UI/routing types.
enum SuggestionAction { inline, navigate }

class Suggestion {
  const Suggestion(this.id, this.label, this.action);
  final String id;
  final String label;
  final SuggestionAction action;
}

/// Ranked next-move suggestions for the current play state. Pure: callers pass
/// the booleans (derived elsewhere) so this is trivially testable.
List<Suggestion> suggestionsFor({
  required bool hasScenes,
  required bool hasOpenThreads,
  required bool encounterActive,
  required bool ironswornFamily,
  required bool hasFocusCharacter,
}) {
  return [
    const Suggestion('roll-oracle', 'Roll the oracle', SuggestionAction.inline),
    if (hasScenes)
      const Suggestion('scene-event', 'Scene event', SuggestionAction.inline)
    else
      const Suggestion('start-scene', 'Start a scene', SuggestionAction.navigate),
    if (hasOpenThreads)
      const Suggestion(
          'advance-thread', 'Advance a thread', SuggestionAction.navigate),
    if (encounterActive)
      const Suggestion('combat-turn', 'Take a turn', SuggestionAction.navigate),
    if (ironswornFamily && hasFocusCharacter)
      const Suggestion('make-move', 'Make a move', SuggestionAction.navigate),
  ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/suggestions_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/suggestions.dart test/suggestions_test.dart
git commit -m "feat(assistant): SuggestionEngine (pure rule-based)"
```

---

### Task 2: fateCheckGenResult helper (DRY the Fate-Check → journal mapping)

The inline `roll-oracle` chip and `FateScreen` both turn a `FateResult` into a
`GenResult` for the journal. Extract the existing inline construction in
`fate_screen.dart` into one pure helper.

**Files:**
- Modify: `lib/engine/oracle.dart` (add helper near `fateCheck`)
- Modify: `lib/features/fate_screen.dart` (use the helper)
- Test: `test/suggestions_test.dart` (append a group) — or a small `oracle` test

- [ ] **Step 1: Write the failing test** (append to `test/suggestions_test.dart`)

```dart
// add import at top: import 'package:juice_oracle/engine/oracle.dart';
  group('fateCheckGenResult', () {
    test('wraps a FateResult into a journal GenResult', () {
      final oracle = Oracle.forTest(); // see note in Step 3
      final r = oracle.fateCheck(Likelihood.normal);
      final g = fateCheckGenResult(r);
      expect(g.title, 'Fate Check');
      expect(g.rolls.map((x) => x.label), containsAll(['Answer', 'Intensity']));
      expect(g.asText, isNotEmpty);
    });
  });
```

Note: if no `Oracle.forTest()` exists, build a `FateResult` directly (it is a
pure value — construct one with literal fields) instead of rolling. Inspect
`FateResult` in `lib/engine/oracle.dart` and construct a literal in the test;
do not load oracle assets in a unit test.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/suggestions_test.dart`
Expected: FAIL — `fateCheckGenResult` not found.

- [ ] **Step 3: Write minimal implementation**

In `lib/features/fate_screen.dart`, find the existing inline construction that
builds a `GenResult` from a Fate Check `FateResult` (the `Roll('Answer', …)` /
`Roll('Intensity', …)` block passed to `addResult`). Move that exact mapping
into a new top-level pure function in `lib/engine/oracle.dart`:

```dart
/// The journal representation of a Fate Check roll. Shared by the Fate screen
/// and the assistant rail's inline "Roll the oracle" so the mapping lives once.
GenResult fateCheckGenResult(FateResult result) {
  // Paste the EXACT GenResult(...) currently built inline in fate_screen.dart
  // (title 'Fate Check', summary, rolls: Answer + Intensity). Keep it identical.
}
```

Then in `fate_screen.dart`, replace the inline construction with a call to
`fateCheckGenResult(result)` (keep the surrounding `addResult(... sourceTool:
'fate-check', payload: g.toPayload())` call).

- [ ] **Step 4: Run tests**

Run: `flutter test test/suggestions_test.dart test/fate_screen_test.dart`
Expected: PASS (the Fate screen still logs identical journal output).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle.dart lib/features/fate_screen.dart test/suggestions_test.dart
git commit -m "refactor(oracle): extract fateCheckGenResult, shared by rail + fate screen"
```

---

### Task 3: AskGmSeed + prompt builder + parser (pure, budget-safe)

**Files:**
- Modify: `lib/engine/oracle_interpreter.dart` (add near the voice section)
- Test: `test/oracle_interpreter_test.dart` (append) — or a new `test/ask_gm_test.dart`

- [ ] **Step 1: Write the failing test** (new file `test/ask_gm_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';

void main() {
  group('buildAskGmPrompt', () {
    test('includes the question and the scene line when present', () {
      final p = buildAskGmPrompt(const AskGmSeed(
          question: 'Is the door locked?', sceneTitle: 'The vault'));
      expect(p, contains('Is the door locked?'));
      expect(p, contains('The vault'));
      expect(p, contains('OUTPUT'));
    });

    test('omits the scene line when no scene', () {
      final p =
          buildAskGmPrompt(const AskGmSeed(question: 'What do I smell?'));
      expect(p, contains('What do I smell?'));
      expect(p.toLowerCase(), isNot(contains('scene:')));
    });
  });

  group('parseAskGmResponse', () {
    test('strips think spans and trims', () {
      expect(parseAskGmResponse('<think>x</think>  Yes, it is locked. '),
          'Yes, it is locked.');
    });
    test('throws on empty', () {
      expect(() => parseAskGmResponse('  '), throwsFormatException);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ask_gm_test.dart`
Expected: FAIL — `AskGmSeed` / `buildAskGmPrompt` / `parseAskGmResponse` not found.

- [ ] **Step 3: Write minimal implementation**

In `lib/engine/oracle_interpreter.dart`, mirror the voice section
(`VoiceSeed`/`buildVoicePrompt`/`parseVoiceResponse`, using the existing `_flat`
and `_stripThink` helpers in that file):

```dart
// -- Ask the GM ---------------------------------------------------------------

const String _askGmInstruction =
    'You are the game master for a solo tabletop RPG. Answer the player\'s '
    'question in 1-3 sentences of plain prose. Be concrete and decisive.';

class AskGmSeed {
  const AskGmSeed({required this.question, this.sceneTitle});
  final String question;
  final String? sceneTitle;
}

/// Tiny, budget-safe prompt: instruction + optional scene line + question.
String buildAskGmPrompt(AskGmSeed seed) {
  final scene = seed.sceneTitle;
  final sceneLine =
      (scene == null || scene.trim().isEmpty) ? '' : 'scene: ${_flat(scene)}\n';
  return '$_askGmInstruction\n\n'
      'INPUT:\n'
      '$sceneLine'
      'question: ${_flat(seed.question)}\n'
      'OUTPUT:';
}

String parseAskGmResponse(String raw) {
  final out = _stripThink(raw).trim();
  if (out.isEmpty) throw const FormatException('Empty ask-the-GM response');
  return out;
}
```

(If `_flat`/`_stripThink` are private to a region, reuse them as the voice
builder does — they are top-level in this file.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ask_gm_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle_interpreter.dart test/ask_gm_test.dart
git commit -m "feat(assistant): AskGmSeed + budget-safe prompt/parse"
```

---

### Task 4: askGm seam — abstract + fake + Gemma impl

**Files:**
- Modify: `lib/state/interpreter.dart` (abstract method)
- Modify: `test/fake_interpreter.dart` (fake)
- Modify: `lib/state/interpreter_gemma.dart` (real, mirror `voiceLine`)
- Test: `test/interpreter_test.dart` (append, via fake)

- [ ] **Step 1: Write the failing test** (append to `test/interpreter_test.dart`)

```dart
  test('fake askGm captures the seed and returns queued text', () async {
    final fake = FakeInterpreter()..queuedAskGm.add('It is barred from within.');
    final out = await fake.askGm(
        const AskGmSeed(question: 'Locked?', sceneTitle: 'Vault'));
    expect(out, 'It is barred from within.');
    expect(fake.lastAskGmSeed?.question, 'Locked?');
    expect(fake.askGmCalls, 1);
  });
```

(Match the existing import style in `interpreter_test.dart`; it already imports
`fake_interpreter.dart` and `oracle_interpreter.dart`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/interpreter_test.dart`
Expected: FAIL — `askGm` not on `InterpreterService`/`FakeInterpreter`.

- [ ] **Step 3a: Abstract method** — in `lib/state/interpreter.dart`, beside `voiceLine`:

```dart
  /// Free-form GM answer to a player question (plain text). Same readiness
  /// contract as [voiceLine]: requires phase == ready.
  Future<String> askGm(AskGmSeed seed);
```

(Ensure `AskGmSeed` is importable — `oracle_interpreter.dart` is already
imported by this file for `VoiceSeed`.)

- [ ] **Step 3b: Fake** — in `test/fake_interpreter.dart`, mirror `voiceLine`:

```dart
  final List<String> queuedAskGm = [];
  AskGmSeed? lastAskGmSeed;
  int askGmCalls = 0;
  Object? askGmError;

  @override
  Future<String> askGm(AskGmSeed seed) async {
    lastAskGmSeed = seed;
    askGmCalls++;
    if (askGmError != null) throw askGmError!;
    if (queuedAskGm.isEmpty) return 'A canned GM answer.';
    return queuedAskGm.removeAt(0);
  }
```

- [ ] **Step 3c: Gemma impl** — in `lib/state/interpreter_gemma.dart`, add `askGm`
by mirroring the existing `voiceLine` method EXACTLY (same readiness guard,
session/watchdog handling, error wrapping), swapping only:
`buildVoicePrompt(seed)` → `buildAskGmPrompt(seed)` and
`parseVoiceResponse(raw)` → `parseAskGmResponse(raw)`. Read `voiceLine` in that
file and copy its structure verbatim with those two substitutions and the
`AskGmSeed` parameter type.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/interpreter_test.dart`
Expected: PASS.
Run: `flutter analyze lib/state/interpreter.dart lib/state/interpreter_gemma.dart test/fake_interpreter.dart`
Expected: No issues found (every `InterpreterService` impl now defines `askGm`).

- [ ] **Step 5: Commit**

```bash
git add lib/state/interpreter.dart lib/state/interpreter_gemma.dart test/fake_interpreter.dart test/interpreter_test.dart
git commit -m "feat(assistant): askGm interpreter seam (abstract + fake + gemma)"
```

---

### Task 5: suggestionsProvider

Derives the engine's booleans from existing providers. Returns a safe default
(at least `roll-oracle`) while sources load, so mounting the rail never breaks
the journal.

**Files:**
- Create: `lib/state/suggestions_provider.dart`
- Test: `test/suggestions_provider_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/suggestions.dart';
import 'package:juice_oracle/state/suggestions_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('empty campaign → roll-oracle + start-scene', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
      'juice.threads.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Sync provider over async sources: await the sources first, then read.
    await c.read(journalProvider.future);
    await c.read(threadsProvider.future);
    final ids = c.read(suggestionsProvider).map((e) => e.id).toList();
    expect(ids, contains('roll-oracle'));
    expect(ids, contains('start-scene'));
  });

  test('open thread + a scene → advance-thread + scene-event', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default':
          '[{"id":"s1","timestamp":"2026-06-18T00:00:00.000","title":"Scene","body":"","kind":"scene"}]',
      'juice.threads.v1.default':
          '[{"id":"t1","title":"Find it","open":true}]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    await c.read(threadsProvider.future);
    final ids = c.read(suggestionsProvider).map((e) => e.id);
    expect(ids, containsAll(['scene-event', 'advance-thread']));
  });
}

// NOTE: imports for this test — flutter_riverpod, flutter_test,
// juice_oracle/engine/suggestions.dart, juice_oracle/state/suggestions_provider.dart,
// juice_oracle/state/providers.dart (for journalProvider/threadsProvider),
// shared_preferences.
```

(Confirm the `JournalEntry` JSON keys/`kind` encoding by checking
`JournalEntry.toJson`/`fromJson` in `lib/engine/models.dart`; adjust the seeded
JSON to match exactly — especially how `kind: JournalKind.scene` serializes.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/suggestions_provider_test.dart`
Expected: FAIL — `suggestions_provider.dart` not found.

- [ ] **Step 3: Write minimal implementation**

Create `lib/state/suggestions_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/suggestions.dart';
import 'play_context.dart';
import 'providers.dart';

/// Ranked suggestions for the active campaign, derived from the play state.
/// A plain (sync) Provider: it reads each source's `valueOrNull`, treating
/// still-loading sources as empty, so it always yields at least the always-on
/// suggestions and a consumer mounted during load never crashes.
final suggestionsProvider = Provider<List<Suggestion>>((ref) {
  final journal = ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
  final threads = ref.watch(threadsProvider).valueOrNull ?? const <Thread>[];
  final encounter = ref.watch(encounterProvider).valueOrNull;
  final ctx = ref.watch(playContextProvider).valueOrNull;
  final systems =
      ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
          kAllSystems;
  final rulesets = ref.watch(rulesetsProvider).valueOrNull ?? const <String>{};

  final ironswornFamily = systems.contains('ironsworn') &&
      (rulesets.contains('classic') ||
          rulesets.contains('starforged') ||
          rulesets.contains('sundered_isles'));

  return suggestionsFor(
    hasScenes: journal.any((e) => e.kind == JournalKind.scene),
    hasOpenThreads: threads.any((t) => t.open),
    encounterActive: (encounter?.combatants.isNotEmpty) ?? false,
    ironswornFamily: ironswornFamily,
    hasFocusCharacter: ctx?.activeCharacterId != null,
  );
});
```

It is a plain `Provider<List<Suggestion>>` (sync). The rail reads it directly:
`ref.watch(suggestionsProvider)` returns the list. Tests await the async source
providers first (so their data is loaded), then read this synchronously.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/suggestions_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/suggestions_provider.dart test/suggestions_provider_test.dart
git commit -m "feat(assistant): suggestionsProvider derives chips from play state"
```

---

### Task 6: AssistantRail — chips (inline + navigate) + mount on Journal

**Files:**
- Create: `lib/features/assistant_rail.dart`
- Modify: `lib/features/journal_screen.dart` (mount atop the Column)
- Test: `test/assistant_rail_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/assistant_rail.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> pumpRail(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.journal.v2.default': '[]',
    'juice.threads.v1.default': '[]',
  });
  final c = ProviderContainer();
  await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AssistantRail()))));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('renders the always-on oracle chip', (tester) async {
    await pumpRail(tester);
    expect(find.text('Roll the oracle'), findsOneWidget);
  });

  testWidgets('navigate chip routes via shellRouteProvider', (tester) async {
    final c = await pumpRail(tester); // empty campaign → start-scene present
    await tester.tap(find.text('Start a scene'));
    await tester.pumpAndSettle();
    final route = c.read(shellRouteProvider);
    expect(route.destination, Destination.track);
    expect(route.subtab, 'scenes');
  });
}
```

(The inline-oracle journal-write test needs an `oracleProvider` override with a
test `Oracle` fixture — see Step 3 note. Add it once the rail compiles; if a
fixture `Oracle` is awkward, assert the inline path in a follow-up and keep this
task's tests to render + navigate.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/assistant_rail_test.dart`
Expected: FAIL — `assistant_rail.dart` not found.

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/assistant_rail.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/oracle.dart';
import '../engine/suggestions.dart';
import '../shared/destination.dart';
import '../shared/shell_route.dart';
import '../state/providers.dart';
import '../state/suggestions_provider.dart';

/// The assistant strip atop the Journal verb: rule-based suggestion chips
/// (plus the ask-the-GM box, added in a later task).
class AssistantRail extends ConsumerWidget {
  const AssistantRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(suggestionsProvider); // plain List<Suggestion>
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in suggestions)
            ActionChip(
              key: Key('suggest-${s.id}'),
              label: Text(s.label),
              onPressed: () => _onTap(context, ref, s),
            ),
        ],
      ),
    );
  }

  void _onTap(BuildContext context, WidgetRef ref, Suggestion s) {
    final route = ref.read(shellRouteProvider.notifier);
    switch (s.id) {
      case 'roll-oracle':
        final g = fateCheckGenResult(
            ref.read(oracleProvider).requireValue.fateCheck(Likelihood.normal));
        ref.read(journalProvider.notifier).addResult(g.title, g.asText,
            sourceTool: 'fate-check', payload: g.toPayload());
      case 'scene-event':
        final g = ref.read(oracleProvider).requireValue.randomEvent();
        ref.read(journalProvider.notifier).addResult(g.title, g.asText,
            sourceTool: 'mythic', payload: g.toPayload());
      case 'start-scene':
        route.goTo(Destination.track, subtab: 'scenes');
      case 'advance-thread':
        route.goTo(Destination.track, subtab: 'threads');
      case 'combat-turn':
        route.goTo(Destination.track, subtab: 'encounter');
      case 'make-move':
        route.goTo(Destination.sheet, subtab: 'moves');
    }
  }
}
```

Then mount it in `lib/features/journal_screen.dart`: in `build()`, make the
`AssistantRail` the FIRST child of the outer `Column` (before the `Expanded`
holding `async.when(...)`):

```dart
    return Column(
      children: [
        const AssistantRail(),
        Expanded(
          child: async.when( /* unchanged */ ),
        ),
        // unchanged composer block
      ],
    );
```

Add `import 'assistant_rail.dart';` to `journal_screen.dart`.

- [ ] **Step 4: Run tests**

Run: `flutter test test/assistant_rail_test.dart test/journal_screen_test.dart`
Expected: PASS. (If `journal_screen_test` now fails because the rail's providers
aren't seeded there, confirm `suggestionsProvider` degrades on AsyncLoading —
it does, via `valueOrNull ?? []` — and that `oracleProvider` is only `.read` on
tap, not on build, so mounting doesn't require oracle data.)

Run: `flutter analyze lib/features/assistant_rail.dart lib/features/journal_screen.dart`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add lib/features/assistant_rail.dart lib/features/journal_screen.dart test/assistant_rail_test.dart
git commit -m "feat(assistant): rail chips + mount on Journal"
```

---

### Task 7: Ask-the-GM box

Adds the input + send to `AssistantRail`. On submit: read the current scene
title (latest scene entry), call `askGm`, write one journal entry with the Q and
A. Guarded by interpreter readiness; errors write nothing.

**Files:**
- Modify: `lib/features/assistant_rail.dart` (convert to `ConsumerStatefulWidget`; add the field + handler)
- Test: `test/assistant_rail_test.dart` (append)

- [ ] **Step 1: Write the failing test** (append)

```dart
  testWidgets('ask-the-GM writes a Q&A journal entry via the fake', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
      'juice.threads.v1.default': '[]',
    });
    final fake = FakeInterpreter()
      ..setReady() // mark phase ready — match the fake's readiness API
      ..queuedAskGm.add('The door is barred from within.');
    final c = ProviderContainer(overrides: [
      interpreterServiceProvider.overrideWith((ref) => fake),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: AssistantRail()))));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('ask-gm-field')), 'Locked?');
    await tester.tap(find.byKey(const Key('ask-gm-send')));
    await tester.pumpAndSettle();

    expect(fake.askGmCalls, 1);
    final entries = await c.read(journalProvider.future);
    expect(entries.first.body, contains('The door is barred from within.'));
    expect(entries.first.body, contains('Locked?'));
  });
```

(Match the fake's actual readiness setter — inspect `test/fake_interpreter.dart`
for how other tests mark it ready, e.g. a `setReady()`/status field; and the
real provider name `interpreterServiceProvider`. Adjust the two names to the
codebase.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/assistant_rail_test.dart -n "ask-the-GM"`
Expected: FAIL — no `ask-gm-field`.

- [ ] **Step 3: Write minimal implementation**

Convert `AssistantRail` to `ConsumerStatefulWidget`. Add a `TextEditingController`,
a row under the chips with a `TextField(key: Key('ask-gm-field'))` and an
`IconButton(key: Key('ask-gm-send'))`. Handler:

```dart
  Future<void> _ask() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    final service = ref.read(interpreterServiceProvider);
    if (service.status.value != InterpreterStatus.ready) {
      setState(() => _error = 'Assistant not ready.');
      return;
    }
    final entries = ref.read(journalProvider).valueOrNull ?? const [];
    final scene = entries
        .where((e) => e.kind == JournalKind.scene)
        .map((e) => e.title)
        .firstOrNull;
    setState(() { _busy = true; _error = null; });
    try {
      final answer = await service.askGm(AskGmSeed(question: q, sceneTitle: scene));
      await ref.read(journalProvider.notifier).addResult(
          'Ask the GM', 'Q: $q\n\n$answer', sourceTool: 'ask-gm');
      _controller.clear();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the assistant.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
```

Add the imports: `../engine/models.dart`, `../engine/oracle_interpreter.dart`,
`../state/interpreter.dart`. Verify `InterpreterStatus.ready` is the correct
enum value (check `lib/state/interpreter.dart`). Show `_error` inline (a small
`Text` in the error color) when non-null; disable the send button while `_busy`.

- [ ] **Step 4: Run tests**

Run: `flutter test test/assistant_rail_test.dart`
Expected: PASS.
Run: `flutter analyze lib/features/assistant_rail.dart`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add lib/features/assistant_rail.dart test/assistant_rail_test.dart
git commit -m "feat(assistant): ask-the-GM box (budget-safe, writes Q&A to journal)"
```

---

### Task 8: Full verify + docs

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze` → No issues found.
Run: `flutter test` → All tests pass.

- [ ] **Step 2: CLAUDE.md note**

Add under "## Project notes":

```markdown
- The **assistant rail** (`lib/features/assistant_rail.dart`) sits atop the
  Journal verb: rule-based suggestion chips from a pure `SuggestionEngine`
  (`lib/engine/suggestions.dart`, `suggestionsFor`) wired by
  `suggestionsProvider` (`lib/state/suggestions_provider.dart`) off the
  PlayContext spine + journal/threads/encounter/rulesets. Inline chips
  (roll-oracle, scene-event) reuse the `oracle → journalProvider.addResult`
  pipeline (`fateCheckGenResult` shared with the Fate screen); navigate chips
  `shellRouteProvider.goTo`. "Ask the GM" uses `InterpreterService.askGm` (third
  LLM seam beside `voiceLine`/`summarize`; `buildAskGmPrompt`/`parseAskGmResponse`,
  tiny context = scene title only, within the ~1280-token budget) and writes one
  Q&A entry. Current scene is the latest `kind==scene` entry (no explicit
  activeScene pointer). See
  `docs/superpowers/specs/2026-06-18-assistant-rail-design.md`.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(assistant): document the assistant rail"
```

---

## Self-Review

**1. Spec coverage:**
- SuggestionEngine (pure, rule-based) → Task 1. ✓
- AssistantRail on Journal → Task 6. ✓
- Inline chips reuse roll→journal; navigate chips deep-link → Tasks 2, 6. ✓
- `askGm` seam (+ fake, budget-safe) → Tasks 3, 4. ✓
- suggestionsProvider derives from PlayContext + entities → Task 5. ✓
- Ask-the-GM context-aware + writes journal + error handling → Task 7. ✓
- Never construct GemmaInterpreterService in tests → all tests use the fake. ✓
- Tests green / format / analyze → Task 8. ✓

**Deviation from spec (deliberate):** the spec said the rail would *set*
`PlayContext.activeScene` (consuming a foundation pointer) and gate `scene-event`
on `hasActiveScene`. Investigation found "current scene" is already implicit
(the latest `kind==scene` entry, used by `_sceneContext`/`_CampaignHeader`).
Introducing a redundant `activeScene` pointer would be speculative duplication,
so v1 reuses the implicit latest-scene and gates on `hasScenes`. The
`activeScene` pointer stays unwired (a genuinely deferred item); `hasFocusCharacter`
already consumes `activeCharacterId` from the foundation, so the spine is not
left entirely write-only.

**2. Placeholder scan:** No "TBD"/"implement later". Notes that say "inspect X
and match" point at concrete existing code the implementer reads (FateResult
fields, JournalEntry JSON, fake readiness API, InterpreterStatus enum) rather
than leaving logic unspecified.

**3. Type consistency:** `Suggestion{id,label,action}`, `SuggestionAction
.{inline,navigate}`, `suggestionsFor({hasScenes,hasOpenThreads,encounterActive,
ironswornFamily,hasFocusCharacter})`, `fateCheckGenResult(FateResult)→GenResult`,
`AskGmSeed{question,sceneTitle}`, `buildAskGmPrompt`/`parseAskGmResponse`,
`askGm(AskGmSeed)`, `suggestionsProvider`, `AssistantRail` — consistent across
tasks. `suggestionsProvider` is a plain `Provider<List<Suggestion>>`; the rail
consumes it with `ref.watch` directly (no AsyncValue unwrap) — consistent across
Tasks 5 and 6.
