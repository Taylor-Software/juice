import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/hexcrawl.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';

HexcrawlData _data() => HexcrawlData(
    jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  final data = _data();

  test('weightedPick respects weights and only returns table values', () {
    const table = [WeightedTerrain('a', 3), WeightedTerrain('b', 1)];
    // Deterministic across many seeds: every pick is a/b, and 'a' (weight 3)
    // wins clearly more than half.
    final picks = [
      for (var i = 0; i < 400; i++) weightedPick(table, Dice(Random(i)))
    ];
    expect(picks.every((p) => p == 'a' || p == 'b'), isTrue);
    expect(picks.where((p) => p == 'a').length, greaterThan(picks.length ~/ 2));
  });

  test('rollTerrain returns a terrain valid for the climate', () {
    for (final climate in data.climates) {
      final t = rollTerrain(data, climate, Dice(Random(7)));
      expect(t, isNotNull);
      expect(data.terrainByKey(t!.key), isNotNull);
    }
  });

  test('rollNeighbour returns a defined terrain', () {
    final t = rollNeighbour(data, 'forest', Dice(Random(3)));
    expect(t, isNotNull);
    expect(data.terrains.map((x) => x.key), contains(t!.key));
  });

  test('flat-table rolls return an option from the table', () {
    expect(data.weather, contains(rollFrom(data.weather, Dice(Random(2)))));
    expect(data.encounterCategories,
        contains(rollFrom(data.encounterCategories, Dice(Random(9)))));
  });
}
