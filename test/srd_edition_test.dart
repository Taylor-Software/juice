import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/spell.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionMeta.dndEdition', () {
    test('round-trips through toJson/fromJson and copyWith', () {
      const m = SessionMeta(id: 'a', name: 'C', dndEdition: '5.2');
      final j = m.toJson();
      expect(j['dndEdition'], '5.2');
      expect(SessionMeta.fromJson(j).dndEdition, '5.2');
      // null omitted from JSON
      expect(const SessionMeta(id: 'b', name: 'D').toJson()['dndEdition'],
          isNull);
      // copyWith sets + preserves
      expect(m.copyWith(name: 'X').dndEdition, '5.2');
      expect(const SessionMeta(id: 'c', name: 'E')
          .copyWith(dndEdition: '5.1')
          .dndEdition, '5.1');
    });
  });

  group('content edition filter', () {
    List<Override> overrides(String edition) => [
          enabledContentSystemsProvider.overrideWithValue(const ['dnd']),
          dndEditionProvider.overrideWithValue(edition),
          systemSpellsProvider('dnd').overrideWith((ref) async => const [
                SpellEntry(
                    id: 'dnd-fireball',
                    system: 'dnd',
                    edition: '5.1',
                    name: 'Fireball'),
                SpellEntry(
                    id: 'dnd-2024-fireball',
                    system: 'dnd',
                    edition: '5.2',
                    name: 'Fireball'),
              ]),
          systemFoesProvider('dnd').overrideWith((ref) async => const [
                Creature(id: 'dnd-goblin', name: 'Goblin', edition: '5.1'),
                Creature(
                    id: 'dnd-2024-goblin', name: 'Goblin', edition: '5.2'),
              ]),
        ];

    test('default (5.2) shows only 5.2 spells + monsters', () async {
      final c = ProviderContainer(overrides: overrides('5.2'));
      addTearDown(c.dispose);
      final spells = await c.read(contentSpellsProvider.future);
      expect(spells.map((s) => s.id), ['dnd-2024-fireball']);
      final foes = await c.read(contentMonstersProvider.future);
      expect(foes.map((f) => f.id), ['dnd-2024-goblin']);
    });

    test('5.1 selection flips to only 5.1', () async {
      final c = ProviderContainer(overrides: overrides('5.1'));
      addTearDown(c.dispose);
      final spells = await c.read(contentSpellsProvider.future);
      expect(spells.map((s) => s.id), ['dnd-fireball']);
      final foes = await c.read(contentMonstersProvider.future);
      expect(foes.map((f) => f.id), ['dnd-goblin']);
    });

    test('non-edition entries are never filtered out', () async {
      final c = ProviderContainer(overrides: [
        enabledContentSystemsProvider.overrideWithValue(const ['dnd']),
        dndEditionProvider.overrideWithValue('5.2'),
        systemSpellsProvider('dnd').overrideWith((ref) async => const [
              SpellEntry(
                  id: 'x-bolt', system: 'other', name: 'Bolt'), // no edition
            ]),
        systemFoesProvider('dnd').overrideWith((ref) async => const []),
      ]);
      addTearDown(c.dispose);
      final spells = await c.read(contentSpellsProvider.future);
      expect(spells.map((s) => s.id), ['x-bolt']);
    });
  });

  group('setDndEdition', () {
    test('persists onto the active campaign and drives dndEditionProvider',
        () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"s1","sessions":[{"id":"s1","name":"C1"}]}',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(sessionsProvider.future);
      expect(c.read(dndEditionProvider), '5.2'); // default
      await c.read(sessionsProvider.notifier).setDndEdition('s1', '5.1');
      expect(c.read(dndEditionProvider), '5.1');
      expect(
          c.read(sessionsProvider).valueOrNull!.activeMeta.dndEdition, '5.1');
    });
  });
}
