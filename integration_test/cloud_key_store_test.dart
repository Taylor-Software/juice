// Device integration test proving SecureCloudKeyStore actually works against
// the real OS Keychain (macOS) — unit tests only ever exercise FakeCloudKeyStore,
// so this is the first real proof the platform channel + entitlements are
// sufficient. No widget pumping needed — SecureCloudKeyStore has zero Flutter
// UI dependency, it's a pure flutter_secure_storage wrapper.
//
// Run: flutter test integration_test/cloud_key_store_test.dart -d macos

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juice_oracle/state/cloud_key_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SecureCloudKeyStore round-trips a value on the real Keychain',
      (tester) async {
    final store = SecureCloudKeyStore();
    // Clean slate in case a prior run left a value.
    await store.clear();
    expect(await store.read(), isNull);

    await store.write('sk-ant-integration-test-value');
    expect(await store.read(), 'sk-ant-integration-test-value');

    await store.clear();
    expect(await store.read(), isNull);
  });
}
