# Oracle Interpreter — on-device LLM readings (design)

Date: 2026-06-11. Status: approved.
Origin: user-provided brief + two Dart files (Claude chat), adapted to this
app's actual stack and data. Source files preserved in
`~/Downloads/llm/` (ORACLE_INTEGRATION.md, oracle_interpreter.dart,
oracle_interpretation_sheet.dart).

## Goal

Any oracle result logged to the journal can be expanded into 2-sentence
narrative interpretations by a small on-device LLM. Four cards per roll, one
per lens (literal / symbolic / complication / foreshadow); the player accepts
one, which appends to the journal entry. The dice stay authoritative — the
model only interprets; it never resolves outcomes or speaks for the player's
character.

## Decisions (user-confirmed)

| Question | Decision |
|---|---|
| Platforms | Both web and mobile from the start (web spike first) |
| Model | Split, forced by the spike (below): web = Gemma3 1B int4 `-web.task`, mobile = Qwen3 0.6B int4 `.litertlm`. No auth anywhere |
| Web weights source | User's own HF mirror of the official `gemma3-1b-it-int4-web.task` (user accepts the Gemma license, re-uploads under their account; clean provenance). Until that repo exists, development pins the `darkB/gemma3-1b-it-int4-web-litert` mirror; the URL is one constant to swap |
| Hook point | Journal result entries get an Interpret action (one wiring point, covers every tool) |
| Genre/tone | Per-campaign setting, new session-scoped key `juice.settings.v1` |
| Prompt grounding | Full journal entry text (title + body) — Juice/Mythic tables have no per-word meanings, so the brief's word+meaning pairs are replaced by the already-formatted result text |
| Approach | Direct port with thin service seam; two PRs (web first, then mobile config) |

## Verified facts (2026-06-11)

- `flutter_gemma` 0.16.5 (pub.dev). `createChat` accepts `temperature`
  (default .8), `topK` (default 1 — would kill variety), `topP`,
  `randomSeed`, `isThinking`, `modelType`, `systemInstruction`. The brief's
  "verify sampling params" step is resolved: set temp 1.0 / topK 64 /
  topP 0.95.
- Qwen3 0.6B artifacts are public (HTTP 302 to CDN, no token):
  - `https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3_0_6b_mixed_int4.litertlm` (475MB) — chosen.
  - `Qwen3-0.6B.litertlm` (586MB) — fallback if int4 quality disappoints.
  - No `.task` variant exists for Qwen3.
- Web `.litertlm` support in flutter_gemma is **early preview** (WebGPU via
  `@litert-lm/core`). The only proven public web models are gemma-4-E2B web
  builds at ~2GB (too heavy). Gemma 270M/1B web variants are gated
  (verified 401) — unusable from a shipped web app.

### Spike results (branch `spike/llm-web`, commit 63a783c)

- **Qwen3 on web is dead**: `@litert-lm/core` 0.12.1 and 0.13.1 both fail
  with "Streaming HF_Tokenizer_Zlib section is not supported yet" on the
  Qwen3 `.litertlm` files. Mobile-format `.task` (tried Qwen2.5 0.5B q8)
  dies in a MediaPipe WASM abort. On web, only `-web.task` builds work.
- **Gemma3 1B int4 `-web.task` (668MB) works end to end** in Chrome via
  MediaPipe/WebGPU: network install → Cache API persistence → model load
  (~40s warm) → generation (~50s). The renderer blocks during generation —
  the sheet must set expectations; acceptable v1.
- API facts: `FlutterGemma.initialize()` is required in `main()`;
  `installModel` needs an explicit `fileType: ModelFileType.litertlm` for
  litertlm artifacts (defaults to `.task`); web needs the MediaPipe
  tasks-genai script include in index.html for the `.task` path.
- Spike-prompt output was malformed JSON (cut-down prompt, no few-shot) —
  the tolerant parser's raw-fallback behavior is load-bearing, and the full
  few-shot prompt plus the quality bar below judge the rest.
- Gemma models would need an HF token; impossible to ship client-side. Qwen3
  needs none.
- Qwen3 license: Apache 2.0 — compatible with the app's non-commercial
  obligations; add attribution alongside Mythic/Datasworn credits.

## Architecture

Three units, one dependency added (`flutter_gemma`; CLAUDE.md lean-stack note
updated).

### 1. Engine — `lib/engine/oracle_interpreter.dart` (pure Dart)

No flutter_gemma import. Fully unit-testable.

- `OracleSeed { String resultText, String genre, String tone, String sceneContext }`
- `OracleInterpretation { String lens, String reading }`
- `kLenses = [literal, symbolic, complication, foreshadow]` — ordered safest
  to most surprising; naming the lenses is what forces a small model to
  diversify.
- `oracleSystemInstruction`: role + rules + JSON shape + two few-shot
  examples. Reworded from the brief: INPUT carries a `result:` block (the
  journal entry text) instead of `rolled:` word+meaning pairs. Few-shot
  examples rewritten to match real app output (one Fate Check line, one
  generator line). Player-agency rules unchanged (never resolve outcomes,
  never speak for the character; output ONLY a JSON object).
- `buildOraclePrompt(OracleSeed)` → per-roll user message.
- `parseInterpretations(String raw)` → tolerant parser: strips
  `<think>…</think>` spans (Qwen3 is a thinking model — belt and suspenders
  beside `isThinking: false`), strips ``` fences, isolates outermost
  `{…}`, validates shape. Any failure → single `raw`-lens fallback card.
  Never throws.

### 2. Service — `lib/state` (seam + flutter_gemma impl + providers)

- `InterpreterService` (abstract): `InterpreterStatus get status`
  (`notInstalled | installing(progress 0-100) | ready | unsupported`),
  `Future<void> warmUp()`, `Future<List<OracleInterpretation>>
  interpret(OracleSeed)`, `Future<void> dispose()`.
- `GemmaInterpreterService`: pins a per-platform model spec —
  web: `gemma3-1b-it-int4-web.task` (668MB, `ModelType.gemmaIt`,
  `ModelFileType.task`, user-mirror URL); mobile: `qwen3_0_6b_mixed_int4.litertlm`
  (475MB, `ModelType.qwen3`, `ModelFileType.litertlm`, official
  litert-community URL). `warmUp()` = `isModelInstalled` →
  `installModel.fromNetwork(url).withProgress(...)` → `getActiveModel(
  maxTokens: 1280, preferredBackend: gpu)`; on mobile, GPU init failure
  falls back to CPU. `interpret()` = fresh `createChat(systemInstruction:
  oracleSystemInstruction, temperature: 1.0, topK: 64, topP: 0.95,
  isThinking: false, modelType: <platform model type>)` per roll (no bleed
  across rolls), stream `TextResponse` tokens, parse.
- Riverpod: `interpreterServiceProvider` (plain `Provider`, overridden with a
  fake in every widget test) + status exposure for UI. App-global, not
  session-scoped — the on-disk model is shared across campaigns.
- Lifecycle: lazy. Nothing loads at app start. First Interpret tap shows a
  consent dialog ("Download ~475MB model? One time, stored on device") then
  warms with progress. Model stays warm for the session;
  `AppLifecycleListener` paused → `dispose()` (frees native session; reload
  after install is the cheap step).
- Web: `status == unsupported` when WebGPU is absent (`navigator.gpu`
  check); the Interpret action is hidden then. No token, no config.json.

### 3. UI — `lib/features/oracle_interpretation_sheet.dart` + journal wiring

- Journal result-kind entries get an **Interpret** action in the existing
  entry action row → `showModalBottomSheet` with the adapted provided sheet.
- Sheet states: consent (not installed) → progress (installing) →
  "Reading the omens…" (generating) → four lens cards. Accept appends
  `\n\n— Oracle reading (lens): <text>` to the entry body via the existing
  `journalProvider` edit path. Regenerate / swipe-to-discard /
  all-discarded-reroll as provided. Theme-driven styling as provided.
- Genre & tone: two short free-text fields per campaign, stored in
  session-scoped `juice.settings.v1` (`{"genre": "...", "tone": "..."}`),
  added to `sessionScopedKeys` and campaign export validation (schema stays
  v2 — additive key, absent = empty). Edited inline from the sheet header.
- Scene context: title of the latest scene-kind journal entry (+ chaos
  factor if set), pulled automatically. Empty if no scene exists. (Future
  RAG hook lives here, out of scope.)

## Phasing

**Phase 0 — web spike (throwaway, no PR).** Scratch branch: add
flutter_gemma, index.html script include, load the int4 litertlm in Chrome
over WebGPU, one prompt round-trip. Settles the early-preview risk before
real code. Fails → feature ships mobile-only, web hides the action; decision
returns to the user.

**Phase 1 PR — engine + service + UI + web.** TDD: engine unit tests
(prompt goldens; parser: clean / fenced / think-tags / garbage / empty /
partial). Fake-service widget tests for sheet states, accept-appends,
regenerate, all-dismissed, consent flow. Settings persistence +
campaign-export tests. CI never touches native code. Browser-verify live:
real download, real interpretation, accept lands in journal.

**Phase 2 PR — mobile config.** Android `ndk { abiFilters 'arm64-v8a' }` +
OpenCL `uses-native-library` manifest entries; iOS Podfile
`platform :ios, '16.0'` + `use_frameworks! :linkage => :static` +
`UIFileSharingEnabled`. Verify `flutter build apk` (arm64) at minimum;
runtime device verification is best-effort and disclosed in the PR (no
physical device in the dev environment).

## Quality bar (from the brief, kept)

1. JSON parse rate ≥ 95% across eval seeds (no raw-fallback cards).
2. Four lenses read as four distinct ideas — judged hardest on
   `complication` and `foreshadow`.
3. Tone genuinely shifts between genres (grimdark vs cozy must differ).

Eval harness trimmed to a debug-only `runEval` over 3 seeds (no 270M/1B A/B —
model is fixed). If Qwen3 0.6B fails 2 or 3 in live verification, report
findings; options are the 586MB full-precision artifact, prompt tightening,
or the 2GB public Gemma web build — user decides.

## Out of scope

- RAG / journal-memory retrieval (sceneContext is the future hook).
- Per-tool Interpret buttons (journal entries only).
- Model choice UI; multiple models; desktop platforms.
- Streaming tokens into the cards (cards appear when complete).

## Risks (accepted)

- ~~Web litertlm early preview~~ — spiked: dead for Qwen3; web uses the
  MediaPipe `-web.task` path instead (proven).
- Two models, two behaviors (web Gemma3 1B / mobile Qwen3 0.6B) — forced by
  artifact availability; prompt is shared, quality judged per platform.
- 668MB (web) / 475MB (mobile) download — consent-gated, never automatic.
- Web tab freezes during generation (MediaPipe main-thread prefill) — sheet
  copy sets expectations; acceptable v1.
- Weights provenance: ships only from the user's own HF mirror of the
  official artifact (Gemma license accepted and attached). The third-party
  darkB mirror is a development pin only — never ships to users; the swap is
  one constant and is a merge-gate for any release build that enables web.
- Small-model quality — quality bar above; judged in live verify.
- Fourth dependency breaks the "three deps" rail — deliberate, user-directed;
  CLAUDE.md updated.
