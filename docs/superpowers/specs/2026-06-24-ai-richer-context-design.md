# AI expansion #1: richer campaign context

**Date:** 2026-06-24
**Status:** Design — approved

## Problem

The on-device interpreter has four seams — `interpret` (oracle), `voiceLine`
(NPC voice), `summarize` (recap), `askGm` (assistant-rail Q&A). Their context is
uneven and starved:

- `interpret` and `voiceLine` get recall-ranked recent journal
  (`relatedEntries`) + scene + system primer — but the recall budget is tiny.
- `askGm` gets **only** the question + the latest scene *title* — no journal, no
  character, no primer.
- **No** seam carries the **active player character** (who the PC is).
- The recall caps are legacy from the retired ~1280-token web model:
  `kRecallMaxEntries = 2`, `kRecallMaxChars = 100` (≈ 50 tokens of journal). AI
  is now desktop/mobile-only (Gemma 4 E2B, far larger window), so these are
  pure dead headroom.
- The `relatedEntries(...) → journalContext` formatting is duplicated across
  `journal_screen._interpret`, `_voiceEntry`, and `sidekick_screen`.

This is the **foundation** of the AI-expansion epic: multi-turn GM chat (#2) and
new affordances (#3) are only as good as the context they ride on.

## Architecture

### 1. Shared recall formatter — `lib/engine/oracle_interpreter.dart`

DRY the duplicated block into one pure helper:

```dart
/// The recall-ranked journal lines for [target] (most-relevant past entries),
/// formatted "Title — body" for any seam's `journalContext`. Pure; the prompt
/// builders still cap each line at [kRecallMaxChars] and take [kRecallMaxEntries].
List<String> recallLines(List<JournalEntry> journal, JournalEntry target) => [
      for (final e in relatedEntries(journal, target))
        e.title.isEmpty ? e.body : '${e.title} — ${e.body}',
    ];
```

`_interpret`, `_voiceEntry`, and the sidekick voice call site all switch to
`recallLines(...)`.

### 2. Active player character in context

A pure one-line descriptor + a derived provider:

```dart
// oracle_interpreter.dart (pure)
/// A short "who the PC is" line for the prompt, or '' when none. Facts-only:
/// name + role + any conditions. Capped by the prompt builders.
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
```

```dart
// providers.dart (derived)
/// The active campaign's PC line for AI context: resolves
/// playContext.activeCharacterId against the roster, '' if unset/missing.
final activeCharacterLineProvider = Provider<String>((ref) {
  final id = ref.watch(playContextProvider).valueOrNull?.activeCharacterId;
  final chars = ref.watch(charactersProvider).valueOrNull ?? const <Character>[];
  final c = id == null ? null : chars.where((x) => x.id == id).firstOrNull;
  return activeCharacterLine(c);
});
```

`OracleSeed`, `VoiceSeed`, and `AskGmSeed` each gain a
`final String activeCharacter` field (default `''`), rendered as a
`character:` line in their prompt builders (capped). All call sites pass
`ref.read(activeCharacterLineProvider)`.

### 3. `askGm` brought to parity — `oracle_interpreter.dart` + `assistant_rail.dart`

`AskGmSeed` gains the grounding fields:

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
```

`buildAskGmPrompt` renders `system:` / `character:` / `scene:` / `recall:` lines
(each capped, recall taking `kRecallMaxEntries`) before `question:` — the same
shape `interpret`/`voice` use. The assistant rail builds the seed via
`recallLines(...)` against a **synthetic target entry** built from the question
(so recall ranks past entries by the question's terms):

```dart
final journal = ref.read(journalProvider).valueOrNull ?? const [];
final qTarget = JournalEntry(
    id: '', timestamp: DateTime.now(), title: '', body: q,
    kind: JournalKind.text);
final seed = AskGmSeed(
  question: q,
  sceneTitle: scene,
  systemPrimer: ref.read(systemPrimerProvider),
  activeCharacter: ref.read(activeCharacterLineProvider),
  journalContext: recallLines(journal, qTarget),
);
```

### 4. Loosen the budgets for the on-device model

```dart
const int kRecallMaxEntries = 6;   // was 2
const int kRecallMaxChars = 280;   // was 100
```

Update the stale "the web model's context may be as small as 1280 tokens" doc
comment in `oracleSystemInstruction` to note AI is desktop/mobile-only (Gemma 4
E2B) and the context is a few hundred tokens of grounding. No model/runtime
change — purely the formatter caps.

## Testing

- `oracle_interpreter` pure tests:
  - `recallLines` formats `relatedEntries` output as "Title — body" / body-only.
  - `activeCharacterLine`: null → ''; a PC with conditions → "Name (PC) — cond".
  - `buildAskGmPrompt` with the new fields renders `system:`/`character:`/`scene:`/
    `recall:` lines + the question; empty fields are omitted; lines are capped.
  - The recall constants are the new values (a guard so the budget isn't
    silently reverted).
- `providers` test: `activeCharacterLineProvider` resolves the active PC's line;
  '' when `activeCharacterId` is null or missing from the roster.
- `assistant_rail` widget test (existing harness): asking the GM still logs one
  Q&A entry (no behavior regression; the fake interpreter ignores the richer
  seed).

## Out of scope (later sub-projects)

- Multi-turn / conversation history (#2); new AI affordances like
  narrate/continue-scene or LLM-ranked chips (#3); per-campaign AI override;
  unloading the model on disable; token-accurate budgeting (char caps stay the
  proxy); changing the model or its runtime.

## Files touched

| File | Change |
|------|--------|
| `lib/engine/oracle_interpreter.dart` | `recallLines`, `activeCharacterLine`, `activeCharacter` on the 3 seeds, `buildAskGmPrompt` grounding lines, looser `kRecall*` consts |
| `lib/state/providers.dart` | `activeCharacterLineProvider` |
| `lib/features/journal_screen.dart` | `_interpret`/`_voiceEntry` use `recallLines` + pass `activeCharacter` |
| `lib/features/sidekick_screen.dart` | voice call uses `recallLines` + `activeCharacter` |
| `lib/features/assistant_rail.dart` | build the enriched `AskGmSeed` |
| tests | `oracle_interpreter`, `providers`, `assistant_rail` |
