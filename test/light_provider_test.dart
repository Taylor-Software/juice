import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('lightProvider: set persists (scoped) + clamps; default 0', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(lightProvider.future), 0);
    await c.read(lightProvider.notifier).set(3);
    expect(c.read(lightProvider).valueOrNull, 3);
    await c.read(lightProvider.notifier).set(-5);
    expect(c.read(lightProvider).valueOrNull, 0); // clamped

    await c.read(lightProvider.notifier).set(2);
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    expect(await c2.read(lightProvider.future), 2); // persisted, scoped key
  });

  test('light key is session-scoped (exported with the campaign)', () {
    expect(sessionScopedKeys, contains('juice.light.v1'));
  });
}
