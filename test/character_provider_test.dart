import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Character.role + conditions', () {
    test('defaults: role pc, no conditions, omitted from json', () {
      const c = Character(id: 'a', name: 'A');
      expect(c.role, CharacterRole.pc);
      expect(c.conditions, isEmpty);
      expect(c.toJson().containsKey('role'), isFalse);
      expect(c.toJson().containsKey('conditions'), isFalse);
    });
    test('npc role + conditions round-trip', () {
      const c = Character(
          id: 'a',
          name: 'A',
          role: CharacterRole.npc,
          conditions: ['poisoned', 'hurt']);
      final back = Character.fromJson(c.toJson());
      expect(back.role, CharacterRole.npc);
      expect(back.conditions, ['poisoned', 'hurt']);
    });
    test('copyWith updates role + conditions', () {
      const c = Character(id: 'a', name: 'A');
      final c2 =
          c.copyWith(role: CharacterRole.companion, conditions: ['hidden']);
      expect(c2.role, CharacterRole.companion);
      expect(c2.conditions, ['hidden']);
    });
    test('kConditions has the authored presets', () {
      expect(kConditions, contains('poisoned'));
      expect(kConditions, contains('exhausted'));
    });
  });

  group('CharacterNotifier role/conditions', () {
    test('setRole + setConditions persist', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
        'juice.characters.v1.default':
            '[{"id":"c1","name":"Ash","stats":[],"tracks":[],"tags":[]}]',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(charactersProvider.future);
      await c
          .read(charactersProvider.notifier)
          .setRole('c1', CharacterRole.npc);
      await c
          .read(charactersProvider.notifier)
          .setConditions('c1', ['poisoned']);
      final ch = (await c.read(charactersProvider.future)).single;
      expect(ch.role, CharacterRole.npc);
      expect(ch.conditions, ['poisoned']);
    });
  });

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

  test('addShadowdark prepends a premade Shadowdark character', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(charactersProvider.future);
    final id = await c.read(charactersProvider.notifier).addShadowdark();
    final chars = await c.read(charactersProvider.future);
    expect(chars.first.id, id);
    expect(chars.first.shadowdark, isNotNull);
    expect(chars.first.shadowdark!.className, 'Fighter');
  });
}
