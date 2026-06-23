# AI expansion #3: GM narration (continue scene + complication)

**Date:** 2026-06-24
**Status:** Design — approved

## Problem

The solo loop is: roll the oracle (yes/no/event) → interpret → **narrate the
consequence** → journal. The app rolls and interprets, and now chats (#2), but
has no one-tap "the GM writes the next beat." This adds it — and its sibling,
"raise the stakes" — as the third AI affordance, on the #1 richer-context
foundation.

## Decisions (from brainstorming)

- Bundle **two narration modes** that share a seam + journal-log path: **Continue
  the scene** and **Add a complication** (they differ only in the prompt).
- Surface as **one composer button** (`composer-narrate`) opening a small menu
  (Continue / Complication), mirroring the existing recap/inspire one-tap-AI
  pattern; gated on `aiReadyProvider`.
- Logs a journal `result` entry (`sourceTool: 'narrate'`) — no chat, no
  separate state.

## Architecture

### 1. Seam — `oracle_interpreter.dart` + `interpreter.dart`

```dart
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
```

`buildNarratePrompt(NarrateSeed)` — a mode-specific instruction, then the **#1
grounding** (`system:` / `pc:` / `scene:` / `recall:`, capped, reusing the
existing helpers), then a trailing `Narration:` cue. Instructions:
- `continueScene`: "You are the game master for a solo tabletop RPG. Narrate the
  next beat of the current scene in 1-3 sentences of vivid present-tense prose,
  advancing the action and staying consistent with the established facts. Output
  only the narration — no preamble, no options, no questions."
- `complication`: "You are the game master for a solo tabletop RPG. Introduce
  ONE complication or twist that raises the stakes in the current scene, in 1-3
  sentences of present-tense prose, consistent with the established facts. Output
  only the complication."

`parseNarrateResponse(String)` — strip `<think>` + trim, throw on empty (mirrors
`parseAskGmResponse`).

`InterpreterService.narrate(NarrateSeed) → Future<String>`:
- `GemmaInterpreterService`:
  `parseNarrateResponse(await _generate(buildNarratePrompt(seed)))`.
- `FakeInterpreterService`: counter + optional error + canned reply (mirrors the
  `askGm`/`gmChat` fakes).

### 2. UI — `lib/features/journal_screen.dart`

A `_narrate(NarrateMode mode)` mirroring `_recap`:
- Gate on `_canVoice` (`aiReadyProvider`) — snackbar "Enable AI in Settings…"
  when off (the button is also hidden when not ready, so this is defensive).
- Build the `NarrateSeed`: `sceneTitle` = `_sceneContext()` (the same scene line
  Interpret uses); `systemPrimer` = `systemPrimerProvider`; `activeCharacter` =
  `activeCharacterLineProvider`; `journalContext` =
  `recallLines(journal, <latest scene or newest entry as target>)`.
- `await ref.read(interpreterServiceProvider).narrate(seed)` (with a busy guard
  + error snackbar).
- `addResult(mode == continueScene ? 'Narration' : 'Complication', text,
  sourceTool: 'narrate')`.

A **`composer-narrate`** `PopupMenuButton` in the composer button row (after
`composer-inspire`), rendered only when `ref.watch(aiReadyProvider)`; icon
`Icons.auto_stories_outlined`, two items keyed `narrate-continue` /
`narrate-complication` → `_narrate(...)`.

### 3. Recall target

Narration isn't ranked against a specific entry, so recall ranks against the
**latest scene entry** if present, else the **newest journal entry**; when the
journal is empty, `journalContext` is `[]` (the GM narrates from scene + primer
alone).

## Testing

- `oracle_interpreter` test: `buildNarratePrompt(continueScene)` renders the
  "Narrate the next beat" instruction + the grounding lines + `Narration:`;
  `complication` renders the "complication or twist" instruction; both omit empty
  grounding lines; `parseNarrateResponse` strips think / throws on empty.
- `narrate` exercised through the fake (Task: interface) — compiles + the screen
  test drives it.
- `journal` widget test (existing harness + fake interpreter, aiReady): tapping
  `composer-narrate` → `narrate-continue` adds one `narrate` journal entry titled
  "Narration"; `narrate-complication` adds one titled "Complication".

## Out of scope (future #4/#5)

- Flesh-out an entity (#4); LLM-ranked suggestion chips (#5); streaming;
  configurable narration length; auto-narrate after an oracle roll; a HUD
  quick-narrate.

## Files touched

| File | Change |
|------|--------|
| `lib/engine/oracle_interpreter.dart` | `NarrateMode`, `NarrateSeed`, `buildNarratePrompt`, `parseNarrateResponse` |
| `lib/state/interpreter.dart` | `narrate` on the interface |
| `lib/state/interpreter_gemma.dart` | `narrate` impl |
| `test/fake_interpreter.dart` | `narrate` fake |
| `lib/features/journal_screen.dart` | `_narrate(mode)` + `composer-narrate` menu |
| tests | `oracle_interpreter` (prompt), a journal narrate widget test |
