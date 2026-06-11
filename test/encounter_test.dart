import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/campaign_io.dart';
import 'package:juice_oracle/state/providers.dart';

Map<String, dynamic> _c(String id, int init,
        {bool defeated = false, String? characterId}) =>
    <String, dynamic>{
      'id': id,
      'name': id.toUpperCase(),
      'characterId': characterId,
      'initiative': init,
      'track': null,
      'tags': const <String>[],
      'defeated': defeated,
    };

String _enc(List<Map<String, dynamic>> combatants,
        {int turnIndex = 0, int round = 1}) =>
    jsonEncode(
        {'combatants': combatants, 'turnIndex': turnIndex, 'round': round});

ProviderContainer _container({String? encounterJson}) {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    if (encounterJson != null) 'juice.encounter.v1.default': encounterJson,
  });
  return ProviderContainer();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Encounter models', () {
    test('ad-hoc and linked combatants round-trip through EncounterState',
        () {
      const adHoc = Combatant(
        id: 'a',
        name: 'Goblin',
        initiative: 12,
        track: CharTrack(label: 'HP', current: 4, max: 6),
        tags: ['poisoned'],
        defeated: true,
      );
      const linked = Combatant(
        id: 'b',
        name: 'Ash',
        characterId: 'char1',
        initiative: 17,
      );
      const s =
          EncounterState(combatants: [linked, adHoc], turnIndex: 1, round: 3);
      final back = EncounterState.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.turnIndex, 1);
      expect(back.round, 3);
      expect(back.combatants, hasLength(2));
      final l = back.combatants[0];
      expect(l.id, 'b');
      expect(l.name, 'Ash');
      expect(l.characterId, 'char1');
      expect(l.initiative, 17);
      expect(l.track, isNull);
      expect(l.tags, isEmpty);
      expect(l.defeated, isFalse);
      final a = back.combatants[1];
      expect(a.characterId, isNull);
      expect(a.track!.current, 4);
      expect(a.track!.max, 6);
      expect(a.tags, ['poisoned']);
      expect(a.defeated, isTrue);
    });

    test('tolerant parse: empty map and sparse combatant entries', () {
      final empty = EncounterState.fromJson(<String, dynamic>{});
      expect(empty.combatants, isEmpty);
      expect(empty.turnIndex, 0);
      expect(empty.round, 1);

      final c = Combatant.fromJson(
          <String, dynamic>{'id': 'x', 'name': 'N', 'initiative': 5});
      expect(c.tags, isEmpty);
      expect(c.defeated, isFalse);
      expect(c.track, isNull);
      expect(c.characterId, isNull);

      // Out-of-range turnIndex (corrupt/hand-edited payload) clamps so
      // index-based notifier ops can't throw.
      final clamped = EncounterState.fromJson(<String, dynamic>{
        'combatants': [_c('a', 10)],
        'turnIndex': 99,
      });
      expect(clamped.turnIndex, 0);
    });
  });

  group('EncounterNotifier.addCombatant', () {
    test('keeps descending initiative; tie goes after equals', () async {
      final container = _container();
      addTearDown(container.dispose);
      final n = container.read(encounterProvider.notifier);
      await n.addCombatant(const Combatant(id: 'a', name: 'A', initiative: 15));
      await n.addCombatant(const Combatant(id: 'b', name: 'B', initiative: 15));
      await n.addCombatant(const Combatant(id: 'c', name: 'C', initiative: 20));
      final s = await container.read(encounterProvider.future);
      expect(s.combatants.map((c) => c.id), ['c', 'a', 'b']);
      // a (current when added first) stays current: c inserted above shifts
      // the pointer; empty-list insert had left it at 0.
      expect(s.turnIndex, 1);
    });

    test('turnIndex follows the current combatant on insert above it',
        () async {
      final container = _container(
          encounterJson:
              _enc([_c('a', 20), _c('b', 15), _c('c', 10)], turnIndex: 1));
      addTearDown(container.dispose);
      await container.read(encounterProvider.notifier).addCombatant(
          const Combatant(id: 'd', name: 'D', initiative: 25));
      final s = await container.read(encounterProvider.future);
      expect(s.combatants.map((c) => c.id), ['d', 'a', 'b', 'c']);
      expect(s.turnIndex, 2); // still pointing at b
    });
  });

  group('EncounterNotifier.nextTurn', () {
    test('skips defeated and wraps with round increment', () async {
      final container = _container(
          encounterJson: _enc(
              [_c('a', 20), _c('b', 15, defeated: true), _c('c', 10)]));
      addTearDown(container.dispose);
      final n = container.read(encounterProvider.notifier);
      await n.nextTurn();
      var s = await container.read(encounterProvider.future);
      expect(s.turnIndex, 2); // skipped defeated b
      expect(s.round, 1);
      await n.nextTurn();
      s = await container.read(encounterProvider.future);
      expect(s.turnIndex, 0); // wrapped
      expect(s.round, 2);
    });

    test('no-ops when all combatants are defeated', () async {
      final container = _container(
          encounterJson: _enc(
              [_c('a', 20, defeated: true), _c('b', 15, defeated: true)]));
      addTearDown(container.dispose);
      await container.read(encounterProvider.notifier).nextTurn();
      final s = await container.read(encounterProvider.future);
      expect(s.turnIndex, 0);
      expect(s.round, 1);
    });

    test('no-ops on an empty encounter', () async {
      final container = _container();
      addTearDown(container.dispose);
      await container.read(encounterProvider.notifier).nextTurn();
      final s = await container.read(encounterProvider.future);
      expect(s.turnIndex, 0);
      expect(s.round, 1);
    });
  });

  group('EncounterNotifier.reorder', () {
    test('moves up and turnIndex follows the pointed-at combatant', () async {
      final container = _container(
          encounterJson:
              _enc([_c('a', 20), _c('b', 15), _c('c', 10)], turnIndex: 2));
      addTearDown(container.dispose);
      await container.read(encounterProvider.notifier).reorder(2, 0);
      final s = await container.read(encounterProvider.future);
      expect(s.combatants.map((c) => c.id), ['c', 'a', 'b']);
      expect(s.turnIndex, 0); // still pointing at c
    });

    test('moves down (ReorderableListView raw newIndex) and pointer follows',
        () async {
      final container = _container(
          encounterJson:
              _enc([_c('a', 20), _c('b', 15), _c('c', 10)], turnIndex: 0));
      addTearDown(container.dispose);
      await container.read(encounterProvider.notifier).reorder(0, 3);
      final s = await container.read(encounterProvider.future);
      expect(s.combatants.map((c) => c.id), ['b', 'c', 'a']);
      expect(s.turnIndex, 2); // still pointing at a
    });
  });

  group('EncounterNotifier.removeCombatant', () {
    test('removing before the pointer shifts turnIndex down', () async {
      final container = _container(
          encounterJson:
              _enc([_c('a', 20), _c('b', 15), _c('c', 10)], turnIndex: 1));
      addTearDown(container.dispose);
      await container.read(encounterProvider.notifier).removeCombatant('a');
      final s = await container.read(encounterProvider.future);
      expect(s.combatants.map((c) => c.id), ['b', 'c']);
      expect(s.turnIndex, 0); // still pointing at b
    });

    test('removing the pointed combatant clamps within range', () async {
      final container = _container(
          encounterJson:
              _enc([_c('a', 20), _c('b', 15), _c('c', 10)], turnIndex: 2));
      addTearDown(container.dispose);
      final n = container.read(encounterProvider.notifier);
      await n.removeCombatant('c');
      var s = await container.read(encounterProvider.future);
      expect(s.combatants.map((c) => c.id), ['a', 'b']);
      expect(s.turnIndex, 1); // clamped to last index
      await n.removeCombatant('b');
      await n.removeCombatant('a');
      s = await container.read(encounterProvider.future);
      expect(s.combatants, isEmpty);
      expect(s.turnIndex, 0);
    });
  });

  group('EncounterNotifier updateCombatant / reset / persistence', () {
    test('updateCombatant replaces by id', () async {
      final container =
          _container(encounterJson: _enc([_c('a', 20), _c('b', 15)]));
      addTearDown(container.dispose);
      final s0 = await container.read(encounterProvider.future);
      await container
          .read(encounterProvider.notifier)
          .updateCombatant(s0.combatants[1].copyWith(defeated: true));
      final s = await container.read(encounterProvider.future);
      expect(s.combatants[0].defeated, isFalse);
      expect(s.combatants[1].defeated, isTrue);
    });

    test('save persists; a fresh container reloads under the session key',
        () async {
      final container = _container();
      await container.read(encounterProvider.future);
      await container.read(encounterProvider.notifier).addCombatant(
          const Combatant(id: 'a', name: 'A', initiative: 13));
      container.dispose();

      final fresh = ProviderContainer(); // same mock prefs store
      addTearDown(fresh.dispose);
      final s = await fresh.read(encounterProvider.future);
      expect(s.combatants.single.name, 'A');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('juice.encounter.v1.default'),
          contains('"initiative":13'));
    });

    test('reset returns a fresh EncounterState and persists it', () async {
      final container = _container(
          encounterJson: _enc([_c('a', 20)], turnIndex: 0, round: 4));
      addTearDown(container.dispose);
      await container.read(encounterProvider.notifier).reset();
      final s = await container.read(encounterProvider.future);
      expect(s.combatants, isEmpty);
      expect(s.round, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('juice.encounter.v1.default'),
          contains('"round":1'));
    });
  });

  group('Campaign file encounter key', () {
    test('round-trips through encode/parse and rejects wrong shape', () {
      final out = encodeCampaign(
        name: 'C1',
        savedAt: DateTime(2026, 6, 11),
        rawByKey: {'juice.encounter.v1': _enc([_c('a', 20)], round: 2)},
      );
      final parsed = parseCampaign(out);
      expect(parsed.rawByKey['juice.encounter.v1'], contains('"round":2'));
      expect(
        () => parseCampaign('{"app":"juice-oracle","schemaVersion":2,'
            '"name":"x","data":{"juice.encounter.v1":[1,2]}}'),
        throwsFormatException,
      );
    });
  });
}
