import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/state/providers.dart';

/// Round-trip tests for the two one-shot dismiss flags added by the
/// cross-cutting polish batch. Both mirror [welcomeSeenProvider]: default
/// false, markSeen flips to true, and the value persists across a fresh
/// container (a new app launch).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('trackHelpSeenProvider: default false → markSeen → persists', () async {
    final c1 = ProviderContainer();
    addTearDown(c1.dispose);
    expect(await c1.read(trackHelpSeenProvider.future), isFalse);
    await c1.read(trackHelpSeenProvider.notifier).markSeen();
    expect(c1.read(trackHelpSeenProvider).valueOrNull, isTrue);

    // A fresh container (new launch) reads the persisted value.
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    expect(await c2.read(trackHelpSeenProvider.future), isTrue);
  });

  test('recapSuppressedProvider: default false → markSeen → persists',
      () async {
    final c1 = ProviderContainer();
    addTearDown(c1.dispose);
    expect(await c1.read(recapSuppressedProvider.future), isFalse);
    await c1.read(recapSuppressedProvider.notifier).markSeen();
    expect(c1.read(recapSuppressedProvider).valueOrNull, isTrue);

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    expect(await c2.read(recapSuppressedProvider.future), isTrue);
  });
}
