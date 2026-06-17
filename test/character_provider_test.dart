import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('addIronsworn prepends a premade Ironsworn character', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(charactersProvider.future);
    final id = await c.read(charactersProvider.notifier).addIronsworn();
    final chars = await c.read(charactersProvider.future);
    expect(chars.first.id, id);
    expect(chars.first.ironsworn, isNotNull);
    expect(chars.first.ironsworn!.edge, 3);
  });

  test('addStarforged prepends a premade Starforged character', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(charactersProvider.future);
    final id = await c.read(charactersProvider.notifier).addStarforged();
    final chars = await c.read(charactersProvider.future);
    expect(chars.first.id, id);
    expect(chars.first.starforged, isNotNull);
    expect(chars.first.starforged!.edge, 3);
  });

  test('addDnd prepends a premade D&D character', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(charactersProvider.future);
    final id = await c.read(charactersProvider.notifier).addDnd();
    final chars = await c.read(charactersProvider.future);
    expect(chars.first.id, id);
    expect(chars.first.dnd, isNotNull);
    expect(chars.first.dnd!.className, 'Fighter');
  });
}
