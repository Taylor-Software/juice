import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/engine/party_emulator.dart';

void main() {
  final data = EmulatorData(
      jsonDecode(File('assets/emulator_data.json').readAsStringSync())
          as Map<String, dynamic>);

  test('rollD66 reads two d6 as tens then units and reaches all 36 keys', () {
    final dice = Dice(Random(42));
    final seen = <int>{};
    for (var i = 0; i < 5000; i++) {
      final r = rollD66(dice);
      expect(r.tens, inInclusiveRange(1, 6));
      expect(r.units, inInclusiveRange(1, 6));
      expect(r.key, r.tens * 10 + r.units);
      seen.add(r.key);
    }
    expect(seen.length, 36);
  });

  test('rollD66 is deterministic under a seeded Dice', () {
    List<int> run() {
      final dice = Dice(Random(7));
      return [for (var i = 0; i < 50; i++) rollD66(dice).key];
    }

    expect(run(), run());
  });

  test('rollBehavior returns table, key, and the matching cell text', () {
    final dice = Dice(Random(1));
    for (var i = 0; i < 500; i++) {
      final r = rollBehavior(data, 'combat', dice);
      expect(r.table, 'combat');
      expect(r.text, data.d66Entry('combat', r.key));
    }
  });

  test('rollBehavior covers all 13 spark + specific tables', () {
    final dice = Dice(Random(2));
    for (final name in [...data.sparkNames, ...data.specificNames]) {
      final r = rollBehavior(data, name, dice);
      expect(r.table, name);
      expect(r.text, data.d66Entry(name, r.key));
    }
  });

  test('rollBehavior throws on an unknown table', () {
    expect(
        () => rollBehavior(data, 'nope', Dice(Random(3))), throwsArgumentError);
  });

  test('rollCombo rolls each named table in order', () {
    final results = rollCombo(data, ['action', 'focus'], Dice(Random(4)));
    expect(results, hasLength(2));
    expect(results[0].table, 'action');
    expect(results[1].table, 'focus');
    for (final r in results) {
      expect(r.text, data.d66Entry(r.table, r.key));
    }
  });

  test('rollCombo is deterministic under the same seed', () {
    List<int> run() => [
          for (final r
              in rollCombo(data, ['action', 'method'], Dice(Random(9))))
            r.key,
        ];
    expect(run(), run());
  });
}
