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

    test('applyPartyEffect broadcasts HP + conditions to the set only',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
        'juice.characters.v1.default': '['
            '{"id":"p1","name":"A","tracks":[{"label":"HP","current":9,"max":10}]},'
            '{"id":"p2","name":"B","tracks":[{"label":"HP","current":9,"max":10}],"conditions":["hidden"]},'
            '{"id":"npc","name":"N","tracks":[{"label":"HP","current":9,"max":10}]}'
            ']',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(charactersProvider.future);
      await c.read(charactersProvider.notifier).applyPartyEffect(
            {'p1', 'p2'},
            hpDelta: -3,
            addConditions: ['burning'],
          );
      final all = await c.read(charactersProvider.future);
      final p1 = all.firstWhere((e) => e.id == 'p1');
      final p2 = all.firstWhere((e) => e.id == 'p2');
      final npc = all.firstWhere((e) => e.id == 'npc');
      expect(p1.tracks.first.current, 6);
      expect(p1.conditions, ['burning']);
      // Merges with existing conditions; no duplicates.
      expect(p2.tracks.first.current, 6);
      expect(p2.conditions, unorderedEquals(['hidden', 'burning']));
      // Untargeted character untouched.
      expect(npc.tracks.first.current, 9);
      expect(npc.conditions, isEmpty);
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
