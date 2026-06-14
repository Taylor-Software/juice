import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('add, toggle, remove rumors persist', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(rumorsProvider.future);
    await c.read(rumorsProvider.notifier).add('North gate');
    final list = c.read(rumorsProvider).value!;
    expect(list.single.text, 'North gate');
    await c.read(rumorsProvider.notifier).toggleResolved(list.single.id);
    expect(c.read(rumorsProvider).value!.single.resolved, isTrue);
    await c.read(rumorsProvider.notifier).remove(list.single.id);
    expect(c.read(rumorsProvider).value, isEmpty);
  });
}
