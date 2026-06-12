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

  test('bandFor maps 4-6 obvious, 2-3 option, 1 odd', () {
    expect(bandFor(1), TripleOBand.odd);
    expect(bandFor(2), TripleOBand.option);
    expect(bandFor(3), TripleOBand.option);
    expect(bandFor(4), TripleOBand.obvious);
    expect(bandFor(5), TripleOBand.obvious);
    expect(bandFor(6), TripleOBand.obvious);
  });

  test('band labels carry the zine article', () {
    expect(TripleOBand.obvious.label, 'The Obvious');
    expect(TripleOBand.option.label, 'The Option');
    expect(TripleOBand.odd.label, 'The Odd');
  });

  test('rollTripleO is a single die with a decided band', () {
    final r = rollTripleO(Dice(Random(7))); // first d6 = 5
    expect(r.die, 5);
    expect(r.dice, isNull);
    expect(r.isDoubles, isFalse);
    expect(r.band, TripleOBand.obvious);
  });

  test('rollDoubleDown rolls both dice and decides no band', () {
    final r = rollDoubleDown(Dice(Random(5))); // rolls 5, 1
    expect(r.die, isNull);
    expect(r.dice, (5, 1));
    expect(r.band, isNull, reason: 'the player picks the favorite die');
    expect(r.isDoubles, isFalse);
  });

  test('double-down doubles are flagged for trait growth', () {
    expect(rollDoubleDown(Dice(Random(2))).isDoubles, isTrue); // rolls 4, 4
    final dice = Dice(Random(11));
    var seenDoubles = false, seenDistinct = false;
    for (var i = 0; i < 200; i++) {
      final r = rollDoubleDown(dice);
      expect(r.isDoubles, r.dice!.$1 == r.dice!.$2);
      r.isDoubles ? seenDoubles = true : seenDistinct = true;
    }
    expect(seenDoubles, isTrue);
    expect(seenDistinct, isTrue);
  });

  test('assignOrder ranks courses highest→obvious; ties keep list order', () {
    expect(assignOrder([1, 2, 3]), [2, 1, 0]);
    expect(assignOrder([6, 5, 4]), [0, 1, 2]);
    expect(assignOrder([4, 4, 2]), [0, 1, 2]); // tie: earlier keeps obvious
    expect(assignOrder([2, 5, 5]), [1, 2, 0]); // tie: earlier keeps obvious
    expect(assignOrder([3, 3, 3]), [0, 1, 2]); // triple tie: list order
  });

  test('assignCourses orders courses by three d6, ties deterministic', () {
    // Seed 0 rolls [4, 6, 5]: course 1 highest, then 2, then 0.
    expect(assignCourses(Dice(Random(0))), [1, 2, 0]);
    // Seed 2 rolls [4, 4, 5]: 5 takes obvious; the tied 4s keep list order.
    expect(assignCourses(Dice(Random(2))), [2, 0, 1]);
    // Seed 4 rolls [1, 4, 4]: tied 4s take obvious/option in list order.
    expect(assignCourses(Dice(Random(4))), [1, 2, 0]);
    for (var s = 0; s < 30; s++) {
      expect(assignCourses(Dice(Random(s)))..sort(), [0, 1, 2],
          reason: 'seed $s must yield a permutation of 0-2');
    }
  });
}
