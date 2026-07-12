import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/state/providers.dart';

void main() {
  test('text scale defaults to 1.0, persists, and clamps', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(textScaleProvider.future), 1.0);

    await c.read(textScaleProvider.notifier).set(1.2);
    expect(c.read(textScaleProvider).value, 1.2);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('juice.text_scale.v1'), 1.2);

    await c.read(textScaleProvider.notifier).set(9.0);
    expect(c.read(textScaleProvider).value, 1.4); // clamped
    await c.read(textScaleProvider.notifier).set(0.1);
    expect(c.read(textScaleProvider).value, 0.85);
  });

  test('persisted scale loads on build', () async {
    SharedPreferences.setMockInitialValues({'juice.text_scale.v1': 1.15});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(textScaleProvider.future), 1.15);
  });
}
