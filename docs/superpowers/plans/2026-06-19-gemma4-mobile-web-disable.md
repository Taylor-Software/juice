# Gemma 4 (mobile) + disable web LLM — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or executing-plans. Steps use `- [ ]`.

**Goal:** Mobile/desktop interpreter → Gemma 4 E2B `.litertlm`; web on-device LLM disabled; honest GB consent label.

**Architecture:** One model spec (Gemma 4 E2B) in `GemmaInterpreterService`; web is forced `unsupported` so the existing phase-gated UI auto-hides AI; a pure `formatDownloadSize` helper drives the consent label. Strip all now-dead web-LLM code + the WebGPU probe.

**Tech Stack:** Flutter, `flutter_gemma ^0.16.5` (unchanged — already exposes `ModelType.gemma4`), `flutter_riverpod`, `flutter_test`.

---

## File Structure

**Modify:** `lib/state/interpreter.dart` (add `formatDownloadSize`), `lib/state/interpreter_gemma.dart` (model spec + web-disable + strip), `assets/help_data.json` (credits), `test/help_asset_test.dart` (drop Qwen needle), `CLAUDE.md`.
**Create:** `test/format_download_size_test.dart`.
**Delete:** `lib/shared/webgpu_check_web.dart`, `lib/shared/webgpu_check_stub.dart`.

---

### Task 1: `formatDownloadSize` helper (TDD)

**Files:** Modify `lib/state/interpreter.dart`; Create `test/format_download_size_test.dart`.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/interpreter.dart';

void main() {
  test('formatDownloadSize: MB under 1 GB, decimal GB above', () {
    expect(formatDownloadSize(475), '~475 MB');
    expect(formatDownloadSize(999), '~999 MB');
    expect(formatDownloadSize(1000), '~1.0 GB');
    expect(formatDownloadSize(2588), '~2.6 GB');
  });
}
```

- [ ] **Step 2:** `flutter test test/format_download_size_test.dart` → FAIL (undefined).
- [ ] **Step 3:** Add to `lib/state/interpreter.dart` (top-level, pure — file has no `flutter_gemma` import; keep it that way):

```dart
/// Human download size: MB under 1 GB, else one-decimal GB (decimal MB,
/// matching how model hosts list file sizes).
String formatDownloadSize(int approxMb) => approxMb < 1000
    ? '~$approxMb MB'
    : '~${(approxMb / 1000).toStringAsFixed(1)} GB';
```

- [ ] **Step 4:** test → PASS. `flutter analyze lib/state/interpreter.dart` → clean.
- [ ] **Step 5: Commit** `feat(interpreter): formatDownloadSize GB-aware label`.

---

### Task 2: Gemma 4 mobile spec + disable web + strip web code

**Files:** Modify `lib/state/interpreter_gemma.dart`; Delete `lib/shared/webgpu_check_web.dart` + `webgpu_check_stub.dart`.

- [ ] **Step 1: Header doc-comment** — rewrite the top `library` doc to: mobile/desktop = Gemma 4 E2B int4 `.litertlm` (ungated litert-community); web = on-device LLM disabled (no model).

- [ ] **Step 2: One spec, Gemma 4.** Delete `_webSpec` and `_mobileSpec`; add:

```dart
const _gemma4Spec = _ModelSpec(
  url:
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
  filename: 'gemma-4-E2B-it.litertlm',
  modelType: ModelType.gemma4,
  fileType: ModelFileType.litertlm,
  approxMb: 2588,
);
```

Replace `final _spec = kIsWeb ? _webSpec : _mobileSpec;` with `final _spec = _gemma4Spec;`.

- [ ] **Step 3: Constructor → disable web.** Replace the WebGPU check with an unconditional web disable, and remove the `webgpu_check` conditional import:

```dart
  GemmaInterpreterService() {
    if (kIsWeb) {
      _status.value = const InterpreterStatus(InterpreterPhase.unsupported,
          message: 'On-device AI runs in the mobile and desktop apps, '
              'not on the web.');
    }
  }
```

Remove the two lines:
```dart
import '../shared/webgpu_check_stub.dart'
    if (dart.library.js_interop) '../shared/webgpu_check_web.dart';
```

- [ ] **Step 4: `downloadLabel`** → `String get downloadLabel => formatDownloadSize(_spec.approxMb);`

- [ ] **Step 5: `_loadModel`** — drop web special-casing. Backends list becomes:
```dart
      for (final backend in const [PreferredBackend.gpu, PreferredBackend.cpu]) {
```
Delete the entire `if (kIsWeb) { ... await _createChat(model); }` probe block inside the try (keep `return model;`). Keep the `[2048, 1280]` maxTokens loop + first-error capture.

- [ ] **Step 6: `_createChat`** — change `systemInstruction: kIsWeb ? null : systemInstruction,` to `systemInstruction: systemInstruction,`. (The web-latch comment above it may be trimmed to a one-liner; keep the temperature/topK/topP rationale comment.)

- [ ] **Step 7: `_generate`** — remove the `finally { if (kIsWeb) { ... stopGeneration } }` block entirely; keep the `try { await for ... .timeout(60s) ... }` and the watchdog comment. (No `finally` needed once web is gone.)

- [ ] **Step 8: `interpret`** — replace:
```dart
    final prompt = kIsWeb
        ? '[System: $oracleSystemInstruction]\n\n${buildOraclePrompt(seed)}'
        : buildOraclePrompt(seed);
    return parseInterpretations(
        await _generate(prompt, systemInstruction: oracleSystemInstruction));
```
with:
```dart
    return parseInterpretations(await _generate(buildOraclePrompt(seed),
        systemInstruction: oracleSystemInstruction));
```

- [ ] **Step 9: Delete** `lib/shared/webgpu_check_web.dart` and `lib/shared/webgpu_check_stub.dart` (`git rm`). Verify nothing else imports them: `grep -rn webgpu_check lib test` → no hits.

- [ ] **Step 10:** `dart format` + `flutter analyze` → clean (no unused imports, no dead `kIsWeb` leftovers beyond the constructor; `kIsWeb` still imported via `package:flutter/foundation.dart`).

- [ ] **Step 11: Commit** `feat(interpreter): Gemma 4 E2B on mobile, disable LLM on web`.

---

### Task 3: Credits copy + test

**Files:** Modify `assets/help_data.json`, `test/help_asset_test.dart`.

- [ ] **Step 1:** In `assets/help_data.json` replace the model-credit `p` line (the one starting `"Web: Gemma 3 1B (Google)..."`) with:
```
"On-device AI (mobile & desktop): Gemma 4 E2B (Google), used under the Gemma license. The model runs entirely on your device after a one-time download. The web version has no on-device AI."
```

- [ ] **Step 2:** In `test/help_asset_test.dart` remove the `'Qwen'` needle from the credits list (keep `'Gemma'`). Leave `'free'` / `'non-commercial'` assertions.

- [ ] **Step 3:** `flutter test test/help_asset_test.dart` → PASS.
- [ ] **Step 4: Commit** `docs(credits): Gemma 4 on-device, drop Qwen, note web has no AI`.

---

### Task 4: Full verify + docs

- [ ] **Step 1:** `flutter analyze` → clean; `flutter test` (full) → green.
- [ ] **Step 2:** Update the `CLAUDE.md` interpreter notes (the `interpreter_gemma.dart` pin note + the web-release-gate note): mobile/desktop = Gemma 4 E2B `.litertlm` (ungated litert-community, on-demand consent download, never bundled); web on-device LLM disabled → web no longer release-gated on weights provenance.
- [ ] **Step 3: Commit** `docs: Gemma 4 / web-LLM-disabled interpreter notes`.

---

## Self-Review

**Spec coverage:** model swap (T2), web disable + strip + file deletes (T2), GB label (T1), credits + test (T3), docs (T4). ✓
**Placeholder scan:** none — every edit shows exact before/after.
**Type consistency:** `formatDownloadSize(int)→String` (T1) used in T2 Step 4; `_gemma4Spec`/`ModelType.gemma4`/`approxMb:2588` consistent; `webgpu_check` fully removed (import T2-S3, files T2-S9). ✓
**Untestable surface noted:** the real service isn't unit-tested (CLAUDE rule) — covered by analyze + live web verify + the curl-confirmed URL.
