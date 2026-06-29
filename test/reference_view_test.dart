import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/spell.dart';
import 'package:juice_oracle/features/reference_view.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/sheet_widgets.dart';

void main() {
  testWidgets('SpellCard renders name, level/school, and description', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SpellCard(
          spell: SpellEntry(
            id: 'dnd-fireball', system: 'dnd', name: 'Fireball', level: 3,
            school: 'Evocation', castingTime: '1 action', range: '150 feet',
            components: 'V, S, M', duration: 'Instantaneous',
            description: 'A bright streak flashes.', concentration: false,
          ),
        ),
      ),
    ));
    expect(find.text('Fireball'), findsOneWidget);
    expect(find.textContaining('Evocation'), findsOneWidget);
    expect(find.textContaining('A bright streak'), findsOneWidget);
  });

  testWidgets('StatBlockView renders cr/type/size, abilities, and traits', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StatBlockView(
          block: StatBlock(
            ac: 17, cr: '5', creatureType: 'Dragon', size: 'Large',
            abilities: {'STR': 19, 'DEX': 10},
            traits: [StatTrait(name: 'Fire Breath', text: 'Cone of fire.')],
          ),
        ),
      ),
    ));
    expect(find.textContaining('CR 5'), findsOneWidget);
    expect(find.textContaining('Dragon'), findsOneWidget);
    expect(find.textContaining('STR 19'), findsOneWidget);
    expect(find.textContaining('Fire Breath'), findsOneWidget);
  });
}
