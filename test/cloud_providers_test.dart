import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_cloud_key_store.dart';
import 'fake_interpreter.dart';

void main() {
  test('cloudInterpretEnabledProvider defaults to false and persists',
      () async {
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
      final c =
          make(onDevicePhase: InterpreterPhase.ready, onDeviceEnabled: true);
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
