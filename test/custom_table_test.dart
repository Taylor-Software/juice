import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/custom_table.dart';
import 'package:juice_oracle/engine/dice.dart';

void main() {
  group('CustomTable JSON', () {
    test('round-trips id/name/rows', () {
      const t = CustomTable(
          id: 't1',
          name: 'Tavern Names',
          rows: ['The Rusty Flagon', 'The Sly Fox']);
      final back = CustomTable.fromJson(t.toJson());
      expect(back.id, 't1');
      expect(back.name, 'Tavern Names');
      expect(back.rows, ['The Rusty Flagon', 'The Sly Fox']);
    });

    test('maybeFromJson returns null on malformed input', () {
      expect(CustomTable.maybeFromJson('not a map'), isNull);
      expect(CustomTable.maybeFromJson({'name': 'x'}), isNull); // missing id
    });

    test('maybeFromJson drops non-string rows tolerantly', () {
      final t = CustomTable.maybeFromJson(
          {'id': 'a', 'name': 'n', 'rows': ['ok', 3, null, 'fine']});
      expect(t, isNotNull);
      expect(t!.rows, ['ok', 'fine']);
    });
  });

  group('rollCustomTable', () {
    test('picks a row and returns a GenResult titled by the table name', () {
      const t =
          CustomTable(id: 't', name: 'Weather', rows: ['Rain', 'Sun', 'Fog']);
      final g = rollCustomTable(t, Dice(_SeqRandom([0]))); // dN(3) -> 1 -> idx 0
      expect(g.title, 'Weather');
      expect(g.rolls, hasLength(1));
      expect(g.rolls.first.value, 'Rain');
      expect(g.rolls.first.detail, 'd3 → 1');
    });

    test('empty table yields a single placeholder roll, no crash', () {
      const t = CustomTable(id: 't', name: 'Empty', rows: []);
      final g = rollCustomTable(t, Dice());
      expect(g.rolls, hasLength(1));
      expect(g.rolls.first.value, isNotEmpty);
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
