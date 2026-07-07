import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/dungeon/treasure.dart';

void main() {
  const h8 = {
    'form_d4': ['Coins', 'Coins', 'D6 items', 'D4 gems'],
    'd10_plus_level': [
      'D6 SP',
      '2D6 SP',
      'D6 GP',
      'D6*5 GP',
      'D6*10 GP',
      '2D6*10 GP',
      'D6*25 GP',
      '2D6*25 GP',
      'D6*50 GP',
      'Artifact +1 & 2D6*50 GP',
      'D6*100 GP',
      'Artifact +1 & D6*100 GP',
      '2D6*100 GP',
      'Artifact +2 & D6*250 GP',
      'D6*250 GP',
      'Artifact +2 & D6*500 GP',
      '2D6*1000 GP',
      'Artifact +3 & D6*5000 GP',
    ],
  };

  test('resolves dice notation to an amount, row picked by d10+depth-1+bonus',
      () {
    final r = rollTreasure(h8, depth: 1, bonus: 0, dice: Dice(Random(1)));
    expect(r, matches(RegExp(r'Treasure: \d+ (GP|SP)')));
  });

  test('bonus shifts the row and the index clamps to the table', () {
    final r = rollTreasure(h8, depth: 9, bonus: 30, dice: Dice(Random(2)));
    expect(r, contains('Artifact +3'));
  });

  test('deterministic under a fixed seed', () {
    final a = rollTreasure(h8, depth: 2, bonus: 0, dice: Dice(Random(5)));
    final b = rollTreasure(h8, depth: 2, bonus: 0, dice: Dice(Random(5)));
    expect(a, b);
  });

  test('unparseable row falls back to the raw text', () {
    const weird = {
      'form_d4': ['Coins', 'Coins', 'Coins', 'Coins'],
      'd10_plus_level': ['A mysterious boon'],
    };
    final r = rollTreasure(weird, depth: 1, bonus: 0, dice: Dice(Random(1)));
    expect(r, contains('A mysterious boon'));
  });

  test('empty table degrades to a plain label', () {
    expect(rollTreasure(const {}, depth: 1, bonus: 0, dice: Dice(Random(1))),
        'Treasure');
  });
}
