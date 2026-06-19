# Assistant Rail — Design

**Status:** Approved

## Problem

The app should "hold the player's hand" — surface the few relevant moves for the
current moment and use the on-device LLM where it adds value. The PlayContext
spine (shipped) makes the play-state readable; this thread builds the assistant
that consumes it.

**Hard constraint:** the on-device interpreter has a **~1280-token total
budget** on web (instruction ≈700, output ≈250 for the existing oracle lens;
very little left for input). A 1B model is unreliable at *structured* output.
So suggestions are **rule-based** (deterministic, offline, reliable); the LLM is
reserved for free-form natural language ("ask the GM") and the already-existing
oracle interpretation.

## Scope

**In (v1):**
- `SuggestionEngine` — pure Dart, `(PlayContext + campaign flags) → ranked
  List<Suggestion>`. No LLM.
- `AssistantRail` — a collapsible strip on the **Journal** verb: a chip row +
  an "ask the GM" input.
- Inline chip execution for oracle/scene-event (reuse the existing
  roll→journal pipeline); navigate chips deep-link via `shellRouteProvider`.
- `askGm` on `InterpreterService` (+ fake + prompt builder): tiny-context,
  budget-safe; writes the question and answer to the journal.

**Out (later threads / v2):**
- LLM-generated or LLM-ranked suggestions.
- Per-system richer rule sets; scene-event tuning beyond a single source.
- Multi-turn GM conversation / memory beyond one Q&A.
- Suggestion analytics.
- Wiring `PlayContext.activeScene`. v1 reuses the **implicit current scene** —
  the latest `kind==scene` journal entry (the existing `_sceneContext` /
  `_CampaignHeader` convention) — so the engine gates on `hasScenes`, and the
  `setActiveScene` notifier (foundation API) stays unwired until a thread needs
  non-chronological scene selection.

## Components

### `Suggestion` + `SuggestionEngine` — `lib/engine/suggestions.dart` (new, pure)

```
enum SuggestionAction { inline, navigate }

class Suggestion {
  final String id;        // stable key, e.g. 'roll-oracle'
  final String label;     // 'Roll the oracle'
  final SuggestionAction action;
}

List<Suggestion> suggestionsFor({
  required bool hasScenes,
  required bool hasOpenThreads,
  required bool encounterActive,
  required bool ironswornFamily,
  required bool hasFocusCharacter,
});
```

Pure function of explicit booleans (not providers) so it is trivially testable.
A thin `suggestionsProvider` (in `lib/state/`) derives those booleans from
`playContextProvider` + `journalProvider`/`threadsProvider`/`encounterProvider`
+ enabled systems/rulesets, then calls `suggestionsFor`.

### v1 rules (ranked, ~6)

| Condition | id / label | Action |
|---|---|---|
| always | `roll-oracle` "Roll the oracle" | inline |
| `!hasScenes` | `start-scene` "Start a scene" | navigate → Track/scenes |
| `hasScenes` | `scene-event` "Scene event" | inline |
| `hasOpenThreads` | `advance-thread` "Advance a thread" | navigate → Track/threads |
| `encounterActive` | `combat-turn` "Take a turn" | navigate → Track/encounter |
| `ironswornFamily && hasFocusCharacter` | `make-move` "Make a move" | navigate → Sheet/moves |

`start-scene` and `scene-event` are mutually exclusive on `hasScenes` (no
scenes → start one; scenes exist → roll an event in the current/latest scene).
Ranking: inline-now actions before navigation; the always-on `roll-oracle`
leads. All context-filtered chips render (≤6, reflowing in a `Wrap`); `ask the
GM` is always present below the chips when the rail is expanded.

### `AssistantRail` — `lib/features/assistant_rail.dart` (new)

A `ConsumerStatefulWidget` rendered at the top of the Journal verb, inside a
collapsible container (**collapsed by default** — a thin header keeps the journal
primary; one tap reveals chips + ask box; collapse state is local UI, not
persisted in v1). Renders the chips from `suggestionsProvider` and the ask-the-GM
field.

- **inline chip** → run the action and append a journal block. `roll-oracle`
  and `scene-event` reuse the existing oracle roll→journal path (which already
  optionally LLM-interprets), so no new roll/interpret code.
- **navigate chip** → `ref.read(shellRouteProvider.notifier).goTo(dest, subtab:
  key)` using `toolLocation`-style targets.

### Ask-the-GM — `InterpreterService.askGm`

New seam method mirroring `voiceLine`/`summarize`:

```
Future<String> askGm(AskGmSeed seed); // seed: { question, sceneTitle? }
```

`buildAskGmPrompt` keeps the instruction short (~120 tokens, e.g. "You are the
GM for a solo RPG. Answer the player's question in 1–3 sentences of plain
prose."), prepends only the active scene title (if any) as context, then the
question. Both question and scene title are length-capped
(`kAskGmMaxFieldChars`). Output target ≤ ~150 tokens. The fake interpreter
returns a canned string; **tests never construct GemmaInterpreterService**. On
submit, the rail writes ONE journal entry (`'Ask the GM'`, body `Q: <q>\n\n
<answer>`, `sourceTool: 'ask-gm'`) via `journalProvider.notifier.addResult`.

## Data flow

`PlayContext + entity providers → suggestionsProvider → AssistantRail chips`.
Inline chip → oracle engine → `journalProvider.addResult` (+ optional interpret).
Navigate chip → `shellRouteProvider.goTo`. Ask-the-GM → `InterpreterService
.askGm` → `journalProvider.addResult` (one Q&A entry). The current scene fed to
`askGm` is the latest `kind==scene` entry (implicit, not a stored pointer).

## Error handling

- LLM unavailable / not ready / throws / times out: ask-the-GM shows an inline
  error in the rail and writes nothing to the journal (no half-written Q with no
  A). Reuse the existing interpreter readiness/error surface.
- Empty question: submit is a no-op.
- Inline roll failures surface like the existing oracle tools do.
- Suggestions never depend on the LLM, so the chip row always works offline.

## Testing

- `suggestions_test.dart` — `suggestionsFor` truth table: each condition toggles
  the expected chip in/out; ranking/cap held; always-on `roll-oracle` present.
- `suggestions_provider_test.dart` — provider maps seeded campaign state
  (sessions/journal/threads/characters) to the right boolean inputs (override
  data providers / mock prefs per the rootBundle-hang rule; never call asset
  `.load()`).
- `assistant_rail_test.dart` — rail renders chips from the provider; tapping an
  inline chip adds a journal entry; tapping a navigate chip calls `goTo` with the
  right target; ask-the-GM submit (with the fake interpreter) writes Q + A
  blocks; LLM error writes nothing and shows the error.
- Full suite stays green; `dart format` + `flutter analyze` clean.

## Decomposition (this thread, then later)

1. **This spec** — engine + rail + 6 rules + inline-oracle + ask-the-GM.
2. LLM-ranked / generated suggestions (when a larger model or budget allows).
3. Per-system rule packs; richer scene-event source.
4. Multi-turn GM conversation.

## Docs

- Add a `CLAUDE.md` project note: the SuggestionEngine (pure, rule-based),
  `suggestionsProvider`, the AssistantRail on Journal, and `askGm` as the third
  LLM seam alongside `voiceLine`/`recap`, all under the ~1280-token budget.
- No new licensed content — rules are authored facts; the LLM only phrases.
