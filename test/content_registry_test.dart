import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/spell.dart';
import 'package:juice_oracle/engine/content_registry.dart';

void main() {
  final monsters = [
    const Creature(id: 'dnd-goblin', name: 'Goblin', edition: '5.1'),
    const Creature(id: 'cairn-wolf', name: 'Wolf'),
  ];
  final spells = [
    const SpellEntry(id: 'dnd-fireball', system: 'dnd', name: 'Fireball', level: 3),
    const SpellEntry(id: 'dnd-fire-bolt', system: 'dnd', name: 'Fire Bolt', level: 0),
  ];

  test('empty query returns everything (type=all)', () {
    final r = searchContent(
        query: '', filter: ContentType.all, monsters: monsters, spells: spells);
    expect(r.monsters.length, 2);
    expect(r.spells.length, 2);
  });

  test('query matches name case-insensitively', () {
    final r = searchContent(
        query: 'fire', filter: ContentType.all, monsters: monsters, spells: spells);
    expect(r.monsters, isEmpty);
    expect(r.spells.map((s) => s.name), containsAll(['Fireball', 'Fire Bolt']));
  });

  test('type filter narrows to monsters only', () {
    final r = searchContent(
        query: '', filter: ContentType.monsters, monsters: monsters, spells: spells);
    expect(r.monsters.length, 2);
    expect(r.spells, isEmpty);
  });

  test('foeEntryToCreature maps rank to hp and folds tactics/features into notes', () {
    final c = foeEntryToCreature(const FoeEntry(
      id: 'is-haunt', name: 'Haunt', rank: 3, nature: 'Horror',
      features: ['Cold spot'], drives: [], tactics: ['Ambush'],
    ));
    expect(c.maxHp, 30);
    expect(c.name, 'Haunt');
    expect(c.statBlock.notes, contains('Ambush'));
    expect(c.statBlock.notes, contains('Cold spot'));
  });

  test('attribution map carries the D&D SRD line', () {
    expect(kContentAttributions['dnd'], contains('System Reference Document'));
  });

  test('argosa + knave attributions are registered', () {
    expect(kContentAttributions['argosa'], contains('Argosa'));
    expect(kContentAttributions['knave'], contains('Knave'));
  });

  test('dcc attribution is registered', () {
    expect(kContentAttributions['dcc'], contains('Open Game License'));
  });
}
