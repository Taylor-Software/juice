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

  test('rollInitiativeForAll is a no-op on empty + resorts when all typed',
      () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(encounterProvider.notifier);
    await c.read(encounterProvider.future);
    await n.rollInitiativeForAll(dice: Dice(Random(1))); // empty: no throw
    expect((await c.read(encounterProvider.future)).combatants, isEmpty);
  });
}
