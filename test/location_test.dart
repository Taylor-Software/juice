import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';

void main() {
  // Tests run with CWD = project root, so read the asset file directly.
  final data = OracleData(
      jsonDecode(File('assets/oracle_data.json').readAsStringSync())
          as Map<String, dynamic>);
  final oracle = Oracle(data, Dice(Random(42)));

  test('asset carries the 5x5 location grid with compass labels', () {
    expect(data.locationRows, 5);
    expect(data.locationCols, 5);
    expect(data.locationRowLabels,
        ['North', 'North', 'Center', 'South', 'South']);
    expect(data.locationColLabels, ['West', 'West', 'Center', 'East', 'East']);
  });

  test('locationFor maps d100 to grid cell and compass label', () {
    expect(oracle.locationFor(0).col, 0);
    expect(oracle.locationFor(0).row, 0);
    expect(oracle.locationFor(0).label, 'North-West');
    expect(oracle.locationFor(48).label, 'Center');
    expect(oracle.locationFor(51).label, 'Center');
    expect(oracle.locationFor(19).label, 'North-East');
    expect(oracle.locationFor(99).label, 'South-East');
    expect(oracle.locationFor(80).label, 'South-West');
    expect(oracle.locationFor(56).label, 'East');
    expect(oracle.locationFor(8).label, 'North');
  });

  test('every value 0-99 maps into the 5x5 grid exactly', () {
    final seen = <String, int>{};
    for (var n = 0; n < 100; n++) {
      final loc = oracle.locationFor(n);
      expect(loc.col, inInclusiveRange(0, 4));
      expect(loc.row, inInclusiveRange(0, 4));
      seen['${loc.col},${loc.row}'] = (seen['${loc.col},${loc.row}'] ?? 0) + 1;
    }
    expect(seen.length, 25);
    expect(seen.values.every((c) => c == 4), isTrue);
  });

  test('rollLocation rolls 1d100 read as 0-99 and carries the roll value',
      () {
    for (var i = 0; i < 2000; i++) {
      final loc = oracle.rollLocation();
      expect(loc.roll, inInclusiveRange(0, 99));
      expect(loc, equals(oracle.locationFor(loc.roll)));
    }
  });
}
