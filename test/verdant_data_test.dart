import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/verdant_data.dart';

void main() {
  final data = VerdantData(
      jsonDecode(File('assets/verdant_data.json').readAsStringSync())
          as Map<String, dynamic>);

  test('tables load with expected sizes and shapes', () {
    expect(data.tasks.length, 12);
    expect(data.terrain.length, 10);
    expect(data.traits.length, 12);
    expect(data.pointsOfInterest.length, 12);
    expect(data.quickEncounters.length, 10);
    expect(data.transportModes.length, 3);
    expect(data.terrainFeatures.length, 3);
  });

  test('constants expose ER + safety modifiers + watches', () {
    expect(data.erBase, 4);
    expect(data.safer, 2);
    expect(data.riskier, -1);
    expect(data.deadly, -2);
    expect(data.paceSlow, 2);
    expect(data.paceFast, -2);
    expect(
        data.watches.map((w) => w.night).toList(), [false, false, true, true]);
  });

  test('terrain trait keys resolve to trait names', () {
    final forest = data.terrain.firstWhere((t) => t.key == 'forest');
    expect(forest.traits, contains('foliage'));
    expect(data.traitName('foliage'), 'Foliage');
  });
}
