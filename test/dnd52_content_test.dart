import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/spell.dart';

/// JSON-shape checks over the merged D&D content assets (5.1 + 5.2). Reads the
/// asset files straight off disk and parses via the same tolerant factories the
/// providers use — no rootBundle, no widget pump.
List<T> _load<T>(String path, T? Function(dynamic) parse) {
  final raw = File(path).readAsStringSync();
  final list = jsonDecode(raw) as List;
  return list.map(parse).whereType<T>().toList();
}

void main() {
  final spells =
      _load('assets/spells_dnd.json', SpellEntry.maybeFromJson);
  final monsters = _load('assets/foes_dnd.json', Creature.maybeFromJson);

  test('both editions present in spells + monsters', () {
    final spellEds = spells.map((s) => s.edition).toSet();
    final foeEds = monsters.map((m) => m.edition).toSet();
    expect(spellEds, containsAll(['5.1', '5.2']));
    expect(foeEds, containsAll(['5.1', '5.2']));
    expect(spells.where((s) => s.edition == '5.2').length,
        greaterThanOrEqualTo(250));
    expect(monsters.where((m) => m.edition == '5.2').length,
        greaterThanOrEqualTo(200));
  });

  test('all ids unique across each merged file', () {
    final spellIds = spells.map((s) => s.id).toList();
    final foeIds = monsters.map((m) => m.id).toList();
    expect(spellIds.toSet().length, spellIds.length);
    expect(foeIds.toSet().length, foeIds.length);
  });

  test('every 5.2 id is dnd-2024- prefixed', () {
    for (final s in spells.where((s) => s.edition == '5.2')) {
      expect(s.id, startsWith('dnd-2024-'));
    }
    for (final m in monsters.where((m) => m.edition == '5.2')) {
      expect(m.id, startsWith('dnd-2024-'));
    }
  });

  test('known 5.2 spell (Fireball) parses with sane fields', () {
    final fb = spells.firstWhere((s) => s.id == 'dnd-2024-fireball');
    expect(fb.edition, '5.2');
    expect(fb.name, 'Fireball');
    expect(fb.level, 3);
    expect(fb.school, 'Evocation');
    expect(fb.description, isNotEmpty);
    expect(fb.classes, contains('Wizard'));
    expect(fb.higherLevels, isNotNull);
  });

  test('known 5.2 monster (Aboleth) parses with sane fields', () {
    final ab = monsters.firstWhere((m) => m.id == 'dnd-2024-aboleth');
    expect(ab.edition, '5.2');
    expect(ab.maxHp, greaterThan(0));
    final sb = ab.statBlock;
    expect(sb.ac, greaterThan(0));
    expect(sb.cr, '10');
    expect(sb.size, 'Large');
    expect(sb.abilities?.keys,
        containsAll(['STR', 'DEX', 'CON', 'INT', 'WIS', 'CHA']));
    expect(sb.attacks, isNotEmpty);
    expect(sb.traits, isNotEmpty);
  });

  test('every spell has a valid level and non-empty name/description', () {
    for (final s in spells) {
      expect(s.level, inInclusiveRange(0, 9), reason: s.id);
      expect(s.name, isNotEmpty, reason: s.id);
      expect(s.description, isNotEmpty, reason: s.id);
    }
  });

  test('every monster has 6 ability keys, a name, and positive maxHp', () {
    for (final m in monsters) {
      expect(m.name, isNotEmpty, reason: m.id);
      expect(m.maxHp, greaterThan(0), reason: m.id);
      expect(m.statBlock.abilities?.length, 6, reason: m.id);
    }
  });
}
