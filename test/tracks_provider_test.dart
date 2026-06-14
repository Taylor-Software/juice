import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('add and adjust clamps within [0, max]', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(tracksProvider.future);
    await c.read(tracksProvider.notifier).add('Find the heir');
    final id = c.read(tracksProvider).value!.single.id;
    await c.read(tracksProvider.notifier).adjust(id, 3);
    expect(c.read(tracksProvider).value!.single.filled, 3);
    await c.read(tracksProvider.notifier).adjust(id, -10);
    expect(c.read(tracksProvider).value!.single.filled, 0);
    await c.read(tracksProvider.notifier).adjust(id, 999);
    expect(c.read(tracksProvider).value!.single.filled, 10);
  });
}
