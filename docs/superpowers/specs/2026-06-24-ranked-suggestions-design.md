# AI expansion #5: LLM-ranked suggestion chips

**Date:** 2026-06-24
**Status:** Design — approved

## Problem

The assistant rail shows a fixed, rule-ordered set of next-move chips (`Roll the
oracle`, `Scene event`, `Advance a thread`, …). The order is static — it doesn't
reflect what's most useful *right now*. This is the fifth and final AI affordance
on the #1 richer-context foundation: the LLM **reorders** the existing chips by
relevance to the current scene **and annotates the top pick with a one-line "why
now"** — the rationale is the real value-add over a bare reorder. The fixed chip
set and tap handlers are unchanged; the model only reorders + explains.

## Decisions (from brainstorming)

- **Rank + rationale**, not generate-new: the chips stay a fixed set with
  deterministic handlers; the LLM returns an ordering + a one-sentence reason.
- The LLM call is tied to the rail's **expanded + aiReady** lifecycle (no
  background spend when collapsed), **cached by a play-state signature** so it
  fires only when the state actually changes.
- **Graceful, non-blocking:** loading / error / AI-off → the rule order with no
  caption. The model can never shrink, break, or block the chips.

## Architecture

### 1. Seam — `oracle_interpreter.dart` + `interpreter.dart`

```dart
class RankSuggestionsSeed {
  const RankSuggestionsSeed({
    required this.candidates, // [(id, label)] in rule order
    this.systemPrimer = '',
    this.sceneTitle,
    this.activeCharacter = '',
    this.journalContext = const [],
  });
  final List<({String id, String label})> candidates;
  final String systemPrimer;
  final String? sceneTitle;
  final String activeCharacter;
  final List<String> journalContext;
}

class RankResult {
  const RankResult({this.order = const [], this.why = ''});
  final List<String> order; // suggestion ids, most→least useful
  final String why;         // one-line rationale for the top pick
}
```

`buildRankPrompt(RankSuggestionsSeed)` — a fixed instruction, the **#1 grounding**
(`system:`/`pc:`/`scene:`/`recall:` via the existing helpers), the candidate
lines (`- {id}: {label}`), and a JSON cue. Instruction: *"You are the game master
for a solo tabletop RPG. Given the current scene and these candidate next moves,
output the move ids ordered most-to-least useful right now, and one short
sentence on why the top one fits. Output ONLY JSON: {"order":["id",…],"why":"…"}."*

`parseRankResult(String) → RankResult` — **tolerant, never throws** (ranking is
best-effort): reuse `_isolateJson` + `jsonDecode`; pull `order` as a
`List<String>` (string-coerced, non-string entries dropped) and `why` as a
trimmed string. Any failure (no JSON, malformed, wrong shape) → `RankResult()`
(empty) so the rail keeps the rule order.

`InterpreterService.rankSuggestions(RankSuggestionsSeed) → Future<RankResult>`:
- Gemma: `parseRankResult(await _generate(buildRankPrompt(seed)))`.
- Fake: counter + optional error + queued/default `RankResult`.

### 2. Pure core — `suggestions.dart`

```dart
({List<Suggestion> chips, String? why}) applyRanking(
    List<Suggestion> ruleOrder, RankResult llm) { … }
```

Reorder `ruleOrder` by `llm.order`: take each known id once in the model's order,
then **append any rule chips the model omitted** (set never shrinks); **unknown
ids are dropped** (handlers always valid). `why` = `llm.why` trimmed, or `null`
when empty. No Riverpod — trivially unit-testable.

### 3. Rail integration — `assistant_rail.dart`

`suggestionsProvider` (sync, rule-based) stays the always-on source + fallback.
The rail's `State` gains:
- `final Map<String, RankResult> _rankCache = {}` keyed by a **signature** =
  `newest journal-entry id` + `active scene id` + the candidate id set joined;
- a `String? _ranking` in-flight guard.

`_maybeRank()`: when `_expanded && aiReady` and the current signature is neither
cached nor in-flight, build a `RankSuggestionsSeed` (candidates = the rule
`Suggestion`s mapped to `(id, label)`; `systemPrimer` = `systemPrimerProvider`;
`sceneTitle` = newest `JournalKind.scene` entry's title; `activeCharacter` =
`activeCharacterLineProvider`; `journalContext` = `recallLines(journal,
<newest scene or newest entry>)`), call `rankSuggestions`, store the result in
`_rankCache[sig]` (on error, store `const RankResult()` so we don't retry-loop),
`setState`. Invoked from the expand toggle and from a post-frame check in
`build` (via `addPostFrameCallback`, so no async-in-build).

Render: `final ranked = (aiReady && _rankCache[sig] != null) ? applyRanking(rule,
_rankCache[sig]!) : (chips: rule, why: null);` → the `Wrap` iterates
`ranked.chips` (same `suggest-<id>` keys, same `_onTap`); when `ranked.why !=
null`, a one-line caption (`Key('suggest-why')`, a small `💡 {why}` `Text`)
renders under the `Wrap`.

### 4. Robustness

- Model hallucinates an id → dropped (not in `byId`). Model omits a chip →
  appended at the end. Model returns nothing / malformed → empty `RankResult` →
  rule order, no caption. Generation throws (timeout) → caught in `_maybeRank`,
  cached as empty → rule order. The chip set is invariant under all model output.

## Testing

- `oracle_interpreter` test: `buildRankPrompt` renders the instruction +
  grounding + `- id: label` candidate lines + JSON cue; `parseRankResult` parses
  a clean object, tolerates fenced/think-wrapped JSON, and returns empty on
  garbage (no throw).
- `suggestions` test: `applyRanking` reorders by `order`, drops unknown ids,
  appends omitted rule chips, and maps empty `why` → `null`.
- `rankSuggestions` via the fake.
- `assistant_rail` widget test (fake interpreter, seeded journal): expanding with
  AI ready reorders the chips to the fake's `order` and shows the `suggest-why`
  caption; with AI off, chips stay in rule order and there's no caption.

## Out of scope

- Generating brand-new (free-text) suggestions; per-chip rationales (only the top
  pick is explained); a manual "re-rank" button (auto on expand + cache is
  enough); streaming; ranking the journal composer's inspire menu.
- This completes the AI-expansion epic (#1–#5).

## Files touched

| File | Change |
|------|--------|
| `lib/engine/oracle_interpreter.dart` | `RankSuggestionsSeed`, `RankResult`, `buildRankPrompt`, `parseRankResult` |
| `lib/state/interpreter.dart` | `rankSuggestions` on the interface |
| `lib/state/interpreter_gemma.dart` | `rankSuggestions` impl |
| `lib/engine/suggestions.dart` | `applyRanking` pure core |
| `test/fake_interpreter.dart` | `rankSuggestions` fake |
| `lib/features/assistant_rail.dart` | rank trigger + cache + reordered render + why caption |
| tests | prompt/parse, `applyRanking`, rail widget test |
