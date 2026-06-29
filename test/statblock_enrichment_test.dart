import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('StatTrait round-trips', () {
    const t = StatTrait(name: 'Pack Tactics', text: 'Advantage when ally is near.');
    final back = StatTrait.fromJson(t.toJson());
    expect(back.name, 'Pack Tactics');
    expect(back.text, 'Advantage when ally is near.');
  });

  test('StatBlock carries the new optional D&D fields', () {
    const sb = StatBlock(
      ac: 17, cr: '5', creatureType: 'Dragon', size: 'Large',
      abilities: {'STR': 19, 'DEX': 10},
      traits: [StatTrait(name: 'Fire Breath', text: 'Cone of fire.')],
    );
    final back = StatBlock.maybeFromJson(sb.toJson())!;
    expect(back.cr, '5');
    expect(back.creatureType, 'Dragon');
    expect(back.size, 'Large');
    expect(back.abilities!['STR'], 19);
    expect(back.traits!.single.name, 'Fire Breath');
  });

  test('back-compat: a legacy stat block without new fields parses to null fields', () {
    final back = StatBlock.maybeFromJson({'ac': 13, 'notes': 'old'})!;
    expect(back.ac, 13);
    expect(back.cr, isNull);
    expect(back.abilities, isNull);
    expect(back.traits, isNull);
    expect(back.isEmpty, isFalse);
  });

  test('an empty enriched stat block is still isEmpty', () {
    expect(const StatBlock().isEmpty, isTrue);
  });

  test('Creature carries optional edition', () {
    final c = Creature.maybeFromJson(
        {'id': 'dnd-2024-goblin', 'name': 'Goblin', 'edition': '5.2'})!;
    expect(c.edition, '5.2');
    final legacy = Creature.maybeFromJson({'id': 'x', 'name': 'X'})!;
    expect(legacy.edition, isNull);
  });
}
