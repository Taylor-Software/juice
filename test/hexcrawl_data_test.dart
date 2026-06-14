import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';

void main() {
  final data = HexcrawlData(
      jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
          as Map<String, dynamic>);

  test('loads terrains, climate map, neighbour map, and flat tables', () {
    expect(data.climates, containsAll(['cold', 'temperate', 'hot']));
    expect(data.terrains.length, greaterThanOrEqualTo(10));
    expect(data.terrainByKey('plains')?.name, 'Plains');
    expect(data.climateToTerrain['hot'], isNotEmpty);
    expect(data.neighbouringTerrain['forest'], isNotEmpty);
    expect(data.weather, isNotEmpty);
    expect(data.siteTypes, isNotEmpty);
    expect(data.encounterCategories, contains('Nothing of note'));
    expect(data.dungeonRoomTypes, contains('Vault'));
    expect(data.dungeonContents, contains('Treasure'));
    expect(data.dungeonDressing, isNotEmpty);
    expect(data.localFeatures, isNotEmpty);
  });

  test('every weighted row references a defined terrain', () {
    final keys = data.terrains.map((t) => t.key).toSet();
    for (final rows in data.climateToTerrain.values) {
      for (final r in rows) {
        expect(keys, contains(r.terrain));
      }
    }
    for (final rows in data.neighbouringTerrain.values) {
      for (final r in rows) {
        expect(keys, contains(r.terrain));
      }
    }
  });
}
