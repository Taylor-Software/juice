# AI Expansion #1: Richer Campaign Context — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ground every AI seam in real play — recall-ranked journal, the active scene, the active player character, and the system primer — and loosen the legacy web-era context caps for the desktop/mobile model.

**Architecture:** A shared pure `recallLines` formatter + an `activeCharacterLine` PC descriptor (engine), surfaced as `activeCharacterLineProvider`. The three seeds (`OracleSeed`/`VoiceSeed`/`AskGmSeed`) gain a `pc:` line; `askGm` is brought to parity (journal + scene + primer + pc). Recall caps bump 2→6 entries / 100→280 chars.

**Tech Stack:** Dart, Flutter, flutter_riverpod, flutter_test. Reuses `relatedEntries` (journal_search), `playContextProvider`, `charactersProvider`, `systemPrimerProvider`.

---

## File Structure

- **Modify** `lib/engine/oracle_interpreter.dart` — `recallLines`, `activeCharacterLine`, `_pcLine`, looser `kRecall*` consts, `activeCharacter` on the 3 seeds, `pc:` line in the 3 prompt builders, enriched `AskGmSeed` + `buildAskGmPrompt`.
- **Modify** `lib/state/providers.dart` — `activeCharacterLineProvider`.
- **Modify** `lib/features/journal_screen.dart` — `_interpret`/`_voiceEntry` use `recallLines` + pass `activeCharacter`.
- **Modify** `lib/features/sidekick_screen.dart` — voice call uses `recallLines` + `activeCharacter`.
- **Modify** `lib/features/assistant_rail.dart` — build the enriched `AskGmSeed`.
- **Test** `test/oracle_interpreter_test.dart`, `test/ask_gm_test.dart`, a `providers` test.

---

## Task 1: Pure helpers + looser budgets

**Files:**
- Modify: `lib/engine/oracle_interpreter.dart`
- Test: `test/oracle_interpreter_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/oracle_interpreter_test.dart` inside `void main()` (the file imports `package:juice_oracle/engine/oracle_interpreter.dart`; it also needs `models.dart` for `JournalEntry`/`Character` — add `import 'package:juice_oracle/engine/models.dart';` if absent):

```dart
  group('recallLines', () {
    test('formats relatedEntries output as "Title — body" / body-only', () {
      final journal = [
        JournalEntry(
            id: '1',
            timestamp: DateTime(2026, 1, 1),
            title: 'The Tower',
            body: 'A black gate guards the ruined tower.'),
        JournalEntry(
            id: '2',
            timestamp: DateTime(2026, 1, 2),
            title: '',
            body: 'The black gate is sealed with old runes.'),
      ];
      final target = JournalEntry(
          id: 't',
          timestamp: DateTime(2026, 1, 3),
          title: 'gate',
          body: 'the black gate and the tower');
      final lines = recallLines(journal, target);
      expect(lines, isNotEmpty);
      // Titled entries render "Title — body"; untitled render body only.
      expect(lines.any((l) => l.startsWith('The Tower — ')), isTrue);
      expect(lines.any((l) => l == 'The black gate is sealed with old runes.'),
          isTrue);
    });
  });

  test('recall budget is loosened for the on-device model', () {
    expect(kRecallMaxEntries, 6);
    expect(kRecallMaxChars, 280);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/oracle_interpreter_test.dart`
Expected: FAIL — `recallLines` undefined; `kRecallMaxEntries`/`kRecallMaxChars` are still 2/100.

- [ ] **Step 3: Implement**

In `lib/engine/oracle_interpreter.dart`:

(a) Change the budget constants:

```dart
const int kRecallMaxEntries = 2;
const int kRecallMaxChars = 100;
```

to:

```dart
// Recall budget. AI is desktop/mobile-only now (Gemma 4 E2B, ample window);
// these were tiny holdovers from the retired ~1280-token web model.
const int kRecallMaxEntries = 6;
const int kRecallMaxChars = 280;
```

(b) Confirm the file imports `journal_search.dart` (for `relatedEntries`) and `models.dart` (for `JournalEntry`/`Character`). Add whichever is missing near the other imports:

```dart
import 'journal_search.dart';
import 'models.dart';
```

(c) Add the `recallLines` helper after the `OracleSeed` class (before `OracleInterpretation`):

```dart
/// The recall-ranked journal lines for [target] (most-relevant past entries via
/// [relatedEntries]), formatted "Title — body" (or body only when untitled) for
/// any seam's `journalContext`. The prompt builders still take [kRecallMaxEntries]
/// and cap each at [kRecallMaxChars]. Pure.
List<String> recallLines(List<JournalEntry> journal, JournalEntry target) => [
      for (final e in relatedEntries(journal, target))
        e.title.isEmpty ? e.body : '${e.title} — ${e.body}',
    ];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/oracle_interpreter_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle_interpreter.dart test/oracle_interpreter_test.dart
git commit -m "feat(ai): recallLines helper + looser recall budgets

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Active-PC line on OracleSeed + VoiceSeed

**Files:**
- Modify: `lib/engine/oracle_interpreter.dart`
- Test: `test/oracle_interpreter_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/oracle_interpreter_test.dart` inside `void main()`:

```dart
  group('activeCharacterLine', () {
    test('null → empty', () => expect(activeCharacterLine(null), ''));
    test('PC with conditions → "Name (PC) — cond"', () {
      final c = Character(
          id: 'c1',
          name: 'Taurin',
          role: CharacterRole.pc,
          conditions: const ['wounded', 'hexed']);
      expect(activeCharacterLine(c), 'Taurin (PC) — wounded, hexed');
    });
    test('companion, no conditions → "Name (companion)"', () {
      final c = Character(
          id: 'c2', name: 'Vex', role: CharacterRole.companion);
      expect(activeCharacterLine(c), 'Vex (companion)');
    });
  });

  test('buildOraclePrompt renders a pc: line when present, omits when empty',
      () {
    final withPc = buildOraclePrompt(const OracleSeed(
        resultText: 'A door opens.', activeCharacter: 'Taurin (PC)'));
    expect(withPc, contains('\npc: Taurin (PC)\n'));
    final noPc = buildOraclePrompt(const OracleSeed(resultText: 'A door opens.'));
    expect(noPc, isNot(contains('pc:')));
  });

  test('buildVoicePrompt renders pc: distinct from the spoken character:', () {
    final p = buildVoicePrompt(const VoiceSeed(
        line: 'Hello there.',
        mood: 'default',
        characterName: 'The Innkeeper',
        activeCharacter: 'Taurin (PC)'));
    expect(p, contains('character: The Innkeeper')); // the spoken NPC
    expect(p, contains('pc: Taurin (PC)')); // the player character
  });
```

The test needs `Character`/`CharacterRole` — ensure `import 'package:juice_oracle/engine/models.dart';` is present (added in Task 1).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/oracle_interpreter_test.dart`
Expected: FAIL — `activeCharacterLine` undefined; `OracleSeed`/`VoiceSeed` have no `activeCharacter`; no `pc:` line.

- [ ] **Step 3: Implement**

In `lib/engine/oracle_interpreter.dart`:

(a) Add `activeCharacterLine` + the shared `_pcLine` helper after `recallLines`:

```dart
/// A short "who the PC is" line for the prompt, or '' when none. Facts-only:
/// name + role + any conditions. Pure.
String activeCharacterLine(Character? c) {
  if (c == null) return '';
  final role = switch (c.role) {
    CharacterRole.pc => 'PC',
    CharacterRole.companion => 'companion',
    CharacterRole.npc => 'NPC',
  };
  final cond = c.conditions.isEmpty ? '' : ' — ${c.conditions.join(', ')}';
  return '${c.name} ($role)$cond';
}

/// A capped `pc:` prompt line for the active player character, or '' when empty.
/// Distinct from voiceLine's `character:` line (the spoken NPC).
String _pcLine(String activeCharacter) {
  final f = _flat(activeCharacter);
  if (f.isEmpty) return '';
  final cut = f.length > kRecallMaxChars ? '${f.substring(0, kRecallMaxChars)}…' : f;
  return 'pc: $cut\n';
}
```

(Note: `_flat` is defined later in the file but Dart allows forward references for top-level functions — no ordering issue.)

(b) Add `activeCharacter` to `OracleSeed`. In its constructor add `this.activeCharacter = ''` (after `systemPrimer`) and the field `final String activeCharacter;` (after `journalContext`):

```dart
  const OracleSeed({
    required this.resultText,
    this.genre = '',
    this.tone = '',
    this.sceneContext = '',
    this.journalContext = const [],
    this.systemPrimer = '',
    this.activeCharacter = '',
  });
```

and after `final List<String> journalContext;` add:

```dart
  /// One-line active-PC descriptor (see activeCharacterLine), or '' for none.
  /// Renders as a `pc:` line.
  final String activeCharacter;
```

(c) In `buildOraclePrompt`, add the pc line after the `$systemLine`:

```dart
      '$systemLine'
      'result: ${_flat(seed.resultText)}\n'
```

becomes:

```dart
      '$systemLine'
      '${_pcLine(seed.activeCharacter)}'
      'result: ${_flat(seed.resultText)}\n'
```

(d) Add `activeCharacter` to `VoiceSeed` the same way — constructor `this.activeCharacter = ''` (after `systemPrimer`) and field:

```dart
  /// One-line active-PC descriptor (see activeCharacterLine), or '' for none.
  /// Renders as a `pc:` line (distinct from [characterName], the spoken NPC).
  final String activeCharacter;
```

(e) In `buildVoicePrompt`, add the pc line after `$systemLine`:

```dart
      '$systemLine'
      '${name == null ? '' : 'character: ${_flat(name)}\n'}'
```

becomes:

```dart
      '$systemLine'
      '${_pcLine(seed.activeCharacter)}'
      '${name == null ? '' : 'character: ${_flat(name)}\n'}'
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/oracle_interpreter_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle_interpreter.dart test/oracle_interpreter_test.dart
git commit -m "feat(ai): active-PC pc: line on OracleSeed + VoiceSeed

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Bring askGm to parity

**Files:**
- Modify: `lib/engine/oracle_interpreter.dart`
- Test: `test/ask_gm_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/ask_gm_test.dart` inside `void main()` (it imports `oracle_interpreter.dart`):

```dart
  test('buildAskGmPrompt grounds the question in system/pc/scene/recall', () {
    final p = buildAskGmPrompt(const AskGmSeed(
      question: 'Does the guard let me pass?',
      sceneTitle: 'The city gate at dusk',
      systemPrimer: 'Ironsworn: perilous Iron Lands; roll action vs challenge.',
      activeCharacter: 'Taurin (PC)',
      journalContext: ['The gate captain owes Taurin a favor.'],
    ));
    expect(p, contains('system: Ironsworn'));
    expect(p, contains('pc: Taurin (PC)'));
    expect(p, contains('scene: The city gate at dusk'));
    expect(p, contains('recall: The gate captain owes Taurin a favor.'));
    expect(p, contains('question: Does the guard let me pass?'));
  });

  test('buildAskGmPrompt omits empty grounding lines', () {
    final p = buildAskGmPrompt(const AskGmSeed(question: 'What now?'));
    expect(p, isNot(contains('system:')));
    expect(p, isNot(contains('pc:')));
    expect(p, isNot(contains('scene:')));
    expect(p, isNot(contains('recall:')));
    expect(p, contains('question: What now?'));
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ask_gm_test.dart`
Expected: FAIL — `AskGmSeed` has no `systemPrimer`/`activeCharacter`/`journalContext`; the prompt renders none of them.

- [ ] **Step 3: Implement**

In `lib/engine/oracle_interpreter.dart`, replace the `AskGmSeed` class + `buildAskGmPrompt`:

```dart
class AskGmSeed {
  const AskGmSeed({required this.question, this.sceneTitle});
  final String question;
  final String? sceneTitle;
}

/// Tiny, budget-safe prompt: instruction + optional scene line + question.
/// The question and scene title are length-capped (see [kAskGmMaxFieldChars]).
String buildAskGmPrompt(AskGmSeed seed) {
  final scene = seed.sceneTitle;
  final sceneLine = (scene == null || scene.trim().isEmpty)
      ? ''
      : 'scene: ${_capped(_flat(scene))}\n';
  return '$_askGmInstruction\n\n'
      'INPUT:\n'
      '$sceneLine'
      'question: ${_capped(_flat(seed.question))}\n'
      'OUTPUT:';
}
```

with:

```dart
class AskGmSeed {
  const AskGmSeed({
    required this.question,
    this.sceneTitle,
    this.systemPrimer = '',
    this.activeCharacter = '',
    this.journalContext = const [],
  });
  final String question;
  final String? sceneTitle;
  final String systemPrimer;
  final String activeCharacter;
  final List<String> journalContext;
}

/// Grounded prompt: instruction + optional system/pc/scene/recall lines, then
/// the question. The same line-keyed shape interpret/voice use. The question and
/// scene title are length-capped (see [kAskGmMaxFieldChars]); recall takes
/// [kRecallMaxEntries] lines capped at [kRecallMaxChars].
String buildAskGmPrompt(AskGmSeed seed) {
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
  return '$_askGmInstruction\n\n'
      'INPUT:\n'
      '$systemLine'
      '${_pcLine(seed.activeCharacter)}'
      '$sceneLine'
      '$recall'
      'question: ${_capped(_flat(seed.question))}\n'
      'OUTPUT:';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ask_gm_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle_interpreter.dart test/ask_gm_test.dart
git commit -m "feat(ai): askGm parity — system/pc/scene/recall grounding

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: activeCharacterLineProvider

**Files:**
- Modify: `lib/state/providers.dart`
- Test: `test/ai_context_provider_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `test/ai_context_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('activeCharacterLineProvider resolves the active PC, else empty',
      () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"c1","name":"Taurin","role":"pc","conditions":["wounded"]}]',
      'juice.context.v1.default': '{"activeCharacterId":"c1"}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(charactersProvider.future);
    await c.read(playContextProvider.future);
    expect(c.read(activeCharacterLineProvider), 'Taurin (PC) — wounded');
  });

  test('activeCharacterLineProvider is empty when no active character',
      () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(charactersProvider.future);
    await c.read(playContextProvider.future);
    expect(c.read(activeCharacterLineProvider), '');
  });
}
```

(If the persisted keys `juice.characters.v1` / `juice.context.v1` differ, the implementer should confirm them via `grep -n "characters.v1\|context.v1" lib/state/*.dart` and adjust the seed strings — the provider logic under test is unchanged.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ai_context_provider_test.dart`
Expected: FAIL — `activeCharacterLineProvider` undefined.

- [ ] **Step 3: Implement**

In `lib/state/providers.dart`, confirm `oracle_interpreter.dart` is imported (for `activeCharacterLine`); add `import '../engine/oracle_interpreter.dart';` if absent. Then add (near the other derived providers, e.g. beside `systemPrimerProvider`):

```dart
/// The active campaign's PC line for AI context: resolves
/// playContext.activeCharacterId against the roster, '' when unset/missing.
final activeCharacterLineProvider = Provider<String>((ref) {
  final id = ref.watch(playContextProvider).valueOrNull?.activeCharacterId;
  final chars = ref.watch(charactersProvider).valueOrNull ?? const <Character>[];
  final c = id == null ? null : chars.where((x) => x.id == id).firstOrNull;
  return activeCharacterLine(c);
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ai_context_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/ai_context_provider_test.dart
git commit -m "feat(ai): activeCharacterLineProvider (active-PC context)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: Wire the call sites

**Files:**
- Modify: `lib/features/journal_screen.dart`, `lib/features/sidekick_screen.dart`, `lib/features/assistant_rail.dart`
- Test: `test/ask_gm_widget_or_assistant_rail` (existing assistant-rail/ask-gm widget test — no regression)

- [ ] **Step 1: Establish the baseline (no new failing test — this is integration wiring)**

Run the existing AI-affordance widget tests to confirm they pass before changes:

Run: `flutter test test/ask_gm_test.dart test/voice_everywhere_test.dart`
Expected: PASS (baseline).

- [ ] **Step 2: Implement — `journal_screen.dart`**

In `_interpret`, change:

```dart
    final related = relatedEntries(
        ref.read(journalProvider).valueOrNull ?? const [], entry);
    final seed = OracleSeed(
      resultText:
          entry.title.isEmpty ? entry.body : '${entry.title}\n${entry.body}',
      sceneContext: _sceneContext(),
      journalContext: [
        for (final e in related)
          e.title.isEmpty ? e.body : '${e.title} — ${e.body}',
      ],
    );
```

to:

```dart
    final journal = ref.read(journalProvider).valueOrNull ?? const [];
    final seed = OracleSeed(
      resultText:
          entry.title.isEmpty ? entry.body : '${entry.title}\n${entry.body}',
      sceneContext: _sceneContext(),
      activeCharacter: ref.read(activeCharacterLineProvider),
      journalContext: recallLines(journal, entry),
    );
```

In `_voiceEntry`, change:

```dart
    final related = relatedEntries(
        ref.read(journalProvider).valueOrNull ?? const [], entry);
    final seed = VoiceSeed(
      line: entry.title.isEmpty ? entry.body : '${entry.title}\n${entry.body}',
      mood: 'default',
      genre: settings.genre,
      toneSetting: settings.tone,
      systemPrimer: ref.read(systemPrimerProvider),
      journalContext: [
        for (final e in related)
          e.title.isEmpty ? e.body : '${e.title} — ${e.body}',
      ],
    );
```

to:

```dart
    final journal = ref.read(journalProvider).valueOrNull ?? const [];
    final seed = VoiceSeed(
      line: entry.title.isEmpty ? entry.body : '${entry.title}\n${entry.body}',
      mood: 'default',
      genre: settings.genre,
      toneSetting: settings.tone,
      systemPrimer: ref.read(systemPrimerProvider),
      activeCharacter: ref.read(activeCharacterLineProvider),
      journalContext: recallLines(journal, entry),
    );
```

(`recallLines`/`activeCharacterLineProvider` resolve via the existing
`oracle_interpreter.dart` / `providers.dart` imports — both already imported in
journal_screen. If `relatedEntries` is now unused in this file, remove its
import only if `flutter analyze` flags it.)

- [ ] **Step 3: Implement — `sidekick_screen.dart`**

Change the VoiceSeed construction's `journalContext` from the inline loop to `recallLines`, and add `activeCharacter`. Replace:

```dart
      final related = relatedEntries(
          entries,
          JournalEntry(
            id: 'sd-voice-target',
            timestamp: DateTime.now(),
            title: 'Sidekick — ${_moodLabel(d.mood)}',
            body: _dialogueBody(selected, d),
          ));
      final voiced =
          await ref.read(interpreterServiceProvider).voiceLine(VoiceSeed(
                line: d.line,
                mood: d.mood,
                tone: d.tone,
                topic: d.topic,
                characterName: selected?.name,
                characterTags: selected?.tags ?? const [],
                genre: settings.genre,
                toneSetting: settings.tone,
                systemPrimer: ref.read(systemPrimerProvider),
                journalContext: [
                  for (final e in related)
                    e.title.isEmpty ? e.body : '${e.title} — ${e.body}',
                ],
```

with:

```dart
      final target = JournalEntry(
        id: 'sd-voice-target',
        timestamp: DateTime.now(),
        title: 'Sidekick — ${_moodLabel(d.mood)}',
        body: _dialogueBody(selected, d),
      );
      final voiced =
          await ref.read(interpreterServiceProvider).voiceLine(VoiceSeed(
                line: d.line,
                mood: d.mood,
                tone: d.tone,
                topic: d.topic,
                characterName: selected?.name,
                characterTags: selected?.tags ?? const [],
                genre: settings.genre,
                toneSetting: settings.tone,
                systemPrimer: ref.read(systemPrimerProvider),
                activeCharacter: ref.read(activeCharacterLineProvider),
                journalContext: recallLines(entries, target),
```

(Add `import '../engine/oracle_interpreter.dart';` to sidekick_screen.dart if
not already present — it constructs `VoiceSeed`, so it is.)

- [ ] **Step 4: Implement — `assistant_rail.dart`**

Replace the seed construction:

```dart
      final answer =
          await service.askGm(AskGmSeed(question: q, sceneTitle: scene));
```

with:

```dart
      final qTarget = JournalEntry(
          id: 'ask-gm-target',
          timestamp: DateTime.now(),
          title: '',
          body: q);
      final answer = await service.askGm(AskGmSeed(
        question: q,
        sceneTitle: scene,
        systemPrimer: ref.read(systemPrimerProvider),
        activeCharacter: ref.read(activeCharacterLineProvider),
        journalContext: recallLines(entries, qTarget),
      ));
```

Ensure `assistant_rail.dart` imports `oracle_interpreter.dart` (it constructs
`AskGmSeed`, so it does) and `models.dart` (for `JournalEntry`) — add
`import '../engine/models.dart';` if `flutter analyze` reports `JournalEntry`
undefined.

- [ ] **Step 5: Run analyze + the AI test suite + full suite**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test test/ask_gm_test.dart test/voice_everywhere_test.dart test/oracle_interpreter_test.dart` → expect PASS.
Run: `flutter test` → expect All tests passed.

- [ ] **Step 6: Commit**

```bash
git add lib/features/journal_screen.dart lib/features/sidekick_screen.dart lib/features/assistant_rail.dart
git commit -m "feat(ai): wire richer context into interpret/voice/askGm call sites

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 6: Doc sync — CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (the system-primer / interpreter bullet)

- [ ] **Step 1: Add a sentence to the system-primer bullet**

In `CLAUDE.md`, find the system-primer bullet (the one describing
`resolveSystemPrimer` / the `system:` INPUT line / `kSystemPrimerMaxChars`).
After its existing text, append:

```
  All four seams now share a grounded context block: recall-ranked recent
  journal (`recallLines` → `relatedEntries`), the active scene, and the active
  PC (`activeCharacterLine` / `activeCharacterLineProvider`, a `pc:` line distinct
  from voiceLine's spoken-NPC `character:` line). `askGm` was brought to parity
  (was question + scene title only). Recall caps were loosened from the retired
  web budget (`kRecallMaxEntries` 2→6, `kRecallMaxChars` 100→280) since AI is
  desktop/mobile-only. See
  `docs/superpowers/specs/2026-06-24-ai-richer-context-design.md`. This is
  foundation #1 of the AI-expansion epic (multi-turn GM chat + new affordances
  ride on it).
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note richer AI context in CLAUDE.md

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 shared recall formatter (`recallLines`) → Task 1. ✓
- §2 active PC (`activeCharacterLine` + `activeCharacterLineProvider` + `pc:` on seeds) → Tasks 2 (seeds/line) + 4 (provider). ✓
- §3 askGm parity → Task 3. ✓
- §4 looser budgets → Task 1. ✓
- Wiring all call sites → Task 5. ✓
- Testing (oracle_interpreter pure, providers, no-regression) → Tasks 1-5. ✓
- Out-of-scope items (multi-turn, new affordances) absent. ✓

**Type consistency:**
- `recallLines(List<JournalEntry>, JournalEntry) -> List<String>` defined Task 1, used Tasks 5. ✓
- `activeCharacterLine(Character?) -> String` defined Task 2, used Task 4. ✓
- `activeCharacter` field is `String` default `''` on all three seeds (Tasks 2/3); `pc:` line via `_pcLine` (defined Task 2, used Task 3). ✓
- `activeCharacterLineProvider` (Task 4) used at every call site (Task 5). ✓
- Label discipline: `pc:` = active PC everywhere; `character:` = voiceLine's spoken NPC (unchanged). ✓

**Placeholder scan:** No TBD/TODO; complete code per step. The provider test (Task 4) flags the persisted-key assumption explicitly with a grep fallback. ✓

**Risk note:** `_pcLine`/`activeCharacterLine` reference `_flat` and `Character` defined elsewhere in the engine — top-level Dart forward references are fine. Task 5 is integration wiring (no new unit test of its own); the existing `ask_gm_test`/`voice_everywhere_test` + analyze are the regression gate, and the enriched prompt builders are unit-tested in Tasks 2/3.
