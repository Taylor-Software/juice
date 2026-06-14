import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/dice_notation.dart';

void main() {
  test('parses and normalizes exploding notation (! leading or trailing)', () {
    expect(parseDice('2d6!').normalized, '2d6!');
    expect(parseDice('5d10!kh2').normalized, '5d10kh2!');
    expect(parseDice('5d10kh2!').normalized, '5d10kh2!');
    expect(parseDice('d20!').normalized, 'd20!');
    // Regression: existing forms unchanged.
    expect(parseDice('4d6kh3').normalized, '4d6kh3');
    expect(parseDice('d20adv').normalized, '2d20kh1');
  });

  test('exploding expands the pool when dice hit max', () {
    // 100d6! almost surely rolls at least one 6, so the pool grows past 100.
    final r = parseDice('100d6!').roll(Dice(Random(7)));
    expect(r.groups.single.dice.length, greaterThan(100));
    // No keep -> total is the sum of every die, each in 1..6.
    final sum = r.groups.single.dice.fold<int>(0, (a, d) => a + d.value);
    expect(r.total, sum);
    expect(r.groups.single.dice.every((d) => d.value >= 1 && d.value <= 6),
        isTrue);
  });

  test('explode runs before keep: keep applies to the expanded pool', () {
    final r = parseDice('20d6!kh3').roll(Dice(Random(3)));
    expect(r.groups.single.dice.where((d) => d.kept).length, 3);
    expect(r.groups.single.dice.length, greaterThanOrEqualTo(20));
  });

  test('fate dice do not explode (trailing ! is rejected)', () {
    expect(() => parseDice('4dF!'), throwsFormatException);
  });
}
