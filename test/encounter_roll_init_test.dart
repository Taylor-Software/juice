import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      }));

  test('rollInitiativeForAll fills unset (<=0) initiatives and sorts desc',
      () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(encounterProvider.notifier);
    await c.read(encounterProvider.future);
    await n.addCombatant(const Combatant(
        id: 'a', name: 'A', initiative: 0, track: CharTrack(label: 'HP', current: 5, max: 5)));
    await n.addCombatant(const Combatant(
        id: 'b', name: 'B', initiative: 0, track: CharTrack(label: 'HP', current: 5, max: 5)));
    await n.addCombatant(const Combatant(
        id: 'c', name: 'C', initiative: 18, track: CharTrack(label: 'HP', current: 5, max: 5)));

    await n.rollInitiativeForAll(dice: Dice(Random(1)));
    final s = await c.read(encounterProvider.future);

    // typed value (18) preserved; the two zeros got d20 rolls
    expect(s.combatants.firstWhere((x) => x.id == 'c').initiative, 18);
    expect(s.combatants.firstWhere((x) => x.id == 'a').initiative, inInclusiveRange(1, 20));
    expect(s.combatants.firstWhere((x) => x.id == 'b').initiative, inInclusiveRange(1, 20));
    // sorted descending + turn pointer reset to top
    final inits = s.combatants.map((x) => x.initiative).toList();
    expect(inits, [...inits]..sort((p, q) => q.compareTo(p)));
    expect(s.turnIndex, 0);
  });

  test('rollInitiativeForAll is a no-op on empty', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(encounterProvider.notifier);
    await c.read(encounterProvider.future);
    await n.rollInitiativeForAll(dice: Dice(Random(1))); // empty: no throw
    expect((await c.read(encounterProvider.future)).combatants, isEmpty);
  });

  test('rollInitiativeForAll preserves all-typed inits and re-sorts desc',
      () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(encounterProvider.notifier);
    await c.read(encounterProvider.future);
    // All typed (> 0); addCombatant already inserts in desc order.
    await n.addCombatant(const Combatant(
        id: 'a', name: 'A', initiative: 8, track: CharTrack(label: 'HP', current: 5, max: 5)));
    await n.addCombatant(const Combatant(
        id: 'b', name: 'B', initiative: 20, track: CharTrack(label: 'HP', current: 5, max: 5)));

    await n.rollInitiativeForAll(dice: Dice(Random(1)));
    final s = await c.read(encounterProvider.future);
    // No rolls happened (values unchanged), order is descending.
    expect(s.combatants.firstWhere((x) => x.id == 'a').initiative, 8);
    expect(s.combatants.firstWhere((x) => x.id == 'b').initiative, 20);
    expect(s.combatants.map((x) => x.initiative).toList(), [20, 8]);
  });

  test('initMod round-trips and toJson omits zero', () {
    const c = Combatant(id: 'a', name: 'A', initiative: 5, initMod: 3);
    final j = c.toJson();
    expect(j['initMod'], 3);
    expect(Combatant.fromJson(j).initMod, 3);
    expect(
        const Combatant(id: 'b', name: 'B', initiative: 1)
            .toJson()
            .containsKey('initMod'),
        false);
    expect(
        Combatant.fromJson({
          'id': 'b',
          'name': 'B',
          'initiative': 1,
          'track': null,
          'tags': const [],
          'defeated': false,
        }).initMod,
        0);
  });

  test('rollInitiativeForAll adds initMod to unset rolls + breaks ties by mod',
      () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(encounterProvider.notifier);
    await c.read(encounterProvider.future);
    await n.addCombatant(const Combatant(
        id: 'lo', name: 'Lo', initiative: 0, initMod: 0,
        track: CharTrack(label: 'HP', current: 5, max: 5)));
    await n.addCombatant(const Combatant(
        id: 'hi', name: 'Hi', initiative: 0, initMod: 10,
        track: CharTrack(label: 'HP', current: 5, max: 5)));
    await n.rollInitiativeForAll(dice: Dice(Random(1)));
    final s = await c.read(encounterProvider.future);
    expect(s.combatants.first.id, 'hi'); // +10 mod wins
    expect(s.combatants.firstWhere((x) => x.id == 'hi').initiative,
        greaterThanOrEqualTo(11));
  });

  test('rollInitiativeForAll tie-break: equal final initiative, higher mod first',
      () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(encounterProvider.notifier);
    await c.read(encounterProvider.future);
    await n.addCombatant(
        const Combatant(id: 'x', name: 'X', initiative: 12, initMod: 1));
    await n.addCombatant(
        const Combatant(id: 'y', name: 'Y', initiative: 12, initMod: 5));
    await n.rollInitiativeForAll(dice: Dice(Random(1)));
    final s = await c.read(encounterProvider.future);
    expect(s.combatants.first.id, 'y');
  });
}
