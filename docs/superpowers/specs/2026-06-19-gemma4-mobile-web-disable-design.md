# Gemma 4 (mobile) + disable web LLM — Design

**Status:** Approved

## Problem

The on-device interpreter pins two model families: web = Gemma3 1B int4
`-web.task` (~670 MB) from a **third-party dev mirror** (`darkB/...`), mobile =
Qwen3 0.6B int4 `.litertlm` (~475 MB). Two problems:

1. The web weights come from a third-party mirror — the documented release gate
   (CLAUDE.md, oracle-interpreter spec "Weights provenance") is swapping it to
   the user's own HF mirror. That gate still blocks a web release.
2. The user wants one stronger model family: **Gemma 4 E2B** (`ModelType.gemma4`,
   native function-calling tokens). Gemma 4 E2B web builds are ~2 GB — too heavy
   for an in-browser download, and web `.litertlm` is early-preview/unproven in
   `flutter_gemma`.

Decision (settled in dialogue): **mobile + desktop → Gemma 4 E2B; web → disable
the on-device LLM entirely.** Disabling web is easier *and* better than
switching the web model — it removes the provenance release-gate, deletes the
flakiest code path (web session-reuse quirks), and web AI UX (670 MB–2 GB
download, WebGPU-only) was always weak. The app degrades gracefully: oracle
rolls/tables are deterministic; the LLM is an enhancement layer.

Backward compatibility is out of scope (pre-release). On-device weights stay
**download-on-demand with consent** (already implemented) — never bundled (a
2.59 GB binary is infeasible for app stores).

## Scope

**In:**
- Mobile/desktop interpreter model: Qwen3 0.6B → **Gemma 4 E2B**
  `gemma-4-E2B-it.litertlm` (`ModelType.gemma4`, `ModelFileType.litertlm`).
- Disable the on-device LLM on web: `GemmaInterpreterService` reports
  `unsupported` on web always; remove `_webSpec`, the WebGPU probe, and every
  `kIsWeb` web-LLM branch. Delete the now-orphaned `webgpu_check_*.dart`.
- Honest consent label: `downloadLabel` shows GB for large models (~2.6 GB).
- Update the credits/help copy (`assets/help_data.json`) + its test.

**Out (later / v2):**
- Web on-device LLM (any model). Web simply has no AI features.
- A `flutter_gemma` major upgrade (0.16.5 already exposes `ModelType.gemma4`).
- Device-accelerator-specific `.litertlm` variants (Tensor G5 / Qualcomm /
  Intel) — ship the generic cross-device build.
- Bundling weights / Play Asset Delivery.

## Artifact (verified)

`litert-community/gemma-4-E2B-it-litert-lm`, base `google/gemma-4-E2B-it`,
public/ungated (HTTP 302 → CDN, no token), repo license tag Apache-2.0.

| field | value |
|---|---|
| url | `https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm` |
| filename | `gemma-4-E2B-it.litertlm` |
| modelType | `ModelType.gemma4` |
| fileType | `ModelFileType.litertlm` |
| size | 2,588,147,712 bytes ≈ **2.59 GB** (`approxMb: 2588`) |

(Verified: `curl -sI -L` → `302` then `200`, `Content-Length: 2588147712`,
`X-Xet-Cas-Uid=public`.)

## Components

### `lib/state/interpreter_gemma.dart`

- **Delete** `_webSpec`; `_spec` becomes `_mobileSpec` (renamed `_gemma4Spec`
  conceptually — keep one spec). Update `_mobileSpec` to the Gemma 4 artifact
  above (`ModelType.gemma4`, `approxMb: 2588`).
- **Constructor:** `if (kIsWeb) _status.value = unsupported(message: 'On-device
  AI runs in the mobile and desktop apps, not on the web.')`. Remove the
  `webgpu_check` conditional import + `hasWebGpu` usage.
- **`_loadModel`:** drop the web-only special-casing — backends become
  `[PreferredBackend.gpu, PreferredBackend.cpu]` (no `if (!kIsWeb)`); remove the
  `if (kIsWeb) await _createChat(model)` probe block. The 2048→1280 maxTokens
  fallback stays.
- **`_createChat`:** drop `systemInstruction: kIsWeb ? null : systemInstruction`
  → always pass `systemInstruction`.
- **`_generate`:** drop the `finally { if (kIsWeb) stopGeneration }` block (the
  comment notes it's web-only; mobile recreates the native session per chat).
  Keep the 60 s inter-token timeout.
- **`interpret`:** drop the `kIsWeb ? '[System: ...]' : ...` prompt branch → use
  `buildOraclePrompt(seed)` with `systemInstruction: oracleSystemInstruction`.
- **`downloadLabel`:** use a pure `formatDownloadSize(approxMb)` (below).

These web branches are unreachable once web is `unsupported` (`warmUp`
short-circuits on `_unsupported`), so removal is behavior-preserving on mobile
and dead-code-removing for web — matching the "remove the flakiest code" goal.

### `lib/state/interpreter.dart` (seam — no `flutter_gemma` dep)

Add a pure, unit-testable helper:

```dart
/// Human download size: MB under 1 GB, else one-decimal GB (decimal MB,
/// matching how the source lists file sizes).
String formatDownloadSize(int approxMb) => approxMb < 1000
    ? '~$approxMb MB'
    : '~${(approxMb / 1000).toStringAsFixed(1)} GB';
```

`GemmaInterpreterService.downloadLabel` → `formatDownloadSize(_spec.approxMb)`
(2588 → "~2.6 GB"). The fake keeps its own constant.

### Delete `lib/shared/webgpu_check_web.dart` + `webgpu_check_stub.dart`

Used only by `interpreter_gemma.dart` (verified). Web is unconditionally
`unsupported`, so the WebGPU probe is gone.

### `assets/help_data.json` (hand-maintained; no build script)

Replace the model-credit line (currently *"Web: Gemma 3 1B (Google) under the
Gemma license. Mobile: Qwen3 0.6B (Alibaba) under Apache 2.0. Models run
entirely on your device after a one-time download."*) with copy reflecting the
new reality: Gemma 4 E2B (Google) on mobile/desktop under the Gemma license,
web has no on-device model, one-time on-device download. Drop the Qwen credit.

## Data flow (unchanged on mobile)

`needsDownload` → consent card (shows `downloadLabel`, e.g. "~2.6 GB") → user
taps → `warmUp` → `installModel(...).fromNetwork(url).withProgress` → `loading`
→ `ready`. Web: constructor → `unsupported` → every AI affordance auto-hides via
the existing phase gates (`assistant_rail`, `journal_screen` `_canVoice`/
`canInterpret`, `sidekick_screen`, `oracle_interpretation_sheet`).

## Error handling

- Web: `unsupported` is set once in the constructor and never flips (existing
  invariant the UI relies on). All four LLM entry points are gated already.
- Mobile download failure / corrupt file → existing `error` phase + retry.
- Large download: consent label is honest (~2.6 GB) so users see the cost.

## Testing

- **Unit (new):** `formatDownloadSize` — < 1 GB → "~N MB"; ≥ 1 GB → one-decimal
  GB; boundary 1024 → "~1.0 GB"; 2588 → "~2.6 GB".
- **Cannot** unit-test `GemmaInterpreterService` (CLAUDE rule: tests always use
  the fake; never construct the real service). The model-spec swap + web-disable
  live in that untested service — covered by `analyze`, the artifact curl check,
  and live web verify.
- **Existing suite stays green:** update `help_asset_test` (drop the `'Qwen'`
  needle; keep `'Gemma'`). Confirm no other test references Qwen3/web model.
- **Live verify (web):** `flutter build web` → on web the oracle-interpretation
  sheet shows the "not available here" note and the voice/interpret/ask
  affordances are hidden (LLM disabled). This is the observable surface of the
  web change. (The mobile Gemma 4 path can't be exercised here — no device /
  2.6 GB download — so it's verified by config correctness + URL reachability,
  stated honestly.)
- `dart format` + `flutter analyze` clean; full suite green.

## Docs

- `CLAUDE.md` interpreter note: mobile/desktop = Gemma 4 E2B `.litertlm`
  (ungated litert-community); web on-device LLM disabled (so web is no longer
  release-gated on weights provenance); on-demand download with consent, never
  bundled. Update `lib/state/interpreter_gemma.dart` header doc-comment to match.
- No new licensed content shipped (weights are downloaded on demand, credited
  in the about page).

## Risks / open items

- **Gemma 4 chat templating in flutter_gemma 0.16.5:** `ModelType.gemma4` exists
  in 0.16.5; `.litertlm` templating is handled by the LiteRT-LM SDK on
  Android/desktop. If live device testing later shows malformed output, revisit
  a `flutter_gemma` bump — tracked as a follow-up, not a blocker for this change.
- **2.59 GB on phones** is a large download + RAM footprint (user-accepted
  tradeoff for E2B). Consent label surfaces the size.
