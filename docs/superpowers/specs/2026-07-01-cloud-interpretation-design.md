# BYO-Key Cloud Interpretation — Design

_Dated 2026-07-01. Phase 2 of the cut-to-the-wedge roadmap
(`docs/superpowers/plans/2026-06-30-wedge-roadmap.md`). Fixes the AI value gap:
the on-device model is too small to be consistently good and cannot run on
web. Adds an optional, user-supplied-key cloud path for the ONE AI seam on the
loop's critical path — oracle interpretation — while leaving every other AI
seam untouched._

## Problem

`GemmaInterpreterService` (Gemma 4 E2B, ~2.6GB, on-device only, disabled on
web) powers `interpret()` and six other AI seams. Interpretation quality is
the bottleneck for the loop's most valuable AI moment, and web users get no AI
at all. The roadmap calls for an optional cloud tier without displacing the
on-device default or expanding scope into the other seams.

## Scope discipline

"Collapse the 5 AI seams to interpret" (roadmap wording) means: **only
`interpret()` gets a cloud path.** `voiceLine`, `summarize`, `gmChat`,
`narrate`, `fleshOut`, `rankSuggestions` are Freeze-bucket (Phase 0 framework)
— zero changes, remain strictly on-device. Only two existing call sites use
`interpret()`: `lib/features/loop_bar.dart` and
`lib/features/oracle_interpretation_sheet.dart` (the latter also serves the
Run screen and journal per-entry Interpret). This scoping keeps the blast
radius small and avoids a new failure mode where enabling cloud silently
"unlocks" UI for seams that still require the undownloaded on-device model.

## Decisions (from brainstorming)

1. **Key storage:** `flutter_secure_storage` (OS Keychain/Keystore) — a real,
   billable secret warrants encrypted-at-rest storage, not the plaintext
   SharedPreferences file every other setting uses.
2. **Provider:** Claude only, via `anthropic_sdk_dart` (pure Dart, `http`-based
   — not dio; cross-platform incl. Web; actively maintained, verified on
   pub.dev 2026-07-01). Supporting a second provider (e.g. OpenAI) would
   roughly double the request-building code and Settings surface for a phase
   scoped to be minimal — deferred, not ruled out.
3. **Model routing lives in a decorator**, not inside `GemmaInterpreterService`
   or at the call sites — see Architecture.

## Architecture

### New dependencies

- `anthropic_sdk_dart` — Claude API client.
- `flutter_secure_storage` — encrypted key storage.

This is the app's **first-ever network-capable dependency** (today `pubspec.yaml`
has zero `http`/`dio`/`cloud_*` packages). It is a deliberate, user-initiated,
opt-in exception — the app's default behavior (no network, on-device only)
is unchanged; a user must explicitly paste a key and flip a toggle to reach
any network code path.

### Key storage + toggle

- `CloudKeyStore` (new, `lib/state/cloud_key_store.dart`) — thin async wrapper
  over `FlutterSecureStorage`: `Future<String?> read()`, `Future<void>
  write(String key)`, `Future<void> clear()`. One secure-storage entry, key
  `cloud_anthropic_api_key`.
- `cloudApiKeyProvider` — `FutureProvider<String?>` reading `CloudKeyStore`.
  Invalidated after write/clear so the UI reflects the change immediately.
- `cloudInterpretEnabledProvider` — `AsyncNotifierProvider<bool>` over
  SharedPreferences (`juice.cloud_interpret_enabled.v1`), same pattern as
  `aiEnabledProvider` (`lib/state/providers.dart`). Default `false`. This is a
  non-sensitive UI preference, not a secret — SharedPreferences is correct
  here, unlike the key itself.

### `CloudInterpreter`

New, `lib/state/cloud_interpreter.dart`:

```dart
class CloudInterpreter {
  const CloudInterpreter({http.Client? httpClient})
      : _httpClient = httpClient;
  final http.Client? _httpClient; // injected in tests; null = SDK default

  static const model = 'claude-haiku-4-5-20251001';

  Future<List<OracleInterpretation>> interpret(
      OracleSeed seed, String apiKey) async {
    final client = AnthropicClient(apiKey: apiKey, client: _httpClient);
    try {
      final response = await client.messages.create(MessageCreateRequest(
        model: model,
        maxTokens: 512,
        system: oracleSystemInstruction, // existing, provider-agnostic
        messages: [InputMessage.user(buildOraclePrompt(seed))], // existing
      ));
      return parseInterpretations(response.text); // existing, pure parser
    } finally {
      client.close();
    }
  }
}
```

Reuses `oracleSystemInstruction`, `buildOraclePrompt`, and `parseInterpretations`
from `lib/engine/oracle_interpreter.dart` unchanged — these are already
provider-agnostic (plain prompt text in, plain text out); only the transport
is new. `parseInterpretations` already tolerates malformed JSON (salvage path),
so cloud responses get the same robustness as on-device ones for free. Errors
(bad key, network failure, rate limit, non-2xx) propagate as thrown exceptions
— `_InterpretCard` (shipped in Phase 1) already renders an error state with a
Retry button on any thrown error from `interpret()`, so no new error UI is
needed.

### Routing decorator

`interpreterServiceProvider`'s factory (`lib/state/interpreter.dart`) wraps the
existing `GemmaInterpreterService` in a new `_RoutingInterpreterService`:

```dart
class _RoutingInterpreterService implements InterpreterService {
  _RoutingInterpreterService(this._onDevice, this._ref);
  final InterpreterService _onDevice;
  final Ref _ref;

  @override
  Future<List<OracleInterpretation>> interpret(OracleSeed seed) async {
    final cloudOn =
        _ref.read(cloudInterpretEnabledProvider).valueOrNull ?? false;
    final key = cloudOn
        ? await _ref.read(cloudApiKeyProvider.future)
        : null;
    if (cloudOn && key != null && key.isNotEmpty) {
      return CloudInterpreter().interpret(seed, key);
    }
    return _onDevice.interpret(seed);
  }

  // All 7 other methods + `status`/`downloadLabel`/`refresh`/`warmUp`/
  // `dispose` delegate straight through to _onDevice, unchanged.
  @override
  ValueListenable<InterpreterStatus> get status => _onDevice.status;
  // ...
}
```

`interpreterServiceProvider` becomes:

```dart
final interpreterServiceProvider = Provider<InterpreterService>((ref) {
  final onDevice = GemmaInterpreterService();
  ref.onDispose(onDevice.dispose);
  return _RoutingInterpreterService(onDevice, ref);
});
```

**Zero changes** to `loop_bar.dart` or `oracle_interpretation_sheet.dart` — both
already call `ref.read(interpreterServiceProvider).interpret(seed)`, which now
transparently routes.

### Readiness — the scoping guard

New `interpretReadyProvider` (`lib/state/providers.dart`):

```dart
final interpretReadyProvider = Provider<bool>((ref) {
  if (ref.watch(aiReadyProvider)) return true; // on-device path available
  final cloudOn =
      ref.watch(cloudInterpretEnabledProvider).valueOrNull ?? false;
  final key = ref.watch(cloudApiKeyProvider).valueOrNull;
  return cloudOn && key != null && key.isNotEmpty;
});
```

The interpret-only gates switch from `aiReadyProvider` to
`interpretReadyProvider`. Concrete call sites (grepped, not guessed):
- `lib/features/loop_bar.dart`: the `aiReady` value fed into `nextBeatActions`
  (`lib/engine/next_beat.dart`'s `aiReady` param, unchanged signature — only
  the value the widget passes in changes).
- `lib/features/run_screen.dart:749`: `aiReady` gates the inline-interpret
  button before opening `OracleInterpretationSheet` — switch to
  `interpretReadyProvider`.
- `lib/features/journal_screen.dart:1100`: `canInterpret` — switch to
  `interpretReadyProvider`.
- `lib/features/journal_screen.dart:937`: `e.kind == JournalKind.result &&
  ref.read(aiReadyProvider)` — reads as an interpret-eligibility check
  (result entries are interpretable); **confirm at plan time** whether this
  gates Interpret specifically before switching it.

**Explicitly NOT switched** (frozen, on-device-only, unrelated to interpret):
`journal_screen.dart:929` (`_canVoice` — gates `voiceLine`, not interpret),
`journal_screen.dart:426,615,1782`, and every read of `aiReadyProvider` in
`assistant_rail.dart`, `gm_chat_screen.dart`, `map_screen.dart`,
`scenes_pane.dart`, `session_resume_screen.dart`, `sidekick_screen.dart`,
`tracker_screen.dart`. Enabling cloud does not make their UI appear; they
still require the on-device model, exactly as today. (Full disambiguation of
any remaining ambiguous `aiReadyProvider` reads in `journal_screen.dart`
happens at plan time by reading each site's surrounding context — the
principle is fixed here: only sites gating the Interpret affordance switch.)

**Inside `OracleInterpretationSheet` itself** (`oracle_interpretation_sheet.dart`):
its `_onStatus()` currently auto-starts generation when `_service.status.value
.phase == InterpreterPhase.ready` — this is a `ValueListenable` on the
routing decorator's `status`, which (per the decorator above) delegates
**straight to on-device, unchanged**. `status`/`phase` must NOT be made
cloud-aware — that field also feeds `aiReadyProvider`
(`enabled && phase==ready`) and `aiSupportedProvider` (`phase != unsupported`)
globally, and making it report "ready" from cloud alone would re-widen
exactly what `interpretReadyProvider` exists to prevent (the other 6 seams'
UI would appear enabled and then fail, since their methods still require the
on-device model). Instead, `_onStatus()`'s trigger condition changes from
`_service.status.value.phase == InterpreterPhase.ready` to
`ref.read(interpretReadyProvider)`, and `initState` adds a second trigger
source watching `interpretReadyProvider` (alongside the existing
`_service.status.addListener`) so the sheet also auto-generates when cloud
alone becomes ready. `_service.status.addListener` stays (still needed for
on-device state changes to trigger a rebuild/retry). Exact Riverpod listening
mechanism (`ref.listenManual` vs. restructuring around `build()`) is a
plan-time implementation detail; the requirement fixed here is: the trigger
condition reads `interpretReadyProvider`, not raw on-device `status`.

Because `interpretReadyProvider` doesn't require on-device `phase==ready`, a
web user with a cloud key configured can use Interpret even though
`GemmaInterpreterService` forces `unsupported` on web — this is the roadmap's
"works on web" goal, delivered for the one seam that needed it.

### Settings UI

`lib/features/settings_sheet.dart`'s single "AI assistant" section splits into
two blocks:
- The existing on-device block — **unchanged**, still gated on
  `aiSupportedProvider` (hidden on web/unsupported platforms).
- A new **"Cloud interpretation (optional)"** block — **always shown**,
  including on web. Contents: an obscured API-key `TextField` + Save/Clear
  buttons (writing through `CloudKeyStore`), and a "Use cloud for
  interpretation" `SwitchListTile` bound to `cloudInterpretEnabledProvider`
  (disabled — greyed, not interactable — until a key is saved). A caption:
  *"Sent to Anthropic's API. Requires your own key — billed by Anthropic, not
  this app."* This is a real network/financial action the user is opting
  into; the caption states that plainly rather than burying it.

## Data flow

1. User opens Settings → Cloud interpretation → pastes a key → Save →
   `CloudKeyStore.write` → `cloudApiKeyProvider` invalidated/refetched →
   toggle becomes enabled → user flips it on → `cloudInterpretEnabledProvider`
   persists `true`.
2. `interpretReadyProvider` flips true (via `cloudEnabled && key present`,
   independent of on-device phase).
3. Loop: Next-beat now offers `interpret` (per `nextBeatActions`); tapping it
   still seeds `_loopInterpretSeedProvider` exactly as before →
   `_InterpretCard` calls `interpreterServiceProvider.interpret(seed)` →
   `_RoutingInterpreterService` sees cloud-on + key → `CloudInterpreter` → a
   real Claude API call → `parseInterpretations` → same card UI, Keep/Discard
   unchanged.
4. Run screen / journal per-entry Interpret: same routing, transparently.
5. Turning the toggle off, or clearing the key, routes back to on-device
   (or shows the "not ready" state if on-device isn't downloaded either).

## Error handling

- Network failure / bad key / rate limit / malformed response → thrown
  exception → existing `_InterpretCard` error+Retry UI (Phase 1, unchanged).
- Empty/whitespace key never reaches `CloudInterpreter` — the routing
  decorator falls through to on-device in that case, per the `key.isNotEmpty`
  check.
- Toggling cloud on with no key saved: the Settings switch is disabled in that
  state (can't happen via the UI); `interpretReadyProvider` also independently
  guards it (`cloudOn && key != null && key.isNotEmpty`) so even a
  directly-manipulated pref value can't produce a broken "ready" signal.
- No automatic fallback from a failed cloud call to on-device — a failed call
  shows Retry (same cloud call) or the user turns the toggle off. Silent
  provider-switching on failure would be surprising; out of scope.

## Testing

- `CloudInterpreter`: unit tests with an **injected fake `http.Client`** (via
  the `httpClient` constructor param) that returns a canned Anthropic-shaped
  response — **no real network calls in tests, ever**. Covers: successful
  parse, malformed-JSON salvage (reuses existing `parseInterpretations`
  coverage), non-2xx → throws.
- `_RoutingInterpreterService`: unit/widget tests across 3 branches — cloud
  off → on-device; cloud on + no key → on-device; cloud on + key → cloud
  (mock `CloudInterpreter` or intercept via a testable seam). All 7
  passthrough methods verified to delegate unchanged (a single test calling
  each and asserting it hit the wrapped on-device fake is sufficient — no need
  to re-test their behavior, only that the wrapper doesn't intercept them).
- `interpretReadyProvider`: unit tests across all 4 boolean combinations of
  (aiReady, cloudEnabled×keyPresent).
- Settings UI: widget test that the cloud block renders on a platform where
  `aiSupportedProvider` is false (simulating web) — i.e. cloud UI visibility
  is independent of on-device support.
- Full `flutter analyze` + `flutter test` green, as with Phases 0/1.

## Non-goals (this phase)

- A second cloud provider (OpenAI, etc.) — deferred, not ruled out.
- Cloud support for any seam other than `interpret`.
- Streaming responses, tool calling, or any `anthropic_sdk_dart` feature beyond
  a single non-streaming `messages.create` call.
- A model-choice setting — `claude-haiku-4-5-20251001` is hardcoded; revisit if
  users want it.
- Automatic on-device fallback on cloud failure.
- Phase 3 (shareable loop kits) or Phase 4 (stranger testing).

## Files

- New: `lib/state/cloud_key_store.dart`, `lib/state/cloud_interpreter.dart`,
  `test/cloud_key_store_test.dart`, `test/cloud_interpreter_test.dart`,
  `test/routing_interpreter_service_test.dart`,
  `test/interpret_ready_provider_test.dart`.
- Changed: `lib/state/interpreter.dart` (routing decorator + provider
  factory), `lib/state/providers.dart` (`cloudInterpretEnabledProvider`,
  `cloudApiKeyProvider`, `interpretReadyProvider`),
  `lib/features/settings_sheet.dart` (new Cloud block),
  `lib/features/loop_bar.dart` (gate switch to `interpretReadyProvider`),
  `lib/features/oracle_interpretation_sheet.dart` (`_onStatus` trigger
  condition switches to `interpretReadyProvider`, `status` listener stays),
  `lib/features/run_screen.dart:749`, `lib/features/journal_screen.dart:1100`
  (gate switch), `pubspec.yaml` (two new deps).
