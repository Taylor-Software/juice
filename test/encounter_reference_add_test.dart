import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/encounter_screen.dart';
import 'package:juice_oracle/state/providers.dart';

String _emptyEnc() => jsonEncode({'combatants': [], 'round': 1});

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<Creature> refMonsters,
}) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.encounter.v1.default': _emptyEnc(),
  });
  final container = ProviderContainer(overrides: [
    contentMonstersProvider.overrideWith((_) async => refMonsters),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: EncounterScreen())),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('Add from reference button visible when monsters non-empty',
      (tester) async {
    await _pump(tester, refMonsters: [
      const Creature(
          id: 'dnd-goblin',
          name: 'Goblin',
          maxHp: 7,
          statBlock: StatBlock(ac: 15, cr: '1/4')),
    ]);
    expect(find.byKey(const Key('add-from-reference')), findsOneWidget);
  });

  testWidgets('Add from reference button hidden when monsters empty',
      (tester) async {
    await _pump(tester, refMonsters: const []);
    expect(find.byKey(const Key('add-from-reference')), findsNothing);
  });

  testWidgets('Add from reference adds a combatant with the stat block',
      (tester) async {
    final container = await _pump(tester, refMonsters: [
      const Creature(
          id: 'dnd-goblin',
          name: 'Goblin',
          maxHp: 7,
          statBlock: StatBlock(ac: 15, cr: '1/4')),
    ]);
    await tester.tap(find.byKey(const Key('add-from-reference')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ref-monster-pick-dnd-goblin')));
    await tester.pumpAndSettle();
    expect(find.text('Goblin'), findsWidgets); // combatant row present
    final s = await container.read(encounterProvider.future);
    expect(s.combatants.single.name, 'Goblin');
    expect(s.combatants.single.track!.max, 7);
    expect(s.combatants.single.statBlock!.ac, 15);
    expect(s.combatants.single.statBlock!.cr, '1/4');
  });

  testWidgets('Search filters monsters by name', (tester) async {
    await _pump(tester, refMonsters: [
      const Creature(id: 'dnd-goblin', name: 'Goblin', maxHp: 7),
      const Creature(id: 'dnd-orc', name: 'Orc', maxHp: 15),
    ]);
    await tester.tap(find.byKey(const Key('add-from-reference')));
    await tester.pumpAndSettle();
    // Both visible initially.
    expect(find.byKey(const Key('ref-monster-pick-dnd-goblin')), findsOneWidget);
    expect(find.byKey(const Key('ref-monster-pick-dnd-orc')), findsOneWidget);
    // Type to filter.
    await tester.enterText(find.byKey(const Key('ref-monster-search')), 'gob');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ref-monster-pick-dnd-goblin')), findsOneWidget);
    expect(find.byKey(const Key('ref-monster-pick-dnd-orc')), findsNothing);
  });
}
