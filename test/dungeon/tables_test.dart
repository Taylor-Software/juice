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
    expect(t.raw['B4'], isA<Map>()); // dict tables reachable via raw
  });
}
