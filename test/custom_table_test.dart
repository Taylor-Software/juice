import 'dart:convert';
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
          id: 'w',
          name: 'W',
          mode: TableRoll.weighted,
          rows: [CustomRow('Rain', weight: 3), CustomRow('Sun')]);
      final back = CustomTable.fromJson(t.toJson());
      expect(back.rows.first.weight, 3);
      expect(back.rows[1].weight, 1);
    });

    test('legacy string rows still load (back-compat)', () {
      final t = CustomTable.maybeFromJson({
        'id': 'a',
        'name': 'n',
        'rows': ['Rain', 'Sun']
      });
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
        'rows': [
          'ok',
          3,
          null,
          {'t': 'fine', 'w': 2}
        ],
      });
      expect(t, isNotNull);
      expect(t!.rows.map((r) => r.text).toList(), ['ok', 'fine']);
      expect(t.rows[1].weight, 2);
    });
  });

  group('library metadata', () {
    test('genre/category/source round-trip and are omitted when empty', () {
      const t = CustomTable(
          id: 'x',
          name: 'Tavern Patrons',
          genre: 'Fantasy',
          category: 'Characters & NPCs',
          source: 'Homebrew binder');
      final j = t.toJson();
      expect(j['genre'], 'Fantasy');
      expect(j['cat'], 'Characters & NPCs');
      expect(j['src'], 'Homebrew binder');
      final back = CustomTable.fromJson(j);
      expect(back.genre, 'Fantasy');
      expect(back.category, 'Characters & NPCs');
      expect(back.source, 'Homebrew binder');

      const bare = CustomTable(id: 'y', name: 'Plain');
      expect(bare.toJson().containsKey('genre'), isFalse);
      expect(bare.toJson().containsKey('cat'), isFalse);
      expect(bare.toJson().containsKey('src'), isFalse);
      expect(CustomTable.fromJson(bare.toJson()).category, '');
    });

    test('pack round-trip carries the metadata', () {
      const t = CustomTable(
          id: 'x', name: 'N', genre: 'Horror', category: 'Names', source: 'S');
      final back = decodeTablePack(encodeTablePack(const [t])).single;
      expect(back.genre, 'Horror');
      expect(back.category, 'Names');
      expect(back.source, 'S');
    });

    test('groupTablesByCategory orders known, unknown, uncategorized', () {
      const tables = [
        CustomTable(id: '1', name: 'a'), // uncategorized
        CustomTable(id: '2', name: 'b', category: 'Names'),
        CustomTable(id: '3', name: 'c', category: 'Zeppelin Parts'),
        CustomTable(id: '4', name: 'd', category: 'Characters & NPCs'),
        CustomTable(id: '5', name: 'e', category: 'Names'),
      ];
      final groups = groupTablesByCategory(tables);
      expect([for (final (c, _) in groups) c],
          ['Characters & NPCs', 'Names', 'Zeppelin Parts', kUncategorized]);
      expect(groups[1].$2.map((t) => t.id), ['2', '5']);
    });

    test('tableGenres is sorted + unique + skips blanks', () {
      const tables = [
        CustomTable(id: '1', name: 'a', genre: 'Horror'),
        CustomTable(id: '2', name: 'b', genre: 'Fantasy'),
        CustomTable(id: '3', name: 'c', genre: 'Horror'),
        CustomTable(id: '4', name: 'd'),
      ];
      expect(tableGenres(tables), ['Fantasy', 'Horror']);
    });

    test('matchesTableQuery searches name/genre/category/source', () {
      const t = CustomTable(
          id: 'x',
          name: 'Tavern Patrons',
          genre: 'Fantasy',
          category: 'Characters & NPCs',
          source: 'Big Book of Bars');
      expect(matchesTableQuery(t, 'tavern'), isTrue);
      expect(matchesTableQuery(t, 'FANTASY'), isTrue);
      expect(matchesTableQuery(t, 'npc'), isTrue);
      expect(matchesTableQuery(t, 'book of bars'), isTrue);
      expect(matchesTableQuery(t, ''), isTrue);
      expect(matchesTableQuery(t, 'spaceship'), isFalse);
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
    test('parses fate dice and modifier (2dF+2)', () {
      final n = parseDiceNotation('2dF+2')!;
      expect([n.fate, n.count, n.mod], [true, 2, 2]);
      final plain = parseDiceNotation('2d6+1')!;
      expect([plain.fate, plain.mod], [false, 1]);
    });
    test('rollNotation rolls fate faces (-1/0/+1) plus the modifier', () {
      // dN(3) faces: value%3+1 -> 1,2,3 map to fate -1,0,+1.
      final d = Dice(_SeqRandom([2, 0])); // dN(3) -> 3 (+1), then 1 (-1)
      // 2dF+2: (+1) + (-1) + 2 = 2
      expect(rollNotation(const DiceNotation(2, 0, mod: 2, fate: true), d), 2);
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
          id: 't',
          name: 'W',
          mode: TableRoll.weighted,
          rows: [CustomRow('Rare', weight: 1), CustomRow('Common', weight: 9)]);
      // total = 10; dN(10): nextInt(10) -> value, +1. value 4 -> hit 5 -> Common.
      final g = rollCustomTable(t, Dice(_SeqRandom([4])));
      expect(g.rolls.single.value, 'Common');
      expect(g.rolls.single.detail, 'd10 → 5');
    });

    test('weighted: empty-text row reads as (no result)', () {
      const t = CustomTable(
          id: 't',
          name: 'W',
          mode: TableRoll.weighted,
          rows: [CustomRow('', weight: 1)]);
      final g = rollCustomTable(t, Dice(_SeqRandom([0]))); // hit 1
      expect(g.rolls.single.value, '(no result)');
    });

    test('ranges: matches the row whose span contains the roll', () {
      const t = CustomTable(
        id: 't',
        name: 'R',
        mode: TableRoll.ranges,
        dice: 'd100',
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
        id: 't',
        name: 'R',
        mode: TableRoll.ranges,
        dice: 'd100',
        rows: [CustomRow('Only', min: 1, max: 10)],
      );
      final g = rollCustomTable(t, Dice(_SeqRandom([74]))); // -> 75, no match
      expect(g.rolls.single.value, '(no result)');
      expect(g.rolls.single.detail, 'd100 → 75');
    });

    test('ranges: blank/garbage dice falls back to d100', () {
      const t = CustomTable(
        id: 't',
        name: 'R',
        mode: TableRoll.ranges,
        dice: '',
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
      final rows = parseRows('01-05 Rusty Flagon\n6 Sly Fox', TableRoll.ranges);
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

  group('table pack', () {
    test('round-trips a multi-table pack (uniform + weighted + ranges)', () {
      const tables = [
        CustomTable(
            id: 'u',
            name: 'Weather',
            rows: [CustomRow('Rain'), CustomRow('Sun')]),
        CustomTable(
            id: 'w',
            name: 'Storms',
            mode: TableRoll.weighted,
            rows: [CustomRow('Calm', weight: 1), CustomRow('Gale', weight: 4)]),
        CustomTable(
          id: 'r',
          name: 'Loot',
          mode: TableRoll.ranges,
          dice: 'd100',
          rows: [
            CustomRow('Copper', min: 1, max: 50),
            CustomRow('Gold', min: 51, max: 100),
          ],
        ),
      ];
      final back = decodeTablePack(encodeTablePack(tables));
      expect(back, hasLength(3));

      expect(back[0].name, 'Weather');
      expect(back[0].mode, TableRoll.uniform);
      expect(back[0].rows.map((r) => r.text).toList(), ['Rain', 'Sun']);

      expect(back[1].name, 'Storms');
      expect(back[1].mode, TableRoll.weighted);
      expect(back[1].rows[1].weight, 4);

      expect(back[2].name, 'Loot');
      expect(back[2].mode, TableRoll.ranges);
      expect(back[2].dice, 'd100');
      expect(back[2].rows.first.min, 1);
      expect(back[2].rows.first.max, 50);
      expect(back[2].rows[1].min, 51);
      expect(back[2].rows[1].max, 100);
    });

    test('a bare non-pack list decodes to []', () {
      expect(decodeTablePack('[]'), isEmpty);
      expect(decodeTablePack('[{"id":"a","name":"n","rows":["X"]}]'), isEmpty);
    });

    test('wrong kind decodes to []', () {
      expect(decodeTablePack('{"kind":"something-else","v":1,"tables":[]}'),
          isEmpty);
    });

    test('a junk table entry is dropped, valid ones kept', () {
      const valid = CustomTable(id: 'a', name: 'A', rows: [CustomRow('X')]);
      final raw = jsonEncode({
        'kind': kTablePackKind,
        'v': 1,
        'tables': [42, valid.toJson()],
      });
      final back = decodeTablePack(raw);
      expect(back, hasLength(1));
      expect(back.single.name, 'A');
    });

    test('unparseable top-level JSON throws FormatException', () {
      expect(() => decodeTablePack('not json'), throwsFormatException);
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
