import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dungeon/tables.dart';

void main() {
  test('parses shipped dungeon_data.json', () {
    final raw = File('assets/dungeon_data.json').readAsStringSync();
    final t = DungeonTables.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    expect(t.a1.length, 12);
    expect(t.a2['7']!.name, 'Ruins');
    expect(t.reaction['2'], 'Immediate ambush');
    expect(t.corridorFamilies.keys, contains('straight'));
    expect(t.factionNames, isNotEmpty);
    expect(t.upperMonsters, isNotEmpty);
    // dict tables reachable via raw
    expect(t.raw['B4'], isA<Map<String, dynamic>>());
  });

  test('parses the cave branch', () {
    final raw = File('assets/dungeon_data.json').readAsStringSync();
    final t = DungeonTables.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    expect(t.d1.length, 12);
    expect(t.d2['7']!.name, 'Natural Cave');
    expect(t.d2['10']!.tierBump, 1);
    expect(t.d2['10']!.veinBonus, 3);
    expect(t.d2['4']!.leadsToDungeon, isTrue);
    expect(t.d2['9']!.monsterDie, 20);
    expect(t.e2.length, 6);
    expect(t.f2.length, 6);
    expect(t.cavestone.length, 10);
    expect(t.tunnelFamilies.keys.toSet(), t.corridorFamilies.keys.toSet());
    expect(t.caveFamilies.keys.toSet(), t.chamberFamilies.keys.toSet());
    expect(t.a2['5']!.onStock6, contains('{ref:I6}'));
    expect(t.centralMonsters, isNotEmpty); // G3
    expect(t.deepMonsters, isNotEmpty); // G4
  });
}
