# BYO-Key Cloud Interpretation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional, user-supplied-key Claude cloud path for the `interpret()` seam only, while every other AI seam (voiceLine/summarize/gmChat/narrate/fleshOut/rankSuggestions) stays strictly on-device and unchanged.

**Architecture:** A `RoutingInterpreterService` decorator wraps the existing `GemmaInterpreterService`; only `interpret()` branches to a new `CloudInterpreter` (Claude, via `anthropic_sdk_dart`) when a cloud toggle + a securely-stored key are both present, else falls through to on-device — the two existing call sites (`loop_bar.dart`, `oracle_interpretation_sheet.dart`) need zero changes. A new `interpretReadyProvider` scopes readiness to interpret specifically, so cloud never unlocks the other 6 on-device-only seams.

**Tech Stack:** Flutter, flutter_riverpod, `anthropic_sdk_dart` ^5.0.0 (Claude API, `http`-based), `flutter_secure_storage` ^10.3.1 (OS Keychain/Keystore).

**Spec:** `docs/superpowers/specs/2026-07-01-cloud-interpretation-design.md`

**Branch:** create `feat/wedge-phase2-cloud-interpret` off `main` before Task 1.

**Run tests with:** `export PATH="$PATH:/Users/johntaylor/development/flutter/bin"` first.

---

## File Structure

- **New** `lib/state/cloud_key_store.dart` — `CloudKeyStore` abstract seam (mirrors `InterpreterService`'s pattern: an interface + a real platform-backed impl, so tests never touch platform channels) + `SecureCloudKeyStore` (real, `flutter_secure_storage`-backed).
- **New** `test/fake_cloud_key_store.dart` — in-memory fake, mirrors `test/fake_interpreter.dart`.
- **New** `lib/state/cloud_interpreter.dart` — `CloudInterpreter`, the actual Claude API call.
- **New** `test/cloud_interpreter_test.dart` — tests `CloudInterpreter` against an injected fake `http.Client` (via `package:http/testing.dart`'s `MockClient`) — no real network calls, ever.
- **New** `test/cloud_key_store_test.dart` — tests the fake + the abstract contract.
- **Modified** `lib/state/interpreter.dart` — adds `RoutingInterpreterService` (public, decorator) and rewires `interpreterServiceProvider`'s factory.
- **New** `test/routing_interpreter_service_test.dart` — tests the decorator's 3 branches + passthrough.
- **Modified** `lib/state/providers.dart` — `cloudKeyStoreProvider`, `cloudApiKeyProvider`, `cloudInterpretEnabledProvider`, `interpretReadyProvider`.
- **New** `test/cloud_providers_test.dart` — tests the four new providers, mirrors `test/ai_providers_test.dart`.
- **Modified** `lib/features/settings_sheet.dart` — new "Cloud interpretation (optional)" block.
- **Modified** `test/settings_sheet_test.dart` (or create if absent — check first) — widget test for the new block, including web-style visibility (works even when `aiSupportedProvider` is false).
- **Modified** `lib/features/loop_bar.dart`, `lib/features/run_screen.dart`, `lib/features/journal_screen.dart`, `lib/features/oracle_interpretation_sheet.dart` — gate-site switches to `interpretReadyProvider` (exact lines below).
- **Modified** `pubspec.yaml` — two new dependencies.
- **Modified** `macos/Runner/DebugProfile.entitlements`, `macos/Runner/Release.entitlements` — only if the macOS verification step (Task 10) finds it's actually needed (see that task — do not guess entitlement content).

---

## Task 1: Branch + dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Create the branch**

```bash
cd /Users/johntaylor/StudioProjects/juice
git checkout main
git pull origin main
git checkout -b feat/wedge-phase2-cloud-interpret
```

- [ ] **Step 2: Add the two dependencies**

In `pubspec.yaml`, under `dependencies:` (after the existing `flutter_svg: ^2.3.0` line), add:

```yaml
  anthropic_sdk_dart: ^5.0.0
  flutter_secure_storage: ^10.3.1
```

- [ ] **Step 3: Fetch + verify**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter pub get
```

Expected: resolves cleanly (`Got dependencies!`). If either package fails to resolve against the SDK constraint (`>=3.3.0 <4.0.0`), note the exact conflict and stop — do not force a lower/pinned version without checking the actual error.

- [ ] **Step 4: Read the real, resolved API for `MessageCreateRequest`**

The exact shape of the `system` parameter on `MessageCreateRequest` could not be confirmed from web docs during planning. Before writing `CloudInterpreter` (Task 5), read the actual resolved package source:

```bash
find / -path "*/anthropic_sdk_dart-*/lib/src/generated/schema/message_create_params.dart" 2>/dev/null | head -1
```

Open that file (or the nearest equivalent — search `find ~/.pub-cache -iname "*message_create*.dart" 2>/dev/null` if the first path doesn't exist) and confirm: does `MessageCreateRequest` accept `system:` as a plain `String`? Note the answer — Task 5 has a fallback if not.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(cloud-interpret): add anthropic_sdk_dart + flutter_secure_storage"
```

---

## Task 2: `CloudKeyStore` seam + fake

Mirrors the existing `InterpreterService` pattern (`lib/state/interpreter.dart`): an abstract interface, a real platform-backed implementation, and a test fake — so unit tests never hit `flutter_secure_storage`'s platform channels (which throw `MissingPluginException` outside a running app).

**Files:**
- Create: `lib/state/cloud_key_store.dart`
- Create: `test/fake_cloud_key_store.dart`
- Test: `test/cloud_key_store_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/cloud_key_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'fake_cloud_key_store.dart';

void main() {
  test('fake starts empty, write then read round-trips, clear empties it',
      () async {
    final store = FakeCloudKeyStore();
    expect(await store.read(), isNull);
    await store.write('sk-ant-test123');
    expect(await store.read(), 'sk-ant-test123');
    await store.clear();
    expect(await store.read(), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter test test/cloud_key_store_test.dart
```

Expected: FAIL — `fake_cloud_key_store.dart` not found.

- [ ] **Step 3: Write the seam**

```dart
// lib/state/cloud_key_store.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted storage for the user's cloud API key. A real, billable secret —
/// unlike every other persisted value in this app (which lives in plaintext
/// SharedPreferences), this warrants OS Keychain/Keystore storage. Abstracted
/// as a seam (mirrors [InterpreterService] in interpreter.dart) so tests never
/// touch the platform channel.
abstract class CloudKeyStore {
  Future<String?> read();
  Future<void> write(String key);
  Future<void> clear();
}

class SecureCloudKeyStore implements CloudKeyStore {
  static const _key = 'cloud_anthropic_api_key';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String key) => _storage.write(key: _key, value: key);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
```

- [ ] **Step 4: Write the fake**

```dart
// test/fake_cloud_key_store.dart
import 'package:juice_oracle/state/cloud_key_store.dart';

class FakeCloudKeyStore implements CloudKeyStore {
  String? _value;
  int readCalls = 0;
  int writeCalls = 0;
  int clearCalls = 0;

  @override
  Future<String?> read() async {
    readCalls++;
    return _value;
  }

  @override
  Future<void> write(String key) async {
    writeCalls++;
    _value = key;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    _value = null;
  }
}
```

- [ ] **Step 5: Run to verify it passes**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter test test/cloud_key_store_test.dart
```

Expected: PASS (1 test).

- [ ] **Step 6: Commit**

```bash
git add lib/state/cloud_key_store.dart test/fake_cloud_key_store.dart test/cloud_key_store_test.dart
git commit -m "feat(cloud-interpret): CloudKeyStore secure-storage seam + fake"
```

---

## Task 3: `CloudInterpreter`

**Files:**
- Create: `lib/state/cloud_interpreter.dart`
- Test: `test/cloud_interpreter_test.dart`

- [ ] **Step 1: Write the failing test**

Uses `package:http/testing.dart`'s `MockClient` (ships with the `http` package, already a transitive dependency via `anthropic_sdk_dart` — no new dev dependency). This is the "no real network calls in tests" guarantee: the mock client intercepts every request and returns a canned response.

```dart
// test/cloud_interpreter_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';
import 'package:juice_oracle/state/cloud_interpreter.dart';

http.Client _mockAnthropicClient(String responseText, {int status = 200}) {
  return MockClient((request) async {
    final body = jsonEncode({
      'id': 'msg_test',
      'type': 'message',
      'role': 'assistant',
      'model': CloudInterpreter.model,
      'content': [
        {'type': 'text', 'text': responseText}
      ],
      'stop_reason': 'end_turn',
      'usage': {'input_tokens': 10, 'output_tokens': 10},
    });
    return http.Response(body, status,
        headers: {'content-type': 'application/json'});
  });
}

const _validJson = '{"interpretations":['
    '{"lens":"literal","reading":"The gate holds."},'
    '{"lens":"symbolic","reading":"A door within a door."},'
    '{"lens":"complication","reading":"But the hinge groans."},'
    '{"lens":"foreshadow","reading":"Footsteps, once, behind you."}]}';

void main() {
  test('interpret() parses a successful Claude response', () async {
    final interpreter =
        CloudInterpreter(httpClient: _mockAnthropicClient(_validJson));
    final cards = await interpreter.interpret(
      const OracleSeed(resultText: 'Fate Check — Yes'),
      'sk-ant-test',
    );
    expect(cards, hasLength(4));
    expect(cards.first.lens, 'literal');
    expect(cards.first.reading, 'The gate holds.');
  });

  test('interpret() throws on a non-2xx response', () async {
    final interpreter = CloudInterpreter(
        httpClient: _mockAnthropicClient('{"error":"bad key"}', status: 401));
    expect(
      () => interpreter.interpret(
          const OracleSeed(resultText: 'x'), 'sk-ant-bad'),
      throwsA(anything),
    );
  });
}
```

If `OracleSeed`'s constructor requires more than `resultText` (check `lib/engine/oracle_interpreter.dart` — other fields may be required, not optional), adjust the test's `OracleSeed(...)` calls to match its actual constructor signature.

- [ ] **Step 2: Run to verify it fails**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter test test/cloud_interpreter_test.dart
```

Expected: FAIL — `cloud_interpreter.dart` not found.

- [ ] **Step 3: Write the implementation**

Base version — adjust the `system:` line per what Task 1 Step 4 found in the real package source. If `system:` accepts a plain `String`, use it as shown. If it requires a different type (e.g. a list of content blocks), the fallback is commented below.

```dart
// lib/state/cloud_interpreter.dart
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';
import 'package:http/http.dart' as http;

import '../engine/oracle_interpreter.dart';

/// Optional Claude-backed cloud path for the interpret() seam ONLY. Every
/// other AI seam (voiceLine/summarize/gmChat/narrate/fleshOut/rankSuggestions)
/// stays strictly on-device — see the routing decorator in interpreter.dart.
/// Reuses the existing, provider-agnostic prompt builder + parser from
/// oracle_interpreter.dart; only the transport (Claude vs. local Gemma) is new.
class CloudInterpreter {
  const CloudInterpreter({http.Client? httpClient}) : _httpClient = httpClient;
  final http.Client? _httpClient;

  /// Fast, cheap tier — a 4-lens interpretation doesn't need a larger model,
  /// and the user pays per token on their own key.
  static const model = 'claude-haiku-4-5-20251001';

  Future<List<OracleInterpretation>> interpret(
      OracleSeed seed, String apiKey) async {
    final client = AnthropicClient.withApiKey(apiKey, httpClient: _httpClient);
    try {
      final response = await client.messages.create(MessageCreateRequest(
        model: model,
        maxTokens: 512,
        system: oracleSystemInstruction, // if this fails to compile, see below
        messages: [InputMessage.user(buildOraclePrompt(seed))],
      ));
      return parseInterpretations(response.text);
    } finally {
      client.close();
    }
  }
}

// FALLBACK if `system:` does not accept a plain String (check the compiler
// error — likely "the argument type 'String' can't be assigned to the
// parameter type '...'"): fold the system instruction into the user message
// instead —
//   messages: [InputMessage.user('$oracleSystemInstruction\n\n${buildOraclePrompt(seed)}')],
// and drop the `system:` line entirely. Use this fallback ONLY if the typed
// `system:` parameter genuinely doesn't accept a String — try the typed form
// first.
```

- [ ] **Step 4: Run to verify it passes; fix compile errors using the noted fallback if needed**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter test test/cloud_interpreter_test.dart
```

Expected: PASS (2 tests). If `system:` doesn't compile, apply the fallback comment above, remove the fallback comment block once applied, and rerun.

- [ ] **Step 5: Commit**

```bash
git add lib/state/cloud_interpreter.dart test/cloud_interpreter_test.dart
git commit -m "feat(cloud-interpret): CloudInterpreter (Claude transport for interpret())"
```

---

## Task 4: Providers — `cloudKeyStoreProvider`, `cloudApiKeyProvider`, `cloudInterpretEnabledProvider`, `interpretReadyProvider`

**Files:**
- Modify: `lib/state/providers.dart`
- Test: `test/cloud_providers_test.dart`

- [ ] **Step 1: Write the failing test**

Mirrors `test/ai_providers_test.dart`'s existing style exactly.

```dart
// test/cloud_providers_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/cloud_key_store.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_cloud_key_store.dart';
import 'fake_interpreter.dart';

void main() {
  test('cloudInterpretEnabledProvider defaults to false and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(cloudInterpretEnabledProvider.future), isFalse);
    await c.read(cloudInterpretEnabledProvider.notifier).setEnabled(true);
    expect(c.read(cloudInterpretEnabledProvider).valueOrNull, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('juice.cloud_interpret_enabled.v1'), isTrue);
  });

  test('cloudApiKeyProvider reads through the overridden key store', () async {
    final fake = FakeCloudKeyStore();
    await fake.write('sk-ant-abc');
    final c = ProviderContainer(overrides: [
      cloudKeyStoreProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    expect(await c.read(cloudApiKeyProvider.future), 'sk-ant-abc');
  });

  group('interpretReadyProvider', () {
    ProviderContainer make({
      required InterpreterPhase onDevicePhase,
      bool onDeviceEnabled = false,
      bool cloudEnabled = false,
      String? cloudKey,
    }) {
      SharedPreferences.setMockInitialValues({
        'juice.ai_enabled.v1': onDeviceEnabled,
        'juice.cloud_interpret_enabled.v1': cloudEnabled,
      });
      final fakeInterpreter =
          FakeInterpreterService(initial: InterpreterStatus(onDevicePhase));
      final fakeKeyStore = FakeCloudKeyStore();
      if (cloudKey != null) fakeKeyStore.write(cloudKey);
      final c = ProviderContainer(overrides: [
        interpreterServiceProvider.overrideWithValue(fakeInterpreter),
        cloudKeyStoreProvider.overrideWithValue(fakeKeyStore),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('true when on-device is ready (cloud irrelevant)', () async {
      final c = make(
          onDevicePhase: InterpreterPhase.ready, onDeviceEnabled: true);
      await c.read(aiEnabledProvider.future);
      await c.read(interpreterStatusProvider.future);
      expect(c.read(interpretReadyProvider), isTrue);
    });

    test('true when cloud enabled + key present, on-device not ready',
        () async {
      final c = make(
        onDevicePhase: InterpreterPhase.needsDownload,
        cloudEnabled: true,
        cloudKey: 'sk-ant-abc',
      );
      await c.read(cloudInterpretEnabledProvider.future);
      await c.read(cloudApiKeyProvider.future);
      expect(c.read(interpretReadyProvider), isTrue);
    });

    test('false when cloud enabled but no key saved', () async {
      final c = make(
        onDevicePhase: InterpreterPhase.needsDownload,
        cloudEnabled: true,
      );
      await c.read(cloudInterpretEnabledProvider.future);
      await c.read(cloudApiKeyProvider.future);
      expect(c.read(interpretReadyProvider), isFalse);
    });

    test('false when cloud has a key but the toggle is off', () async {
      final c = make(
        onDevicePhase: InterpreterPhase.needsDownload,
        cloudKey: 'sk-ant-abc',
      );
      await c.read(cloudInterpretEnabledProvider.future);
      await c.read(cloudApiKeyProvider.future);
      expect(c.read(interpretReadyProvider), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter test test/cloud_providers_test.dart
```

Expected: FAIL — the new providers/imports don't exist yet.

- [ ] **Step 3: Add the providers**

In `lib/state/providers.dart`, add the import at the top (alphabetical, near the other `state`/local imports):

```dart
import 'cloud_key_store.dart';
```

Then, immediately after the existing `aiSupportedProvider` block (found at the lines ending `Provider<bool>((ref) => _phase(ref) != InterpreterPhase.unsupported);`), add:

```dart
// -- Cloud interpretation (BYO Claude key; interpret() seam ONLY) -----------
// The API key is a real, billable secret -> secure storage, NOT the plaintext
// SharedPreferences every other setting uses. The toggle itself is a plain UI
// preference (not sensitive), so it DOES use SharedPreferences, matching
// aiEnabledProvider's pattern.
final cloudKeyStoreProvider =
    Provider<CloudKeyStore>((ref) => SecureCloudKeyStore());

final cloudApiKeyProvider = FutureProvider<String?>(
    (ref) => ref.watch(cloudKeyStoreProvider).read());

class CloudInterpretEnabledNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.cloud_interpret_enabled.v1';

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> setEnabled(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(_key, value);
    state = AsyncData(value);
  }
}

final cloudInterpretEnabledProvider =
    AsyncNotifierProvider<CloudInterpretEnabledNotifier, bool>(
        CloudInterpretEnabledNotifier.new);

/// Scoped readiness for the interpret() seam ONLY — true when EITHER the
/// on-device model is ready OR the cloud toggle is on with a saved key.
/// Deliberately narrower than [aiReadyProvider]: every other AI seam
/// (voiceLine/summarize/gmChat/narrate/fleshOut/rankSuggestions) keeps
/// gating on [aiReadyProvider] unchanged, so enabling cloud does NOT unlock
/// their UI (which would fail — those seams still require on-device).
final interpretReadyProvider = Provider<bool>((ref) {
  if (ref.watch(aiReadyProvider)) return true;
  final cloudOn =
      ref.watch(cloudInterpretEnabledProvider).valueOrNull ?? false;
  final key = ref.watch(cloudApiKeyProvider).valueOrNull;
  return cloudOn && key != null && key.isNotEmpty;
});
```

- [ ] **Step 4: Run to verify it passes**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter test test/cloud_providers_test.dart
```

Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/cloud_providers_test.dart
git commit -m "feat(cloud-interpret): cloud key/toggle providers + scoped interpretReadyProvider"
```

---

## Task 5: `RoutingInterpreterService` decorator

**Files:**
- Modify: `lib/state/interpreter.dart`
- Test: `test/routing_interpreter_service_test.dart`

- [ ] **Step 1: Write the failing test**

`RoutingInterpreterService` takes plain closures (not a Riverpod `Ref`) for its cloud dependencies — this keeps it constructible and testable with zero Riverpod machinery, per the "design for isolation" principle (a unit test shouldn't need a `ProviderContainer` just to prove a decorator delegates correctly).

```dart
// test/routing_interpreter_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';
import 'package:juice_oracle/state/cloud_interpreter.dart';
import 'package:juice_oracle/state/interpreter.dart';

import 'fake_interpreter.dart';

class _StubCloud implements CloudInterpreter {
  _StubCloud(this.result);
  final List<OracleInterpretation> result;
  OracleSeed? lastSeed;
  String? lastKey;

  @override
  Future<List<OracleInterpretation>> interpret(
      OracleSeed seed, String apiKey) async {
    lastSeed = seed;
    lastKey = apiKey;
    return result;
  }
}

void main() {
  const cloudResult = [OracleInterpretation(lens: 'literal', reading: 'cloud')];

  test('cloud disabled -> delegates to on-device', () async {
    final onDevice = FakeInterpreterService();
    final cloud = _StubCloud(cloudResult);
    final routing = RoutingInterpreterService(
      onDevice,
      cloudEnabled: () => false,
      cloudApiKey: () async => 'sk-ant-present',
      cloudInterpreter: cloud,
    );
    final result =
        await routing.interpret(const OracleSeed(resultText: 'x'));
    expect(onDevice.interpretCalls, 1);
    expect(cloud.lastSeed, isNull);
    expect(result.first.reading, 'fallback'); // FakeInterpreterService default
  });

  test('cloud enabled but no key -> delegates to on-device', () async {
    final onDevice = FakeInterpreterService();
    final cloud = _StubCloud(cloudResult);
    final routing = RoutingInterpreterService(
      onDevice,
      cloudEnabled: () => true,
      cloudApiKey: () async => null,
      cloudInterpreter: cloud,
    );
    await routing.interpret(const OracleSeed(resultText: 'x'));
    expect(onDevice.interpretCalls, 1);
    expect(cloud.lastSeed, isNull);
  });

  test('cloud enabled with a key -> routes to cloud, not on-device', () async {
    final onDevice = FakeInterpreterService();
    final cloud = _StubCloud(cloudResult);
    final routing = RoutingInterpreterService(
      onDevice,
      cloudEnabled: () => true,
      cloudApiKey: () async => 'sk-ant-present',
      cloudInterpreter: cloud,
    );
    final seed = const OracleSeed(resultText: 'x');
    final result = await routing.interpret(seed);
    expect(onDevice.interpretCalls, 0);
    expect(cloud.lastSeed, same(seed));
    expect(cloud.lastKey, 'sk-ant-present');
    expect(result.first.reading, 'cloud');
  });

  test('every other method delegates straight through to on-device',
      () async {
    final onDevice = FakeInterpreterService();
    final routing = RoutingInterpreterService(
      onDevice,
      cloudEnabled: () => true,
      cloudApiKey: () async => 'sk-ant-present',
      cloudInterpreter: _StubCloud(cloudResult),
    );
    expect(routing.status, same(onDevice.status));
    expect(routing.downloadLabel, onDevice.downloadLabel);
    await routing.refresh();
    await routing.warmUp();
    await routing.voiceLine(const VoiceSeed(character: 'x', line: 'y'));
    await routing.summarize(const ['a']);
    await routing.gmChat(const GmChatSeed(question: 'x', history: []));
    await routing.narrate(const NarrateSeed(mode: NarrateMode.continueScene));
    await routing
        .fleshOut(const FleshOutSeed(entityKind: 'npc', name: 'x'));
    await routing.rankSuggestions(
        const RankSuggestionsSeed(candidateIds: []));
    await routing.dispose();
    expect(onDevice.refreshCalls, 1);
    expect(onDevice.warmUpCalls, 1);
    expect(onDevice.voiceCalls, 1);
    expect(onDevice.summaryCalls, 1);
    expect(onDevice.gmChatCalls, 1);
    expect(onDevice.narrateCalls, 1);
    expect(onDevice.fleshOutCalls, 1);
    expect(onDevice.rankCalls, 1);
    expect(onDevice.disposeCalls, 1);
  });
}
```

Check the exact constructors for `VoiceSeed`, `GmChatSeed`, `NarrateSeed`, `NarrateMode`, `FleshOutSeed`, `RankSuggestionsSeed` in `lib/engine/oracle_interpreter.dart` before running — adjust the test's field names/required params to match if they differ from the guesses above (these are exercised elsewhere in the existing test suite; `grep -n "VoiceSeed(\|GmChatSeed(\|NarrateSeed(\|FleshOutSeed(\|RankSuggestionsSeed(" test/*.dart` finds real usage examples to copy from).

- [ ] **Step 2: Run to verify it fails**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter test test/routing_interpreter_service_test.dart
```

Expected: FAIL — `RoutingInterpreterService` not defined; also fix any constructor mismatches found above before this step passes as a clean "not defined" failure (not a mismatched-args failure).

- [ ] **Step 3: Implement the decorator**

In `lib/state/interpreter.dart`, add the import (near the top, with the other local imports):

```dart
import 'cloud_interpreter.dart';
```

Then add, after the `InterpreterService` abstract class definition and before `interpreterServiceProvider`:

```dart
/// Wraps an on-device [InterpreterService], routing ONLY interpret() to a
/// [CloudInterpreter] when cloud is enabled and a key is available; every
/// other method delegates straight through unchanged. Takes plain closures
/// (not a Riverpod Ref) so it's constructible and testable without any
/// Riverpod machinery — see interpreterServiceProvider below for how the real
/// app wires the closures to actual providers.
class RoutingInterpreterService implements InterpreterService {
  RoutingInterpreterService(
    this._onDevice, {
    required bool Function() cloudEnabled,
    required Future<String?> Function() cloudApiKey,
    CloudInterpreter? cloudInterpreter,
  })  : _cloudEnabled = cloudEnabled,
        _cloudApiKey = cloudApiKey,
        _cloud = cloudInterpreter ?? const CloudInterpreter();

  final InterpreterService _onDevice;
  final bool Function() _cloudEnabled;
  final Future<String?> Function() _cloudApiKey;
  final CloudInterpreter _cloud;

  @override
  Future<List<OracleInterpretation>> interpret(OracleSeed seed) async {
    if (_cloudEnabled()) {
      final key = await _cloudApiKey();
      if (key != null && key.isNotEmpty) {
        return _cloud.interpret(seed, key);
      }
    }
    return _onDevice.interpret(seed);
  }

  @override
  ValueListenable<InterpreterStatus> get status => _onDevice.status;

  @override
  String get downloadLabel => _onDevice.downloadLabel;

  @override
  Future<void> refresh() => _onDevice.refresh();

  @override
  Future<void> warmUp() => _onDevice.warmUp();

  @override
  Future<String> voiceLine(VoiceSeed seed) => _onDevice.voiceLine(seed);

  @override
  Future<String> summarize(List<String> entries) =>
      _onDevice.summarize(entries);

  @override
  Future<String> gmChat(GmChatSeed seed) => _onDevice.gmChat(seed);

  @override
  Future<String> narrate(NarrateSeed seed) => _onDevice.narrate(seed);

  @override
  Future<String> fleshOut(FleshOutSeed seed) => _onDevice.fleshOut(seed);

  @override
  Future<RankResult> rankSuggestions(RankSuggestionsSeed seed) =>
      _onDevice.rankSuggestions(seed);

  @override
  Future<void> dispose() => _onDevice.dispose();
}
```

Note: `CloudInterpreter` needs a `const` constructor for the `?? const CloudInterpreter()` default to compile — check Task 3's `CloudInterpreter({http.Client? httpClient}) : _httpClient = httpClient;` — this already qualifies as const-constructible (a single nullable field, no non-const initialization) as long as it isn't declared `const CloudInterpreter(...)` is written; if the compiler rejects `const`, drop the `const` keyword here and use `CloudInterpreter()` (non-const) instead — functionally identical, just not a compile-time constant.

- [ ] **Step 4: Run to verify it passes**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter test test/routing_interpreter_service_test.dart
```

Expected: PASS (4 tests).

- [ ] **Step 5: Rewire `interpreterServiceProvider`**

Still in `lib/state/interpreter.dart`, change:

```dart
final interpreterServiceProvider = Provider<InterpreterService>((ref) {
  final service = GemmaInterpreterService();
  ref.onDispose(service.dispose);
  return service;
});
```

to:

```dart
final interpreterServiceProvider = Provider<InterpreterService>((ref) {
  final onDevice = GemmaInterpreterService();
  ref.onDispose(onDevice.dispose);
  return RoutingInterpreterService(
    onDevice,
    cloudEnabled: () =>
        ref.read(cloudInterpretEnabledProvider).valueOrNull ?? false,
    cloudApiKey: () => ref.read(cloudApiKeyProvider.future),
  );
});
```

This requires `cloudInterpretEnabledProvider`/`cloudApiKeyProvider` to be visible from `interpreter.dart` — they're defined in `providers.dart` (Task 4), which already imports `interpreter.dart` (for `InterpreterService`/`InterpreterPhase`/etc.), so add the reverse import here:

```dart
import 'providers.dart';
```

If this creates a circular import error (`providers.dart` importing `interpreter.dart` AND `interpreter.dart` importing `providers.dart`), Dart allows import cycles as long as there's no cycle in top-level *initialization* order — but if the analyzer complains, the fix is to move `cloudInterpretEnabledProvider`/`cloudApiKeyProvider`/`cloudKeyStoreProvider` definitions from `providers.dart` into `interpreter.dart` instead (alongside `interpreterServiceProvider`, which already needs them) and have `providers.dart` import `interpreter.dart` for `interpretReadyProvider` to reference them (it already does, since `interpreter.dart` is presumably already imported by `providers.dart` for `InterpreterPhase`/`aiReadyProvider`'s existing `_phase` helper). Try the straightforward two-way import first; only restructure if the analyzer actually errors.

- [ ] **Step 6: Run full analyze + the interpreter test suite**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter analyze lib/state/interpreter.dart lib/state/providers.dart
flutter test test/interpreter_test.dart test/ai_providers_test.dart test/cloud_providers_test.dart test/routing_interpreter_service_test.dart
```

Expected: analyze clean; all 4 test files pass. `test/interpreter_test.dart`'s existing `interpreterServiceProvider is overridable with the fake` test must still pass unchanged — it overrides the whole provider with `FakeInterpreterService`, which bypasses `RoutingInterpreterService` entirely (this is correct and expected — every existing widget test that does `interpreterServiceProvider.overrideWithValue(fake)` continues to work exactly as before).

- [ ] **Step 7: Commit**

```bash
git add lib/state/interpreter.dart
git commit -m "feat(cloud-interpret): RoutingInterpreterService decorator, wired into interpreterServiceProvider"
```

---

## Task 6: Settings UI — Cloud interpretation block

**Files:**
- Modify: `lib/features/settings_sheet.dart`
- Test: check whether `test/settings_sheet_test.dart` exists (`ls test/settings_sheet_test.dart`); create it if absent, extend it if present.

- [ ] **Step 1: Write the failing test**

```dart
// test/settings_sheet_test.dart (create if it doesn't already exist; if it
// does, ADD these two tests to its existing file/imports rather than
// duplicating boilerplate — read the existing file first)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/settings_sheet.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_cloud_key_store.dart';
import 'fake_interpreter.dart';

void main() {
  testWidgets(
      'cloud interpretation block shows even when on-device is unsupported',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fakeInterpreter = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.unsupported));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        interpreterServiceProvider.overrideWithValue(fakeInterpreter),
        cloudKeyStoreProvider.overrideWithValue(FakeCloudKeyStore()),
      ],
      child: MaterialApp(
        home: Builder(builder: (context) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () => showSettingsSheet(context),
              child: const Text('open'),
            ),
          );
        }),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text("On-device AI isn't available on this platform."),
        findsOneWidget);
    expect(find.text('Cloud interpretation'), findsOneWidget);
    expect(find.byKey(const Key('settings-cloud-key-field')), findsOneWidget);
  });

  testWidgets('saving a key enables the cloud toggle', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fakeInterpreter = FakeInterpreterService();
    final fakeStore = FakeCloudKeyStore();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        interpreterServiceProvider.overrideWithValue(fakeInterpreter),
        cloudKeyStoreProvider.overrideWithValue(fakeStore),
      ],
      child: MaterialApp(
        home: Builder(builder: (context) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () => showSettingsSheet(context),
              child: const Text('open'),
            ),
          );
        }),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Toggle starts disabled: no key saved yet.
    final toggleBefore = tester.widget<SwitchListTile>(
        find.byKey(const Key('settings-cloud-toggle')));
    expect(toggleBefore.onChanged, isNull);

    await tester.enterText(
        find.byKey(const Key('settings-cloud-key-field')), 'sk-ant-test');
    await tester.tap(find.byKey(const Key('settings-cloud-key-save')));
    await tester.pumpAndSettle();

    expect(fakeStore.writeCalls, 1);
    final toggleAfter = tester.widget<SwitchListTile>(
        find.byKey(const Key('settings-cloud-toggle')));
    expect(toggleAfter.onChanged, isNotNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter test test/settings_sheet_test.dart
```

Expected: FAIL — the cloud block/keys don't exist yet.

- [ ] **Step 3: Add the Cloud interpretation block**

In `lib/features/settings_sheet.dart`, add imports:

```dart
import '../state/cloud_key_store.dart';
```

Convert `_SettingsSheet` from `ConsumerWidget` to `ConsumerStatefulWidget` (it needs a `TextEditingController` for the key field):

```dart
class _SettingsSheet extends ConsumerStatefulWidget {
  const _SettingsSheet();
  @override
  ConsumerState<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<_SettingsSheet> {
  final _keyCtrl = TextEditingController();

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supported = ref.watch(aiSupportedProvider);
    final enabled = ref.watch(aiEnabledProvider).valueOrNull ?? false;
    final status = ref.watch(interpreterStatusProvider).valueOrNull;
    final cloudKey = ref.watch(cloudApiKeyProvider).valueOrNull;
    final cloudEnabled =
        ref.watch(cloudInterpretEnabledProvider).valueOrNull ?? false;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('AI assistant', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            if (!supported)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text("On-device AI isn't available on this platform."),
              )
            else ...[
              SwitchListTile(
                key: const Key('settings-ai-toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable AI assistant'),
                subtitle: const Text(
                    'Interpret rolls, voice lines, recaps — all on-device.'),
                value: enabled,
                onChanged: (v) =>
                    ref.read(aiEnabledProvider.notifier).setEnabled(v),
              ),
              if (enabled) _statusBlock(context, ref, status),
            ],
            const SizedBox(height: 16),
            Text('Cloud interpretation', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            const Text(
              'Optional. Sent to Anthropic\'s API. Requires your own key — '
              'billed by Anthropic, not this app.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('settings-cloud-key-field'),
              controller: _keyCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Claude API key',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton(
                key: const Key('settings-cloud-key-save'),
                onPressed: () async {
                  final v = _keyCtrl.text.trim();
                  if (v.isEmpty) return;
                  await ref.read(cloudKeyStoreProvider).write(v);
                  ref.invalidate(cloudApiKeyProvider);
                  _keyCtrl.clear();
                },
                child: const Text('Save'),
              ),
              const SizedBox(width: 8),
              if (cloudKey != null && cloudKey.isNotEmpty)
                OutlinedButton(
                  key: const Key('settings-cloud-key-clear'),
                  onPressed: () async {
                    await ref.read(cloudKeyStoreProvider).clear();
                    ref.invalidate(cloudApiKeyProvider);
                    await ref
                        .read(cloudInterpretEnabledProvider.notifier)
                        .setEnabled(false);
                  },
                  child: const Text('Clear'),
                ),
            ]),
            SwitchListTile(
              key: const Key('settings-cloud-toggle'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Use cloud for interpretation'),
              subtitle: cloudKey == null || cloudKey.isEmpty
                  ? const Text('Save a key above to enable.')
                  : const Text('Falls back to on-device when off.'),
              value: cloudEnabled,
              onChanged: (cloudKey == null || cloudKey.isEmpty)
                  ? null
                  : (v) => ref
                      .read(cloudInterpretEnabledProvider.notifier)
                      .setEnabled(v),
            ),
            const SizedBox(height: 16),
            Text('Third-party content', style: theme.textTheme.labelLarge),
            // ... rest of the existing build() body unchanged from here ...
```

Keep everything from `Text('Third-party content', ...)` through the end of the existing `build()` method body exactly as it already is — only the two sections above it change (the `AI assistant` section gains nothing new; the new `Cloud interpretation` section is inserted right after it, before `Third-party content`). `_statusBlock` stays a method on the class unchanged (it already takes `BuildContext context, WidgetRef ref, InterpreterStatus? status` as parameters, which still works identically on a `ConsumerState` as it did on the `ConsumerWidget`).

- [ ] **Step 4: Run to verify it passes**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter test test/settings_sheet_test.dart
```

Expected: PASS (2 tests, or more if the file pre-existed with other tests — all must pass).

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings_sheet.dart test/settings_sheet_test.dart
git commit -m "feat(cloud-interpret): Settings UI for the cloud key + toggle"
```

---

## Task 7: Gate-site switches

Switches the interpret-specific readiness checks from `aiReadyProvider` to `interpretReadyProvider`. Every other `aiReadyProvider` read in these files (and all reads in every other file) stays untouched.

**Files:**
- Modify: `lib/features/loop_bar.dart`
- Modify: `lib/features/run_screen.dart`
- Modify: `lib/features/journal_screen.dart`
- Modify: `lib/features/oracle_interpretation_sheet.dart`

- [ ] **Step 1: `loop_bar.dart` — the `aiReady` value fed to `nextBeatActions`**

Find where `LoopBar`'s `build()` computes the `aiReady` local (feeds `nextBeatActions(..., aiReady: aiReady)`). Change its source from `ref.watch(aiReadyProvider)` to `ref.watch(interpretReadyProvider)`. (Grep first to get the exact current line: `grep -n "aiReadyProvider" lib/features/loop_bar.dart`.)

- [ ] **Step 2: `run_screen.dart:749` and `:786`**

```bash
grep -n "aiReadyProvider" lib/features/run_screen.dart
```

Confirmed (during planning) that `aiReady` at line 749 (`final aiReady = ref.watch(aiReadyProvider);`) is used exactly once, at line 786, to gate the inline `run-dice-interpret` button. Change line 749's `aiReadyProvider` to `interpretReadyProvider`. Do not touch any other `aiReadyProvider` read elsewhere in the file if `grep` shows more than this one (re-run the grep to confirm current line numbers before editing, in case other tasks shifted them).

- [ ] **Step 3: `journal_screen.dart` — three sites**

Confirmed during planning (re-grep first: `grep -n "aiReadyProvider" lib/features/journal_screen.dart` to get current line numbers, since earlier tasks may have shifted them):

- The `canInterpret = e.kind == JournalKind.result && ref.read(aiReadyProvider);` line (per-entry popup menu Interpret gate) — switch `aiReadyProvider` → `interpretReadyProvider`.
- The `final canInterpret = ref.read(aiReadyProvider);` line inside the hero-card branch (`PayloadCard`'s inline Interpret gate) — switch to `interpretReadyProvider`.
- The rebuild-trigger line `ref.watch(aiReadyProvider);` near the top of `build()` (comment above it: "Re-render AI affordances (Interpret / Voice / recap) as the AI-ready state flips... _canVoice/canInterpret read aiReadyProvider; this watch is what triggers the rebuild.") — this line must become BOTH watches, since `_canVoice` still needs `aiReadyProvider`'s rebuild trigger and `canInterpret` (both sites above) now needs `interpretReadyProvider`'s:
  ```dart
  ref.watch(aiReadyProvider);
  ref.watch(interpretReadyProvider);
  ```
  Update the comment above it to note both providers are watched for their respective downstream reads.

**Do NOT touch:** `_canVoice => ref.read(aiReadyProvider);` (gates `voiceLine`, frozen/unchanged), the `_aiNudge()` method's `ref.watch(aiSupportedProvider)`/`ref.watch(aiReadyProvider)` (the on-device download nudge — a different concern, stays on-device-only), or the `composer-narrate` button's `ref.watch(aiReadyProvider)` (gates `narrate`, frozen/unchanged).

- [ ] **Step 4: `oracle_interpretation_sheet.dart` — the internal auto-trigger**

Change `_onStatus()`'s trigger condition. Current:

```dart
  void _onStatus() {
    if (!mounted) return;
    setState(() {});
    if (_service.status.value.phase == InterpreterPhase.ready &&
        _cards == null &&
        !_generating) {
      _generate();
    }
  }
```

New — the trigger condition reads `interpretReadyProvider` instead of raw on-device `status`; the `_service.status.addListener` subscription in `initState` stays (still needed to catch on-device phase changes, e.g. download completing), and a second trigger source is added for cloud-only readiness changes:

```dart
  void _onStatus() {
    if (!mounted) return;
    setState(() {});
    if (ref.read(interpretReadyProvider) && _cards == null && !_generating) {
      _generate();
    }
  }
```

In `initState`, after the existing `_service.status.addListener(_onStatus);` line, add a listener for `interpretReadyProvider` so a cloud-only readiness flip (which never touches `_service.status`) also triggers `_onStatus()`. Riverpod's `ConsumerState` doesn't support `ref.listen` outside `build()` directly in older API surfaces still in use here — use `ref.listenManual` if available in the installed `flutter_riverpod` version (`grep -n "flutter_riverpod" pubspec.yaml` shows the pinned version; check `flutter pub deps flutter_riverpod` or the package docs for `listenManual`'s availability at that version). If `listenManual` isn't available, an equivalent: add a `didChangeDependencies` override that calls `_onStatus()` once (covers the common case of the sheet opening after cloud was already configured) — note in a code comment that this is a narrower trigger than a live listener and is acceptable because the sheet is short-lived (opened fresh each time Interpret is tapped, not kept alive across a toggle flip). Prefer `ref.listenManual` if it compiles; only fall back to `didChangeDependencies` if it doesn't.

```dart
  @override
  void initState() {
    super.initState();
    _service = ref.read(interpreterServiceProvider);
    _service.status.addListener(_onStatus);
    ref.listenManual(interpretReadyProvider, (prev, next) => _onStatus());
    _onStatus();
  }
```

- [ ] **Step 5: Run analyze + the affected widget tests**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter analyze lib/features/loop_bar.dart lib/features/run_screen.dart lib/features/journal_screen.dart lib/features/oracle_interpretation_sheet.dart
flutter test test/loop_bar_test.dart test/run_screen_test.dart test/journal_screen_test.dart test/oracle_interpretation_sheet_test.dart
```

(Run `ls test/*run_screen* test/*journal_screen* test/*oracle_interpretation*` first if any filename guess is wrong — adjust the test command to the real filenames.)

Expected: analyze clean; all pass. If any existing test explicitly sets `aiEnabledProvider`/`interpreterServiceProvider` to "ready" to exercise the Interpret path but does NOT also make `interpretReadyProvider` true implicitly (it should — `interpretReadyProvider` is true whenever `aiReadyProvider` is true, per Task 4's Step 3 implementation, so any existing on-device-ready test setup continues to satisfy the new gate for free), no changes to those tests should be needed. If a test fails, read the failure — it most likely means a gate site was missed or mis-identified; re-grep and re-check against the specific line's *purpose* (interpret vs. another seam) before changing it.

- [ ] **Step 6: Commit**

```bash
git add lib/features/loop_bar.dart lib/features/run_screen.dart lib/features/journal_screen.dart lib/features/oracle_interpretation_sheet.dart
git commit -m "feat(cloud-interpret): switch interpret-only gates to interpretReadyProvider"
```

---

## Task 8: macOS Keychain entitlement — verify, don't guess

`flutter_secure_storage` needs OS Keychain access. macOS App Sandbox entitlements already grant `com.apple.security.network.client` (both `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`, confirmed during planning — likely for the on-device model download). Keychain access for a single, non-extension app generally works with the DEFAULT per-app keychain scope and does NOT require an explicit `keychain-access-groups` entry — that entry is only needed for SHARING keychain items across multiple apps/extensions signed with the same team, which doesn't apply here. Adding a guessed `keychain-access-groups` value (which requires the actual Apple Developer Team ID — not present in `macos/Runner.xcodeproj/project.pbxproj`, confirmed during planning) risks a wrong entry that silently breaks Keychain access, which is worse than no entry at all.

**Files:**
- Modify (conditionally, only if Step 2 shows a failure): `macos/Runner/DebugProfile.entitlements`, `macos/Runner/Release.entitlements`

- [ ] **Step 1: Run the app on macOS**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter run -d macos
```

- [ ] **Step 2: Exercise the Save-key flow live**

Open Settings → Cloud interpretation → type any test string into the API key field → tap Save. Watch the terminal output for a `PlatformException` or a `flutter_secure_storage`-related error.

- [ ] **Step 3a: If Save succeeds with no error**

No entitlement changes needed. Skip to Step 4. Note in the commit message (Task 10's final commit) that macOS Keychain access worked with the app's default per-bundle scope, no `keychain-access-groups` entry required.

- [ ] **Step 3b: If Save throws a Keychain-related PlatformException**

Read the exact error text — it usually names the specific OSStatus code or missing entitlement. Search that exact error against `flutter_secure_storage`'s GitHub issues (`WebSearch` for the error text + "flutter_secure_storage macos") before editing entitlements, since the fix depends on the specific failure (could be a signing issue unrelated to `keychain-access-groups`, e.g. an ad-hoc/unsigned local build). Only add a `keychain-access-groups` entry if the search confirms that's the actual fix for the error seen, and use the app's own bundle id (`net.taylorsoftware.juice`, confirmed in `project.pbxproj`) — do not fabricate a team-id prefix; if one is required, get it by running `codesign -dvvv build/macos/Build/Products/Debug/juice.app 2>&1 | grep -i "TeamIdentifier"` after a local build, which prints the real local signing identity.

- [ ] **Step 4: Stop the app**

```bash
# Ctrl-C in the flutter run terminal, or:
```

- [ ] **Step 5: Commit (only if entitlements changed in Step 3b)**

```bash
git add macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements
git commit -m "fix(cloud-interpret): macOS Keychain entitlement for secure key storage"
```

If nothing changed (Step 3a), there's nothing to commit for this task — proceed to Task 9.

---

## Task 9: Full-suite verification

**Files:** none (verification only)

- [ ] **Step 1: Full analyze**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter analyze
```

Expected: `No issues found!`.

- [ ] **Step 2: Full test suite**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter test
```

Expected: `All tests passed!`, count ≥ 1798 (1787 from Phase 1 + the ~11 new test files' tests added in this plan; exact count isn't load-bearing, "all pass, none skipped/failed" is).

- [ ] **Step 3: Confirm no real network call is reachable from any test**

```bash
grep -rn "AnthropicClient\|anthropic_sdk_dart" test/ | grep -v "cloud_interpreter_test.dart\|routing_interpreter_service_test.dart"
```

Expected: empty (or only import lines in the two files that legitimately need the type for mocking — no other test file should construct a real `AnthropicClient` without an injected `httpClient`).

- [ ] **Step 4: If anything fails, fix in place**

Do not proceed to Task 10 until analyze is clean and the full suite is green.

---

## Task 10: Manual smoke + wrap-up commit

**Files:** none (manual verification)

- [ ] **Step 1: Manual smoke on macOS**

```bash
export PATH="$PATH:/Users/johntaylor/development/flutter/bin"
flutter run -d macos
```

Walk through: Settings → save a real (or throwaway) Claude API key → Clear it once to confirm the toggle disables again → save it again → flip "Use cloud for interpretation" on → go to a campaign's Play surface → create a scene → Ask → Interpret (via Next-beat). Confirm the inline `_InterpretCard` shows a reading (a REAL API call this time, using whatever key was pasted — use a real key with a small balance, or expect/accept a visible auth-error state if using a throwaway key, which itself confirms the error+Retry path from Phase 1 still works end-to-end with the new transport).

- [ ] **Step 2: Toggle cloud off, confirm on-device path (or "not ready" state) still works**

With the toggle off, repeat Ask → Interpret. If the on-device model was never downloaded on this machine, expect the Interpret action to be absent from the Next-beat menu (since `interpretReadyProvider` correctly falls back to `aiReadyProvider`, which is false) rather than any crash.

- [ ] **Step 3: Confirm the 6 frozen seams are unaffected**

With cloud enabled, open the assistant rail's "Ask the GM" box, or the journal's `composer-narrate` button, or the Sheet roster's Generate-NPC flesh-out. Confirm these STILL show as disabled/hidden if the on-device model isn't downloaded — i.e., enabling cloud did not unlock them. This is the single most important behavioral guarantee of this whole plan; if any of these appear enabled when only cloud (not on-device) is ready, that's a genuine regression — stop and fix the specific gate site (grep for it, it means an `aiReadyProvider` read was missed or incorrectly switched in Task 7).

- [ ] **Step 4: Final commit if any smoke-driven fixes were needed**

```bash
git add -A
git commit -m "fix(cloud-interpret): <describe the specific smoke-test fix>"
```

If no fixes were needed during smoke testing, there's nothing to commit here.

---

## Self-Review Notes

- **Spec coverage:** new deps (T1) — flutter_secure_storage key storage (T2) — CloudInterpreter/Claude transport (T3) — cloud toggle + scoped readiness (T4) — routing decorator, zero call-site changes to loop_bar/oracle_interpretation_sheet (T5) — Settings UI incl. web-style visibility (T6) — gate-site switches at all 4 confirmed files incl. the sheet's internal auto-trigger fix found during planning (T7) — macOS platform verification without guessing entitlements (T8) — full-suite + no-real-network-in-tests guarantee (T9) — end-to-end smoke incl. explicitly verifying the 6 frozen seams stay untouched (T10). Covered.
- **Naming consistency checked:** `CloudKeyStore`/`SecureCloudKeyStore`/`FakeCloudKeyStore`, `CloudInterpreter`/`CloudInterpreter.model`, `RoutingInterpreterService`, `cloudKeyStoreProvider`/`cloudApiKeyProvider`/`cloudInterpretEnabledProvider`/`CloudInterpretEnabledNotifier`/`interpretReadyProvider` used identically across every task that references them.
- **Known deviation from the spec's draft code** (both are correct implementations of the same approved architecture, not a scope change): the spec sketched the routing decorator taking a raw `Ref`; this plan uses injected closures instead, for constructor-level testability without `ProviderContainer`. `interpreterServiceProvider`'s wiring (Task 5 Step 5) is exactly what the spec described.
- **Genuinely uncertain external API detail flagged, not guessed:** `MessageCreateRequest.system`'s exact type (Task 1 Step 4 + Task 3's fallback comment) — the plan tells the implementer how to verify against the real resolved package source rather than trusting an unconfirmed web-doc claim.
