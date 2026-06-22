# AI enable toggle + Settings dialog + affordance gating

**Date:** 2026-06-22
**Status:** Design — approved pending spec review

## Problem

Two issues, reported together:

1. **No discoverable way to enable AI.** The on-device model download is buried
   inside the oracle-interpret sheet: it only surfaces when a user taps
   **Interpret** on a roll and the model isn't on disk (`needsDownload` → a
   "Download" card). There is no Settings screen. A user looking to "turn on AI"
   has nowhere to go.

2. **AI affordances appear prematurely.** Every AI entry point gates on
   `phase != unsupported` — i.e. it shows on any supported platform *before*
   anything is downloaded or opted into. There is no "enabled" concept at all.

**Desired:** AI options must stay hidden until the model is **downloaded
successfully AND explicitly enabled** in a discoverable Settings dialog.

## Decisions (from brainstorming)

- **Toggle scope: app-global.** One switch + one download for the whole app.
  Matches the fact that the model is device-global. Stored outside the
  per-campaign `CampaignSettings`.
- **Entry point: a gear in the home-shell app bar**, next to the existing `?`
  help button — visible on every verb screen.
- **When off: hide AI affordances entirely.** No dead/greyed buttons. The
  Settings gear is the single on-ramp to enable AI.
- **Download UI moves to Settings.** Strip the interpret sheet's
  download/consent branches; Settings owns download. The sheet assumes ready.

## Architecture

### 1. App-global enabled flag — `aiEnabledProvider`

`AsyncNotifierProvider<AiEnabledNotifier, bool>` in `lib/state/providers.dart`.

- Persisted under a **global** key `juice.ai_enabled.v1`.
- **NOT** session-scoped → NOT in `sessionScopedKeys`, so it is neither
  per-campaign nor included in campaign export/import.
- Default **`false`** — AI is off until the user enables it.
- `setEnabled(bool)` writes the pref and updates state.

```dart
class AiEnabledNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.ai_enabled.v1';
  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;
  Future<void> setEnabled(bool v) async {
    await (await SharedPreferences.getInstance()).setBool(_key, v);
    state = AsyncData(v);
  }
}
```

### 2. Reactive interpreter status — `interpreterStatusProvider`

Today the status `ValueListenable<InterpreterStatus>` is read non-reactively
(`ref.read(...).status.value.phase`) — safe only because `unsupported` never
flips. The new gate depends on `phase` flipping `needsDownload → … → ready` at
runtime, so it must be reactive. Wrap the `ValueListenable` in a
`StreamProvider<InterpreterStatus>`:

```dart
final interpreterStatusProvider = StreamProvider<InterpreterStatus>((ref) {
  final vl = ref.watch(interpreterServiceProvider).status;
  final c = StreamController<InterpreterStatus>();
  void listener() => c.add(vl.value);
  vl.addListener(listener);
  c.add(vl.value); // seed current
  ref.onDispose(() { vl.removeListener(listener); c.close(); });
  return c.stream;
});
```

### 3. Derived gates

```dart
/// The single source of truth every AI affordance watches.
/// ready ⇒ downloaded successfully + loaded; enabled ⇒ opted in.
final aiReadyProvider = Provider<bool>((ref) {
  final enabled = ref.watch(aiEnabledProvider).valueOrNull ?? false;
  final phase = ref.watch(interpreterStatusProvider).valueOrNull?.phase;
  return enabled && phase == InterpreterPhase.ready;
});

/// Settings-only: decides toggle-vs-"not available on this platform".
final aiSupportedProvider = Provider<bool>((ref) {
  final phase = ref.watch(interpreterStatusProvider).valueOrNull?.phase;
  return phase != null && phase != InterpreterPhase.unsupported;
});
```

### 4. Settings dialog — `lib/features/settings_sheet.dart`

A new `ConsumerWidget`/sheet opened from a gear `IconButton` (tooltip
"Settings", key `shell-settings`) added to the home-shell app bar beside the `?`
button (`lib/shared/home_shell.dart`, near the existing `openHelp` action). Named
"Settings" (general) so it can grow; P1 holds a single **"AI assistant"**
section.

Section body, driven by `interpreterStatusProvider` + `aiEnabledProvider`:

- **`unsupported`** → text "On-device AI isn't available on this platform."
  No toggle (web).
- **else** → `SwitchListTile` **"Enable AI assistant"** (key `settings-ai-toggle`)
  bound to `aiEnabledProvider.setEnabled`. When **on**, a phase-driven block:
  | phase | UI |
  |-------|-----|
  | `needsDownload` | "Runs on-device. Download the model (~2.6 GB) over Wi-Fi." + **Download** button (key `settings-ai-download`) → `service.warmUp()` |
  | `installing` | `LinearProgressIndicator(value: progress/100)` + "Downloading… N%" |
  | `loading` | spinner + "Loading model…" |
  | `ready` | "Ready ✓" |
  | `error` | `status.message` + **Retry** → `service.warmUp()` |

  When the toggle is **off**, the phase block is hidden.

**Consent & load semantics:**
- Toggling on does **not** auto-download — it reveals an explicit **Download**
  button showing the size. The tap is the consent.
- `setEnabled(true)` is stored immediately; AI affordances still stay hidden
  until `phase == ready` (gate requires both).
- On open with `enabled == true`, the dialog calls `service.refresh()` so an
  on-disk model loads (`needsDownload`→`loading`→`ready`) without re-download.
- Toggling off only hides affordances; the model stays on disk (re-enable is
  fast). The model is **not** unloaded (YAGNI).

### 5. Re-gate AI entry points

Replace each `phase != unsupported` read with `ref.watch(aiReadyProvider)`:

- `lib/features/journal_screen.dart` — `_canVoice`, `canInterpret` (the
  **Interpret…** popup item + **Voice this**), and the **recap/summarize**
  action.
- `lib/features/assistant_rail.dart` — the **Ask the GM** box (hide the ask box
  when not ready; rule-based suggestion chips are non-AI and stay).
- `lib/features/sidekick_screen.dart` — the **Voice this** affordance.

Because these now depend on runtime-flipping providers, convert their
`ref.read` reads to `ref.watch` so affordances appear/disappear live.

### 6. Strip the interpret sheet's download UI

`lib/features/oracle_interpretation_sheet.dart`: remove the `needsDownload` /
`installing` / `loading` / `error` consent+download branches and the
`initState` `_service.refresh()` call. The sheet only opens when
`aiReadyProvider` is true, so it assumes `ready` and goes straight to
generating. Defensive fallback: if `phase != ready` when somehow opened, show a
short "Assistant not ready — enable AI in Settings." message (no download flow).

## Data flow

```
Settings gear ─▶ SettingsSheet
                   │  toggle on ─▶ aiEnabledProvider.setEnabled(true)
                   │  Download   ─▶ service.warmUp()  (installing→loading→ready)
                   ▼
        interpreterStatusProvider (reactive) ──┐
        aiEnabledProvider ──────────────────────┤
                                                 ▼
                                         aiReadyProvider (bool)
                                                 │ watched by
        ┌────────────────────────────────────────┼───────────────────────┐
   journal Interpret/Voice/recap        assistant-rail Ask-GM       sidekick Voice
        (shown only when true)
```

## Testing

All via the shared `test/fake_interpreter.dart` (`FakeInterpreterService` with a
drivable `statusNotifier`); `interpreterServiceProvider` is overridden with it.
`aiEnabledProvider` is controlled per-test by `SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': true})`
or a provider override.

- **`aiReadyProvider` / `aiSupportedProvider` unit tests** — truth table:
  ready only when `enabled && phase == ready`; supported = `phase != unsupported`.
- **`settings_sheet_test.dart`** — per phase: `unsupported` shows "not available"
  + no toggle; supported+off shows toggle off (no phase block); toggling on calls
  `setEnabled(true)`; `needsDownload` shows Download → `warmUp` called;
  `installing` shows progress; `ready` shows "Ready ✓".
- **Gate widget tests** — journal/assistant-rail/sidekick: AI affordance hidden
  when `aiReady` false (e.g. enabled but `needsDownload`, or `ready` but
  disabled), shown when both true; affordance appears live when the fake's
  `statusNotifier` flips to `ready` with enabled true.
- **Update existing AI-affordance tests** (blast radius): tests that assert an AI
  button visible with `phase == ready` must now also enable AI
  (`aiEnabledProvider`) — at minimum `ask_anything_test`, `recap_test`,
  `sidekick_screen_test`, and any interpret-affordance test. Tests that override
  the fake only to avoid real Gemma (no AI-button assertions) are unaffected.

## Out of scope (YAGNI)

- Per-campaign AI override (one global switch only).
- Unloading the model from memory on disable.
- Moving genre/tone/default-oracle into the Settings dialog (they stay where
  they are; Settings is AI-only for P1).
- Web PDF/model support (unchanged; web stays `unsupported`).

## Files touched

| File | Change |
|------|--------|
| `lib/state/providers.dart` | `AiEnabledNotifier` + `aiEnabledProvider` |
| `lib/state/interpreter.dart` (or providers) | `interpreterStatusProvider`, `aiReadyProvider`, `aiSupportedProvider` |
| `lib/features/settings_sheet.dart` | **new** — Settings dialog + AI section |
| `lib/shared/home_shell.dart` | gear `IconButton` → open Settings |
| `lib/features/journal_screen.dart` | re-gate Interpret/Voice/recap on `aiReadyProvider` |
| `lib/features/assistant_rail.dart` | re-gate Ask-GM box |
| `lib/features/sidekick_screen.dart` | re-gate Voice |
| `lib/features/oracle_interpretation_sheet.dart` | strip download UI; assume ready |
| `test/settings_sheet_test.dart` | **new** |
| `test/ai_gating_test.dart` | **new** — provider truth table + gate widget tests |
| existing AI-affordance tests | enable AI where they assert AI buttons |
