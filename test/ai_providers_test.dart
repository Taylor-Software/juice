import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

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

  group('gates', () {
    ProviderContainer make(InterpreterStatus initial, {bool enabled = false}) {
      SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': enabled});
      final fake = FakeInterpreterService(initial: initial);
      final c = ProviderContainer(overrides: [
        interpreterServiceProvider.overrideWithValue(fake),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('aiReady true only when enabled AND ready', () async {
      final c =
          make(const InterpreterStatus(InterpreterPhase.ready), enabled: true);
      await c.read(aiEnabledProvider.future);
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

    test('aiSupported true for a real phase', () async {
      final c = make(const InterpreterStatus(InterpreterPhase.needsDownload));
      await c.read(interpreterStatusProvider.future);
      expect(c.read(aiSupportedProvider), isTrue);
    });
  });
}
