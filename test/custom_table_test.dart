import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/custom_table.dart';
import 'package:juice_oracle/engine/dice.dart';

void main() {
  group('CustomTable JSON', () {
    test('round-trips id/name/mode/dice/rows', () {
      const t = CustomTable(
        id: 't1',
        name: 'Tavern Names',
        mode: TableRoll.ranges,
        dice: 'd100',
        rows: [
          CustomRow('The Rusty Flagon', min: 1, max: 50),
          CustomRow('The Sly Fox', min: 51, max: 100),
        ],
      );
      final back = CustomTable.fromJson(t.toJson());
      expect(back.id, 't1');
      expect(back.name, 'Tavern Names');
      expect(back.mode, TableRoll.ranges);
      expect(back.dice, 'd100');
      expect(back.rows.map((r) => r.text).toList(),
          ['The Rusty Flagon', 'The Sly Fox']);
      expect(back.rows.first.min, 1);
      expect(back.rows.first.max, 50);
    });

    test('weighted row round-trips weight', () {
      const t = CustomTable(
          id: 'w', name: 'W', mode: TableRoll.weighted,
          rows: [CustomRow('Rain', weight: 3), CustomRow('Sun')]);
      final back = CustomTable.fromJson(t.toJson());
      expect(back.rows.first.weight, 3);
      expect(back.rows[1].weight, 1);
    });

    test('legacy string rows still load (back-compat)', () {
      final t = CustomTable.maybeFromJson(
          {'id': 'a', 'name': 'n', 'rows': ['Rain', 'Sun']});
      expect(t, isNotNull);
      expect(t!.mode, TableRoll.uniform);
      expect(t.rows.map((r) => r.text).toList(), ['Rain', 'Sun']);
      expect(t.rows.first.weight, 1);
    });

    test('maybeFromJson returns null on malformed input', () {
      expect(CustomTable.maybeFromJson('not a map'), isNull);
      expect(CustomTable.maybeFromJson({'name': 'x'}), isNull); // missing id
    });

    test('maybeFromJson drops non-string/non-map rows tolerantly', () {
      final t = CustomTable.maybeFromJson({
        'id': 'a',
        'name': 'n',
        'rows': ['ok', 3, null, {'t': 'fine', 'w': 2}],
      });
      expect(t, isNotNull);
      expect(t!.rows.map((r) => r.text).toList(), ['ok', 'fine']);
      expect(t.rows[1].weight, 2);
    });
  });

  group('parseDiceNotation', () {
    test('parses d-only, count d, case/space tolerant', () {
      expect(parseDiceNotation('d6')!.count, 1);
      expect(parseDiceNotation('d6')!.sides, 6);
      expect(parseDiceNotation('2d6')!.count, 2);
      expect(parseDiceNotation(' D100 ')!.sides, 100);
      expect(parseDiceNotation('1 d 20')!.sides, 20);
    });
    test('rejects garbage and out-of-range', () {
      expect(parseDiceNotation(''), isNull);
      expect(parseDiceNotation('d'), isNull);
      expect(parseDiceNotation('hello'), isNull);
      expect(parseDiceNotation('d1'), isNull); // sides < 2
      expect(parseDiceNotation('0d6'), isNull); // count < 1
    });
    test('rollNotation sums count dice', () {
      // _SeqRandom yields nextInt -> values; dN(sides)=value%sides+1
      final d = Dice(_SeqRandom([0, 2])); // d6 -> 1, then 3
      expect(rollNotation(const DiceNotation(2, 6), d), 1 + 3);
    });
  });

  group('rollCustomTable', () {
    test('uniform: picks a row, GenResult titled by the table name', () {
      const t = CustomTable(
          id: 't',
          name: 'Weather',
          rows: [CustomRow('Rain'), CustomRow('Sun'), CustomRow('Fog')]);
      final g = rollCustomTable(t, Dice(_SeqRandom([0]))); // dN(3) -> 1
      expect(g.title, 'Weather');
      expect(g.rolls.single.value, 'Rain');
      expect(g.rolls.single.detail, 'd3 → 1');
    });

    test('empty table yields a single placeholder roll, no crash', () {
      const t = CustomTable(id: 't', name: 'Empty', rows: []);
      final g = rollCustomTable(t, Dice());
      expect(g.rolls.single.value, isNotEmpty);
    });

    test('weighted: cumulative pick lands in the heavy row', () {
      const t = CustomTable(
          id: 't', name: 'W', mode: TableRoll.weighted,
          rows: [CustomRow('Rare', weight: 1), CustomRow('Common', weight: 9)]);
      // total = 10; dN(10): nextInt(10) -> value, +1. value 4 -> hit 5 -> Common.
      final g = rollCustomTable(t, Dice(_SeqRandom([4])));
      expect(g.rolls.single.value, 'Common');
      expect(g.rolls.single.detail, 'd10 → 5');
    });

    test('weighted: empty-text row reads as (no result)', () {
      const t = CustomTable(
          id: 't', name: 'W', mode: TableRoll.weighted,
          rows: [CustomRow('', weight: 1)]);
      final g = rollCustomTable(t, Dice(_SeqRandom([0]))); // hit 1
      expect(g.rolls.single.value, '(no result)');
    });

    test('ranges: matches the row whose span contains the roll', () {
      const t = CustomTable(
        id: 't', name: 'R', mode: TableRoll.ranges, dice: 'd100',
        rows: [
          CustomRow('Low', min: 1, max: 50),
          CustomRow('High', min: 51, max: 100),
        ],
      );
      // d100: nextInt(100) -> 74, +1 -> 75 -> High.
      final g = rollCustomTable(t, Dice(_SeqRandom([74])));
      expect(g.rolls.single.value, 'High');
      expect(g.rolls.single.detail, 'd100 → 75');
    });

    test('ranges: gap (no covering span) yields (no result)', () {
      const t = CustomTable(
        id: 't', name: 'R', mode: TableRoll.ranges, dice: 'd100',
        rows: [CustomRow('Only', min: 1, max: 10)],
      );
      final g = rollCustomTable(t, Dice(_SeqRandom([74]))); // -> 75, no match
      expect(g.rolls.single.value, '(no result)');
      expect(g.rolls.single.detail, 'd100 → 75');
    });

    test('ranges: blank/garbage dice falls back to d100', () {
      const t = CustomTable(
        id: 't', name: 'R', mode: TableRoll.ranges, dice: '',
        rows: [CustomRow('Hit', min: 1, max: 100)],
      );
      final g = rollCustomTable(t, Dice(_SeqRandom([0]))); // -> 1
      expect(g.rolls.single.value, 'Hit');
      expect(g.rolls.single.detail, 'd100 → 1');
    });
  });

  group('parseRows / rowsToText', () {
    test('uniform: line per row, round-trips', () {
      final rows = parseRows('Rain\n  Sun  \n\nFog', TableRoll.uniform);
      expect(rows.map((r) => r.text).toList(), ['Rain', 'Sun', 'Fog']);
      expect(rowsToText(rows, TableRoll.uniform), 'Rain\nSun\nFog');
    });

    test('weighted: "text | weight", default 1, round-trips', () {
      final rows = parseRows('Rain | 3\nSun\nFog | x', TableRoll.weighted);
      expect(rows[0].text, 'Rain');
      expect(rows[0].weight, 3);
      expect(rows[1].weight, 1);
      expect(rows[2].text, 'Fog'); // unparseable weight -> 1
      expect(rows[2].weight, 1);
      expect(rowsToText(rows, TableRoll.weighted), 'Rain | 3\nSun\nFog');
    });

    test('ranges: "min[-max] text", round-trips', () {
      final rows =
          parseRows('01-05 Rusty Flagon\n6 Sly Fox', TableRoll.ranges);
      expect(rows[0].text, 'Rusty Flagon');
      expect(rows[0].min, 1);
      expect(rows[0].max, 5);
      expect(rows[1].min, 6);
      expect(rows[1].max, 6);
      expect(rowsToText(rows, TableRoll.ranges), '1-5 Rusty Flagon\n6 Sly Fox');
    });

    test('ranges: a line with no leading number keeps text, no span', () {
      final rows = parseRows('Plain line', TableRoll.ranges);
      expect(rows.single.text, 'Plain line');
      expect(rows.single.min, isNull);
    });
  });
}

class _SeqRandom implements Random {
  _SeqRandom(this._values);
  final List<int> _values;
  int _i = 0;
  @override
  int nextInt(int max) => _values[_i++ % _values.length] % max;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}
