# AI enable toggle + Settings dialog + affordance gating — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate every AI affordance behind an explicit, discoverable opt-in — a Settings gear that owns the model download plus an app-global enable toggle — so AI buttons stay hidden until the model is both downloaded and enabled.

**Architecture:** A new app-global `aiEnabledProvider` (default off, non-exported pref) and a reactive `interpreterStatusProvider` (wraps the service's `ValueListenable`) combine into `aiReadyProvider = enabled && phase==ready`, which every AI affordance watches. A new Settings sheet (opened from a home-shell gear) owns the download/consent flow; the interpret sheet's inline download UI is stripped.

**Tech Stack:** Flutter, flutter_riverpod (AsyncNotifier/StreamProvider/Provider), shared_preferences. Tests: flutter_test + the shared `test/fake_interpreter.dart`.

Spec: `docs/superpowers/specs/2026-06-22-ai-enable-settings-gating-design.md`

---

## File structure

| File | Responsibility |
|------|----------------|
| `lib/state/providers.dart` | `AiEnabledNotifier`+`aiEnabledProvider`; `interpreterStatusProvider`, `aiReadyProvider`, `aiSupportedProvider` (all here to avoid an interpreter.dart↔providers.dart import cycle) |
| `lib/features/settings_sheet.dart` | **new** — `showSettingsSheet(context)` + the AI-assistant section |
| `lib/shared/home_shell.dart` | gear `IconButton` in the app bar → `showSettingsSheet` |
| `lib/features/journal_screen.dart` | re-gate Interpret / Voice / recap on `aiReadyProvider` |
| `lib/features/assistant_rail.dart` | gate the Ask-GM box on `aiReadyProvider` |
| `lib/features/sidekick_screen.dart` | gate Voice on `aiReadyProvider` |
| `lib/features/oracle_interpretation_sheet.dart` | strip download UI; assume ready |
| `test/ai_providers_test.dart` | **new** — provider truth table |
| `test/settings_sheet_test.dart` | **new** — Settings sheet per phase |
| existing AI tests | enable AI where they assert AI buttons |

---

## Task 1: `aiEnabledProvider` (app-global enable flag)

**Files:**
- Modify: `lib/state/providers.dart`
- Test: `test/ai_providers_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/ai_providers_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('aiEnabledProvider defaults to false and persists setEnabled', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);

    expect(await c.read(aiEnabledProvider.future), isFalse);
    await c.read(aiEnabledProvider.notifier).setEnabled(true);
    expect(c.read(aiEnabledProvider).valueOrNull, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('juice.ai_enabled.v1'), isTrue);
  });

  test('aiEnabledProvider reads an existing true pref', () async {
    SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': true});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(aiEnabledProvider.future), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ai_providers_test.dart`
Expected: FAIL — `aiEnabledProvider` undefined.

- [ ] **Step 3: Implement the provider**

In `lib/state/providers.dart`, after the `settingsProvider` definition (~line 1053), add. Ensure `import 'interpreter.dart';` and `import 'dart:async';` exist at the top of the file (add if missing).

```dart
// -- AI enable (app-global; NOT per-campaign, NOT exported) -----------------
class AiEnabledNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.ai_enabled.v1';

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> setEnabled(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(_key, value);
    state = AsyncData(value);
  }
}

final aiEnabledProvider =
    AsyncNotifierProvider<AiEnabledNotifier, bool>(AiEnabledNotifier.new);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ai_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/ai_providers_test.dart
git commit -m "feat(ai): app-global aiEnabledProvider (default off)"
```

---

## Task 2: reactive status + derived gates

**Files:**
- Modify: `lib/state/providers.dart`
- Test: `test/ai_providers_test.dart` (extend)

- [ ] **Step 1: Write the failing tests**

Append to `test/ai_providers_test.dart` `main()`:

```dart
  group('gates', () {
    ProviderContainer make(InterpreterStatus initial, {bool enabled = false}) {
      SharedPreferences.setMockInitialValues(
          {'juice.ai_enabled.v1': enabled});
      final fake = FakeInterpreterService(initial: initial);
      final c = ProviderContainer(overrides: [
        interpreterServiceProvider.overrideWithValue(fake),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('aiReady true only when enabled AND ready', () async {
      final c = make(const InterpreterStatus(InterpreterPhase.ready),
          enabled: true);
      await c.read(aiEnabledProvider.future);
      // seed the stream
      await c.read(interpreterStatusProvider.future);
      expect(c.read(aiReadyProvider), isTrue);
    });

    test('aiReady false when ready but disabled', () async {
      final c = make(const InterpreterStatus(InterpreterPhase.ready));
      await c.read(aiEnabledProvider.future);
      await c.read(interpreterStatusProvider.future);
      expect(c.read(aiReadyProvider), isFalse);
    });

    test('aiReady false when enabled but needsDownload', () async {
      final c = make(const InterpreterStatus(InterpreterPhase.needsDownload),
          enabled: true);
      await c.read(aiEnabledProvider.future);
      await c.read(interpreterStatusProvider.future);
      expect(c.read(aiReadyProvider), isFalse);
    });

    test('aiSupported false only for unsupported', () async {
      final c = make(const InterpreterStatus(InterpreterPhase.unsupported));
      await c.read(interpreterStatusProvider.future);
      expect(c.read(aiSupportedProvider), isFalse);
    });
  });
```

Add imports at the top of the test file:

```dart
import 'package:juice_oracle/state/interpreter.dart';
import 'fake_interpreter.dart';
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ai_providers_test.dart`
Expected: FAIL — `interpreterStatusProvider`/`aiReadyProvider`/`aiSupportedProvider` undefined.

- [ ] **Step 3: Implement the providers**

In `lib/state/providers.dart`, right after `aiEnabledProvider`:

```dart
/// The interpreter's status as a reactive provider (the service exposes it as
/// a ValueListenable). Lets affordances rebuild as the phase flips.
final interpreterStatusProvider = StreamProvider<InterpreterStatus>((ref) {
  final vl = ref.watch(interpreterServiceProvider).status;
  final controller = StreamController<InterpreterStatus>();
  void listener() => controller.add(vl.value);
  vl.addListener(listener);
  controller.add(vl.value); // seed current value
  ref.onDispose(() {
    vl.removeListener(listener);
    controller.close();
  });
  return controller.stream;
});

/// Single source of truth every AI affordance watches.
/// ready ⇒ downloaded + loaded; enabled ⇒ opted in via Settings.
final aiReadyProvider = Provider<bool>((ref) {
  final enabled = ref.watch(aiEnabledProvider).valueOrNull ?? false;
  final phase = ref.watch(interpreterStatusProvider).valueOrNull?.phase;
  return enabled && phase == InterpreterPhase.ready;
});

/// Settings-only: decides toggle vs "not available on this platform".
final aiSupportedProvider = Provider<bool>((ref) {
  final phase = ref.watch(interpreterStatusProvider).valueOrNull?.phase;
  return phase != null && phase != InterpreterPhase.unsupported;
});
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/ai_providers_test.dart`
Expected: PASS (all in the group).

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/ai_providers_test.dart
git commit -m "feat(ai): reactive interpreterStatus + aiReady/aiSupported gates"
```

---

## Task 3: Settings sheet (AI assistant section)

**Files:**
- Create: `lib/features/settings_sheet.dart`
- Test: `test/settings_sheet_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/settings_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/settings_sheet.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Future<FakeInterpreterService> pump(WidgetTester tester,
    {required InterpreterStatus status, bool enabled = false}) async {
  SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': enabled});
  final fake = FakeInterpreterService(initial: status);
  await tester.pumpWidget(ProviderScope(
    overrides: [interpreterServiceProvider.overrideWithValue(fake)],
    child: MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () => showSettingsSheet(context),
          child: const Text('open'),
        );
      })),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('unsupported: shows not-available, no toggle', (tester) async {
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.unsupported));
    expect(find.textContaining("isn't available"), findsOneWidget);
    expect(find.byKey(const Key('settings-ai-toggle')), findsNothing);
  });

  testWidgets('enabling the toggle calls setEnabled(true)', (tester) async {
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.needsDownload));
    await tester.tap(find.byKey(const Key('settings-ai-toggle')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('juice.ai_enabled.v1'), isTrue);
  });

  testWidgets('enabled + needsDownload shows Download -> warmUp',
      (tester) async {
    final fake = await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.needsDownload),
        enabled: true);
    await tester.tap(find.byKey(const Key('settings-ai-download')));
    await tester.pumpAndSettle();
    expect(fake.warmUpCalls, 1);
  });

  testWidgets('enabled + ready shows Ready', (tester) async {
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.ready),
        enabled: true);
    expect(find.textContaining('Ready'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/settings_sheet_test.dart`
Expected: FAIL — `settings_sheet.dart` / `showSettingsSheet` missing.

- [ ] **Step 3: Implement the sheet**

Create `lib/features/settings_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/interpreter.dart';
import '../state/providers.dart';

/// App-wide settings. P1 holds a single "AI assistant" section that owns the
/// on-device model download + the global enable toggle.
Future<void> showSettingsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SettingsSheet(),
    );

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final supported = ref.watch(aiSupportedProvider);
    final enabled = ref.watch(aiEnabledProvider).valueOrNull ?? false;
    final status = ref.watch(interpreterStatusProvider).valueOrNull;

    return SafeArea(
      child: Padding(
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
                child: Text(
                    "On-device AI isn't available on this platform."),
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
          ],
        ),
      ),
    );
  }

  Widget _statusBlock(
      BuildContext context, WidgetRef ref, InterpreterStatus? status) {
    final service = ref.read(interpreterServiceProvider);
    final phase = status?.phase ?? InterpreterPhase.loading;
    switch (phase) {
      case InterpreterPhase.needsDownload:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Runs on-device. Download the model (${service.downloadLabel}) '
                'over Wi-Fi. One time only.'),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('settings-ai-download'),
              icon: const Icon(Icons.download),
              label: const Text('Download model'),
              onPressed: service.warmUp,
            ),
          ],
        );
      case InterpreterPhase.installing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Downloading… ${status?.progress ?? 0}%'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: (status?.progress ?? 0) / 100),
          ],
        );
      case InterpreterPhase.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Loading model…'),
          ]),
        );
      case InterpreterPhase.ready:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(Icons.check_circle, color: Colors.green, size: 18),
            SizedBox(width: 8),
            Text('Ready'),
          ]),
        );
      case InterpreterPhase.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(status?.message ?? 'Something went wrong.'),
            const SizedBox(height: 8),
            FilledButton.tonal(
              key: const Key('settings-ai-retry'),
              onPressed: service.warmUp,
              child: const Text('Retry'),
            ),
          ],
        );
      case InterpreterPhase.unsupported:
        return const SizedBox.shrink();
    }
  }
}
```

Note: on open with `enabled == true`, the status stream seeds from the
service's current value. If the model is on disk but not loaded the host
service surfaces `needsDownload`/`loading`; tapping Download (or, for an
on-disk model, the service's own `warmUp`) loads it. No `refresh()` call is
needed here because `warmUp` is safe to call repeatedly and the stream is
seeded; if a future host requires an explicit `refresh()` to detect an on-disk
model, add `ref.read(interpreterServiceProvider).refresh()` in an `initState`
of a stateful wrapper. (Out of scope for P1: the fake reaches ready via
`warmUp`.)

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/settings_sheet_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings_sheet.dart test/settings_sheet_test.dart
git commit -m "feat(ai): Settings sheet owning the AI enable toggle + download"
```

---

## Task 4: home-shell gear opens Settings

**Files:**
- Modify: `lib/shared/home_shell.dart` (app-bar `actions:`, after the Help `IconButton` ~line 535)
- Test: `test/home_shell_test.dart` (add one case) — OR rely on settings_sheet_test for the sheet; here just assert the gear exists and opens.

- [ ] **Step 1: Write the failing test**

Add to `test/home_shell_test.dart` (reuse its existing pump helper that builds the shell). Add:

```dart
  testWidgets('settings gear opens the Settings sheet', (tester) async {
    await pumpShell(tester); // existing helper in this file
    await tester.tap(find.byKey(const Key('shell-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
  });
```

If the file's helper has a different name, match it; the key assertion is
tapping `shell-settings` then finding the `Settings` title.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/home_shell_test.dart -j 1`
Expected: FAIL — no `shell-settings` key.

- [ ] **Step 3: Implement the gear**

In `lib/shared/home_shell.dart`, add `import '../features/settings_sheet.dart';`
at the top, and insert in the app-bar `actions:` list immediately after the
Help `IconButton`:

```dart
          IconButton(
            key: const Key('shell-settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => showSettingsSheet(context),
          ),
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/home_shell_test.dart -j 1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/home_shell.dart test/home_shell_test.dart
git commit -m "feat(ai): settings gear in the home-shell app bar"
```

---

## Task 5: re-gate journal Interpret / Voice / recap

**Files:**
- Modify: `lib/features/journal_screen.dart`
- Test: `test/journal_interpret_test.dart`, `test/recap_test.dart`, `test/voice_everywhere_test.dart`

- [ ] **Step 1: Update tests to assert the gate (failing)**

In each of `journal_interpret_test.dart`, `recap_test.dart`,
`voice_everywhere_test.dart`: the existing tests set `phase == ready` and
expect the AI affordance present. They now ALSO need AI enabled. At the top of
each test's pump/setup, add the mock pref so AI is enabled:

```dart
SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': true});
```

(Plus whatever prefs the test already seeds — merge the map.)

Then add ONE new negative case per file (example for interpret):

```dart
testWidgets('Interpret hidden when AI disabled', (tester) async {
  SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': false});
  // ... pump with a ready fake exactly as the positive test does ...
  await tester.tap(find.byKey(const Key('journal-entry-menu-<id>')));
  await tester.pumpAndSettle();
  expect(find.text('Interpret…'), findsNothing);
});
```

- [ ] **Step 2: Run to verify failures**

Run: `flutter test test/journal_interpret_test.dart test/recap_test.dart test/voice_everywhere_test.dart`
Expected: positive tests FAIL (affordance now hidden because default-off pref
wasn't set OR gate not yet wired); negative case FAILs until the gate exists.

- [ ] **Step 3: Wire the gate**

In `lib/features/journal_screen.dart`:

a) Change the `_canVoice` getter (currently ~line 584) to read the new gate:

```dart
  bool get _canVoice => ref.read(aiReadyProvider);
```

b) Change `canInterpret` (currently ~line 592) to:

```dart
    final canInterpret =
        e.kind == JournalKind.result && ref.read(aiReadyProvider);
```

c) Make the screen rebuild when AI state flips: add at the very top of the
main `build()` method (the screen's `build`, the one that lays out the journal
list), before building children:

```dart
    ref.watch(aiReadyProvider); // re-render AI affordances as state flips
```

Ensure `aiReadyProvider` is in scope — it's in `providers.dart`, already
imported by this file (it imports `../state/providers.dart`). Confirm the
import exists.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/journal_interpret_test.dart test/recap_test.dart test/voice_everywhere_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/journal_screen.dart test/journal_interpret_test.dart test/recap_test.dart test/voice_everywhere_test.dart
git commit -m "feat(ai): gate journal Interpret/Voice/recap on aiReady"
```

---

## Task 6: gate the assistant-rail Ask-GM box

**Files:**
- Modify: `lib/features/assistant_rail.dart`
- Test: `test/assistant_rail_test.dart`

- [ ] **Step 1: Update tests (failing)**

In `test/assistant_rail_test.dart`: positive cases (ask-gm-field present) add
`SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': true})` to setup.
Add a negative case:

```dart
testWidgets('ask-gm box hidden when AI not ready', (tester) async {
  SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': false});
  // pump rail with a ready fake, expand it
  await tester.tap(find.byKey(const Key('assistant-expand')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('ask-gm-field')), findsNothing);
});
```

- [ ] **Step 2: Run to verify failures**

Run: `flutter test test/assistant_rail_test.dart`
Expected: FAIL.

- [ ] **Step 3: Wire the gate**

In `lib/features/assistant_rail.dart` `build()`, after
`final suggestions = ref.watch(suggestionsProvider);` add:

```dart
    final aiReady = ref.watch(aiReadyProvider);
```

Then wrap the Ask-GM `Row` (the one containing `ask-gm-field` + `ask-gm-send`,
~lines 148-170) and the `_error` block below it in `if (aiReady) ...`:

```dart
                if (aiReady) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [ /* ask-gm-field + ask-gm-send (unchanged) */ ],
                  ),
                  if (_error != null)
                    Padding( /* unchanged error text */ ),
                ],
```

(Move the existing `const SizedBox(height: 8)` that preceded the Row inside the
`if (aiReady)` block so there's no dangling gap when hidden.) Suggestion chips
stay outside the gate.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/assistant_rail_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/assistant_rail.dart test/assistant_rail_test.dart
git commit -m "feat(ai): gate the assistant-rail Ask-GM box on aiReady"
```

---

## Task 7: gate the sidekick Voice affordance

**Files:**
- Modify: `lib/features/sidekick_screen.dart`
- Test: `test/sidekick_screen_test.dart`

- [ ] **Step 1: Update tests (failing)**

In `test/sidekick_screen_test.dart`: positive cases (sd-voice present) add the
enabled pref. Add a negative case asserting `sd-voice` hidden when AI disabled
(ready fake, pref false).

- [ ] **Step 2: Run to verify failures**

Run: `flutter test test/sidekick_screen_test.dart`
Expected: FAIL.

- [ ] **Step 3: Wire the gate**

In `lib/features/sidekick_screen.dart`, replace the `_voiceArea`
`ValueListenableBuilder`/`ref.read(interpreterServiceProvider)` gate
(~lines 255-261) with the reactive gate:

```dart
  Widget _voiceArea(ThemeData theme, Character? selected) {
    final aiReady = ref.watch(aiReadyProvider);
    if (!aiReady) return const SizedBox.shrink();
    final voiced = _voiced;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        // ... voiced / _voiceError / OutlinedButton block unchanged, EXCEPT
        // the button's onPressed condition drops the phase check:
        //   onPressed: !_voicing ? () => _voice(selected) : null,
      ],
    );
  }
```

Replace the button's `onPressed: status.phase == InterpreterPhase.ready &&
!_voicing ? ... : null` with `onPressed: !_voicing ? () => _voice(selected) :
null` (the `aiReady` guard already gates the whole area). Remove the now-unused
`status`/`ValueListenableBuilder` and the `InterpreterPhase.unsupported` branch.
`_voiceArea` must be called from a `build` that runs in a `ConsumerState` so
`ref.watch` re-renders it — confirm `_voiceArea` is invoked within `build`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/sidekick_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/sidekick_screen.dart test/sidekick_screen_test.dart
git commit -m "feat(ai): gate the sidekick Voice affordance on aiReady"
```

---

## Task 8: strip the interpret sheet's download UI

**Files:**
- Modify: `lib/features/oracle_interpretation_sheet.dart`
- Test: `test/oracle_interpretation_sheet_test.dart`

- [ ] **Step 1: Update tests (failing)**

In `test/oracle_interpretation_sheet_test.dart`: REMOVE tests that exercise the
sheet's `needsDownload`/`installing`/`loading`/warmUp-from-sheet behavior (that
flow now lives in `settings_sheet_test.dart`). KEEP/adjust tests that pump a
`ready` fake and assert interpretation cards generate. Add a test that pumping
a non-ready fake shows the fallback note:

```dart
testWidgets('non-ready shows the enable-in-Settings note', (tester) async {
  // pump sheet with a needsDownload fake
  expect(find.textContaining('Enable AI in Settings'), findsOneWidget);
  expect(find.byKey(const Key('settings-ai-download')), findsNothing);
});
```

- [ ] **Step 2: Run to verify failures**

Run: `flutter test test/oracle_interpretation_sheet_test.dart`
Expected: FAIL (removed-flow tests gone; new note test fails until strip).

- [ ] **Step 3: Strip the download UI**

In `lib/features/oracle_interpretation_sheet.dart`:

a) `initState` (~line 41): remove the `_service.refresh();` line. Keep the
status listener + `_onStatus()` (so the open-while-ready auto-generates):

```dart
  @override
  void initState() {
    super.initState();
    _service = ref.read(interpreterServiceProvider);
    _service.status.addListener(_onStatus);
    _onStatus();
  }
```

b) `_body` (~line 172): replace the entire `switch (status.phase) { … }` block
(the `unsupported`/`needsDownload`/`installing`/`loading`/`error`/`ready: break`
cases) with a single non-ready guard, keeping everything from `if (_generating)`
onward unchanged:

```dart
  Widget _body(BuildContext context) {
    if (_service.status.value.phase != InterpreterPhase.ready) {
      return const _Note(
          icon: Icons.auto_awesome_outlined,
          title: 'Assistant not ready',
          detail: 'Enable AI in Settings to interpret.');
    }
    if (_generating) {
      return const _Note(
          icon: Icons.auto_awesome,
          title: 'Reading the omens…',
          detail: 'The page may be unresponsive while the model writes.',
          spinner: true);
    }
    // ... rest of the existing ready content (generateError / cards) unchanged
  }
```

c) Delete the now-unused `_Consent` widget class from this file. Run a search
for `_Consent` and `interp-warm-retry` and remove their definitions/usages.
`downloadLabel`/`warmUp` are no longer referenced here.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/oracle_interpretation_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/oracle_interpretation_sheet.dart test/oracle_interpretation_sheet_test.dart
git commit -m "refactor(ai): strip interpret sheet download UI; Settings owns it"
```

---

## Task 9: full verification + sweep for other AI tests

**Files:** any remaining test that asserts an AI affordance visible.

- [ ] **Step 1: Run the full suite**

Run: `flutter analyze && flutter test`
Expected: some failures in tests that assert AI buttons but don't enable AI.

- [ ] **Step 2: Fix stragglers**

For each failing test that expects an AI affordance (Interpret/Voice/recap/
ask-gm/sd-voice) with a ready fake, add
`SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': true})` to its
setup (merging with any prefs it already sets). Candidates beyond Tasks 5-8:
`ask_anything_test.dart`, `journal_payload_ui_test.dart`,
`mention_autocomplete_test.dart`, `slash_palette_test.dart` (recap command
visibility), `home_shell_test.dart`. Only touch tests that actually assert an
AI affordance; tests overriding the fake merely to avoid real Gemma need no
change.

- [ ] **Step 3: Re-run to green**

Run: `flutter analyze && flutter test`
Expected: analyze clean (no NEW issues vs the pre-existing
`card_oracle_test.dart:44` info lint), all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add -A -- test/
git commit -m "test(ai): enable AI in tests that assert AI affordances"
```

---

## Self-review notes (done)

- **Spec coverage:** §1 aiEnabled→T1; §2 reactive status→T2; §3 gates→T2;
  §4 Settings sheet→T3 + gear T4; §5 re-gate entry points→T5/T6/T7; §6 strip
  sheet→T8; §Testing→T1-T3 + T5-T9 blast radius. All covered.
- **Type consistency:** `aiEnabledProvider`/`setEnabled`,
  `interpreterStatusProvider`, `aiReadyProvider`, `aiSupportedProvider`,
  `showSettingsSheet`, keys `settings-ai-toggle`/`settings-ai-download`/
  `settings-ai-retry`/`shell-settings` — used identically across tasks.
- **Reactivity caveat:** journal getters use `ref.read` but `build()` adds a
  `ref.watch(aiReadyProvider)` so the screen rebuilds; assistant-rail/sidekick
  use `ref.watch` directly in build.
```
