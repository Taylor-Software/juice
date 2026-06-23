# GM Narration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A one-tap "GM narration" affordance — Continue the scene / Add a complication — that writes the next beat to the journal, grounded in the #1 context.

**Architecture:** A `narrate` seam (`NarrateSeed`/`buildNarratePrompt`) mode-parameterized over `{continueScene, complication}`, reusing the #1 grounding + the stateless `_generate`. A `composer-narrate` popup-menu button in the journal composer logs a `narrate` entry, mirroring the recap one-tap-AI pattern.

**Tech Stack:** Dart, Flutter, flutter_riverpod, flutter_test. Reuses `_generate`/`_flat`/`_capped`/`_pcLine`/`_stripThink`/`recallLines` (oracle_interpreter), `aiReadyProvider`/`_canVoice`, `systemPrimerProvider`, `activeCharacterLineProvider`, `_sceneContext`.

---

## File Structure

- **Modify** `lib/engine/oracle_interpreter.dart` — `NarrateMode`, `NarrateSeed`, `buildNarratePrompt`, `parseNarrateResponse`.
- **Modify** `lib/state/interpreter.dart` — `narrate` on the interface.
- **Modify** `lib/state/interpreter_gemma.dart` — `narrate` impl.
- **Modify** `test/fake_interpreter.dart` — `narrate` fake.
- **Modify** `lib/features/journal_screen.dart` — `_narrate(mode)` + `composer-narrate` menu.
- **Test** `test/oracle_interpreter_test.dart`, `test/narrate_test.dart` (new).

---

## Task 1: Seam — NarrateSeed + buildNarratePrompt

**Files:**
- Modify: `lib/engine/oracle_interpreter.dart`
- Test: `test/oracle_interpreter_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/oracle_interpreter_test.dart` inside `void main()`:

```dart
  group('buildNarratePrompt', () {
    test('continueScene grounds + uses the narrate-next-beat instruction', () {
      final p = buildNarratePrompt(const NarrateSeed(
        mode: NarrateMode.continueScene,
        sceneTitle: 'The collapsing bridge',
        systemPrimer: 'Ironsworn: perilous Iron Lands.',
        activeCharacter: 'Taurin (PC)',
        journalContext: ['The rope is fraying.'],
      ));
      expect(p, contains('Narrate the next beat'));
      expect(p, contains('system: Ironsworn'));
      expect(p, contains('pc: Taurin (PC)'));
      expect(p, contains('scene: The collapsing bridge'));
      expect(p, contains('recall: The rope is fraying.'));
      expect(p.trimRight(), endsWith('Narration:'));
    });

    test('complication uses the twist instruction', () {
      final p = buildNarratePrompt(
          const NarrateSeed(mode: NarrateMode.complication));
      expect(p, contains('complication or twist'));
      expect(p, isNot(contains('system:'))); // empty grounding omitted
      expect(p.trimRight(), endsWith('Narration:'));
    });

    test('parseNarrateResponse strips think + throws on empty', () {
      expect(parseNarrateResponse('<think>x</think> The bridge groans. '),
          'The bridge groans.');
      expect(() => parseNarrateResponse('  '), throwsFormatException);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/oracle_interpreter_test.dart`
Expected: FAIL — `NarrateMode`/`NarrateSeed`/`buildNarratePrompt`/`parseNarrateResponse` undefined.

- [ ] **Step 3: Implement**

In `lib/engine/oracle_interpreter.dart`, after the GM-chat section (`parseGmChatResponse`), add:

```dart
// -- GM narration -------------------------------------------------------------

enum NarrateMode { continueScene, complication }

class NarrateSeed {
  const NarrateSeed({
    required this.mode,
    this.sceneTitle,
    this.systemPrimer = '',
    this.activeCharacter = '',
    this.journalContext = const [],
  });
  final NarrateMode mode;
  final String? sceneTitle;
  final String systemPrimer;
  final String activeCharacter;
  final List<String> journalContext;
}

String _narrateInstruction(NarrateMode mode) => switch (mode) {
      NarrateMode.continueScene =>
        'You are the game master for a solo tabletop RPG. Narrate the next beat '
            'of the current scene in 1-3 sentences of vivid present-tense prose, '
            'advancing the action and staying consistent with the established '
            'facts. Output only the narration — no preamble, no options, no '
            'questions.',
      NarrateMode.complication =>
        'You are the game master for a solo tabletop RPG. Introduce ONE '
            'complication or twist that raises the stakes in the current scene, '
            'in 1-3 sentences of present-tense prose, consistent with the '
            'established facts. Output only the complication.',
    };

/// Mode-specific instruction + the #1 grounding (system/pc/scene/recall) + a
/// trailing `Narration:` cue. Caps mirror the other builders.
String buildNarratePrompt(NarrateSeed seed) {
  final scene = seed.sceneTitle;
  final sceneLine = (scene == null || scene.trim().isEmpty)
      ? ''
      : 'scene: ${_capped(_flat(scene))}\n';
  final primer = _flat(seed.systemPrimer);
  final systemLine = primer.isEmpty ? '' : 'system: ${_capped(primer)}\n';
  final recall = StringBuffer();
  for (final context in seed.journalContext.take(kRecallMaxEntries)) {
    final f = _flat(context);
    if (f.isEmpty) continue;
    final cut =
        f.length > kRecallMaxChars ? '${f.substring(0, kRecallMaxChars)}…' : f;
    recall.write('recall: $cut\n');
  }
  return '${_narrateInstruction(seed.mode)}\n\n'
      'INPUT:\n'
      '$systemLine'
      '${_pcLine(seed.activeCharacter)}'
      '$sceneLine'
      '$recall'
      'Narration:';
}

/// Plain-text parse (like parseAskGmResponse): strip think spans, trim, throw
/// on empty.
String parseNarrateResponse(String raw) {
  final out = _stripThink(raw).trim();
  if (out.isEmpty) throw const FormatException('Empty narration response');
  return out;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/oracle_interpreter_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle_interpreter.dart test/oracle_interpreter_test.dart
git commit -m "feat(ai): narrate seam — NarrateSeed + buildNarratePrompt (continue/complication)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Interface + impls (narrate)

**Files:**
- Modify: `lib/state/interpreter.dart`, `lib/state/interpreter_gemma.dart`, `test/fake_interpreter.dart`

- [ ] **Step 1: Add the interface method**

In `lib/state/interpreter.dart`, in `abstract class InterpreterService`, after the `gmChat` declaration add:

```dart
  /// GM narration: the next scene beat or a complication (plain text). Same
  /// readiness contract as the other seams. Requires ready.
  Future<String> narrate(NarrateSeed seed);
```

- [ ] **Step 2: Add the Gemma impl**

In `lib/state/interpreter_gemma.dart`, after the `gmChat` override add:

```dart
  @override
  Future<String> narrate(NarrateSeed seed) async {
    return parseNarrateResponse(await _generate(buildNarratePrompt(seed)));
  }
```

- [ ] **Step 3: Add the fake impl**

In `test/fake_interpreter.dart`, beside the gmChat fake fields add:

```dart
  int narrateCalls = 0;
  Object? narrateError;
  NarrateSeed? lastNarrateSeed;
  final List<String> queuedNarrate = [];
```

and the method (beside the `gmChat` override):

```dart
  @override
  Future<String> narrate(NarrateSeed seed) async {
    lastNarrateSeed = seed;
    narrateCalls++;
    if (narrateError != null) throw narrateError!;
    if (queuedNarrate.isEmpty) return 'A canned narration.';
    return queuedNarrate.removeAt(0);
  }
```

- [ ] **Step 4: Verify it compiles + existing tests pass**

Run: `flutter analyze lib/state/interpreter.dart lib/state/interpreter_gemma.dart test/fake_interpreter.dart` → expect no issues.
Run: `flutter test test/oracle_interpreter_test.dart test/interpreter_test.dart` → expect PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/interpreter.dart lib/state/interpreter_gemma.dart test/fake_interpreter.dart
git commit -m "feat(ai): narrate on InterpreterService (+ Gemma + fake impls)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: UI — composer narrate menu

**Files:**
- Modify: `lib/features/journal_screen.dart`
- Test: `test/narrate_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/narrate_test.dart`:

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
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Future<(ProviderContainer, FakeInterpreterService)> pumpJournal(
    WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.journal.v2.default':
        '[{"id":"1","timestamp":"2026-06-12T10:00:00.000","title":"Scene",'
            '"body":"At the gate.","kind":"scene"}]',
    'juice.ai_enabled.v1': true,
  });
  final fake =
      FakeInterpreterService(initial: const InterpreterStatus(InterpreterPhase.ready));
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
      home: const Scaffold(body: JournalScreen()),
    ),
  ));
  await tester.pumpAndSettle();
  final c = ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
  return (c, fake);
}

void main() {
  testWidgets('Continue the scene logs a Narration entry', (tester) async {
    final (c, _) = await pumpJournal(tester);
    await tester.tap(find.byKey(const Key('composer-narrate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('narrate-continue')));
    await tester.pumpAndSettle();
    final entries = c.read(journalProvider).valueOrNull ?? const [];
    final narr = entries.where((e) => e.sourceTool == 'narrate').toList();
    expect(narr, hasLength(1));
    expect(narr.single.title, 'Narration');
    expect(narr.single.body, 'A canned narration.');
  });

  testWidgets('Add a complication logs a Complication entry', (tester) async {
    final (c, _) = await pumpJournal(tester);
    await tester.tap(find.byKey(const Key('composer-narrate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('narrate-complication')));
    await tester.pumpAndSettle();
    final entries = c.read(journalProvider).valueOrNull ?? const [];
    final narr = entries.where((e) => e.sourceTool == 'narrate').toList();
    expect(narr, hasLength(1));
    expect(narr.single.title, 'Complication');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/narrate_test.dart`
Expected: FAIL — no `composer-narrate` widget.

- [ ] **Step 3: Implement**

In `lib/features/journal_screen.dart`:

(a) Add the `_narrate` method (place it right after the `_recap` method, ~line 240):

```dart
  Future<void> _narrate(NarrateMode mode) async {
    if (!_canVoice) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enable AI in Settings to narrate.')));
      return;
    }
    final journal = ref.read(journalProvider).valueOrNull ?? const [];
    // Recall ranks against the latest scene entry, else the newest entry.
    final target =
        journal.where((e) => e.kind == JournalKind.scene).firstOrNull ??
            journal.firstOrNull;
    final seed = NarrateSeed(
      mode: mode,
      sceneTitle: _sceneContext(),
      systemPrimer: ref.read(systemPrimerProvider),
      activeCharacter: ref.read(activeCharacterLineProvider),
      journalContext:
          target == null ? const [] : recallLines(journal, target),
    );
    final String text;
    try {
      text = await ref.read(interpreterServiceProvider).narrate(seed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Narration failed: $e')));
      }
      return;
    }
    await ref.read(journalProvider.notifier).addResult(
          mode == NarrateMode.continueScene ? 'Narration' : 'Complication',
          text,
          sourceTool: 'narrate',
        );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Added to journal')));
    }
  }
```

(b) In `_composerBar`, add the narrate button after the `composer-inspire`
`IconButton` (which ends `onPressed: () => showGenerateSheet(context)),`):

```dart
            if (ref.watch(aiReadyProvider))
              PopupMenuButton<NarrateMode>(
                key: const Key('composer-narrate'),
                icon: const Icon(Icons.auto_stories_outlined),
                tooltip: 'GM narration',
                onSelected: _narrate,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    key: Key('narrate-continue'),
                    value: NarrateMode.continueScene,
                    child: Text('Continue the scene'),
                  ),
                  PopupMenuItem(
                    key: Key('narrate-complication'),
                    value: NarrateMode.complication,
                    child: Text('Add a complication'),
                  ),
                ],
              ),
```

(`NarrateMode`/`NarrateSeed`/`recallLines`/`activeCharacterLineProvider`/
`systemPrimerProvider` resolve via the existing imports — `oracle_interpreter.dart`,
`play_context.dart`, and `providers.dart` are all already imported by
journal_screen.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/narrate_test.dart`
Expected: PASS.

- [ ] **Step 5: Run analyze + full suite**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test` → expect All tests passed.

- [ ] **Step 6: Commit**

```bash
git add lib/features/journal_screen.dart test/narrate_test.dart
git commit -m "feat(ai): composer GM-narration menu (continue scene / complication)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Doc sync — CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (the AI-expansion #2 note)

- [ ] **Step 1: Append the #3 note**

In `CLAUDE.md`, find the "AI expansion #2 (multi-turn GM chat)" paragraph (ends
with "The single-shot `askGm` seam is retained but app-unused. See
`docs/superpowers/specs/2026-06-24-multi-turn-gm-chat-design.md`."). Immediately
after it, append:

```
  **AI expansion #3 (GM narration):** a one-tap `narrate(NarrateSeed)` seam
  (`NarrateMode {continueScene, complication}`) — mode-specific instruction +
  the #1 grounding + a `Narration:` cue via the fresh-chat `_generate`. The
  journal composer's `composer-narrate` popup (aiReady-gated) offers Continue the
  scene / Add a complication, logging a `narrate` journal entry (title
  "Narration"/"Complication"), mirroring the recap one-tap pattern. See
  `docs/superpowers/specs/2026-06-24-gm-narration-design.md`. Deferred AI
  affordances: flesh-out an entity (#4), LLM-ranked suggestion chips (#5).
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note GM narration in CLAUDE.md (AI expansion #3)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 seam (`NarrateMode`/`NarrateSeed`/`buildNarratePrompt`/`parseNarrateResponse`) → Task 1; interface+impls → Task 2. ✓
- §2 UI (`_narrate` + `composer-narrate` menu, aiReady-gated, logs `narrate`) → Task 3. ✓
- §3 recall target (latest scene else newest, empty → []) → Task 3 `_narrate`. ✓
- Testing (prompt both modes, parse, widget both modes) → Tasks 1, 3. ✓
- Out-of-scope (#4/#5) absent. ✓

**Type consistency:**
- `NarrateMode {continueScene, complication}` + `NarrateSeed{mode,sceneTitle,systemPrimer,activeCharacter,journalContext}` (Task 1) used in `narrate` (Task 2 interface/Gemma/fake) + `_narrate` (Task 3). ✓
- `narrate(NarrateSeed) -> Future<String>` consistent across interface/Gemma/fake (Task 2) + call (Task 3). ✓
- Keys `composer-narrate`/`narrate-continue`/`narrate-complication` consistent between Task 3 impl + test. ✓
- Entry titles 'Narration'/'Complication' + `sourceTool: 'narrate'` consistent between Task 3 impl + test. ✓

**Placeholder scan:** No TBD/TODO; complete code per step. ✓

**Risk note:** `_narrate` mirrors `_recap` (same gate/error/log shape); the widget test seeds a `scene` entry so `_sceneContext()` + the recall target resolve. `PopupMenuButton` opens on tap then the item tap selects — `pumpAndSettle` between covers the menu animation.
