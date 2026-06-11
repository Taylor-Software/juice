import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/dice_notation.dart';

/// Scripted dice: dN/fate pop from a fixed list.
class FakeDice extends Dice {
  FakeDice(this._values);
  final List<int> _values;
  int _i = 0;
  @override
  int dN(int n) => _values[_i++];
  @override
  int fate() => _values[_i++];
}

void main() {
  group('parser accepts', () {
    for (final input in [
      'd20', '3d6', '2d6+1d8+3', '4d6kh3', '10d10kl4', '4d6dh1', '4d6dl1',
      'd%', 'dF', '4df', 'd20adv', 'd20dis', '1d20adv',
      '2d6-1', '-d6+10', ' 2D6 + 3 ', '100d1000',
    ]) {
      test(input, () => expect(() => parseDice(input), returnsNormally));
    }
  });

  group('parser rejects with position', () {
    // Syntax errors anchor where the expected token should start; semantic
    // errors anchor at the START of the offending token.
    final cases = {
      '': 0, 'd': 1, '2d': 2, 'xd6': 0, '2d6++3': 4, 'd6kh': 4,
      '0d6': 0, '101d6': 0, 'd1': 1, 'd1001': 1,
      'd6kh2': 2, // keep > count; suffix starts at 2
      '4d6kh0': 3, '4d6dh4': 3, '2d20adv': 4, 'd6foo': 2, '2d6 3': 4,
    };
    cases.forEach((input, pos) {
      test("'$input'", () {
        expect(
          () => parseDice(input),
          throwsA(isA<FormatException>().having(
              (e) => e.message, 'message', contains('position $pos'))),
        );
      });
    });
  });

  group('evaluation', () {
    test('multi-group sum with modifier and dF', () {
      final r = parseDice('2d6+1d8+dF+3').roll(FakeDice([4, 5, 2, 1]));
      expect(r.total, 15);
      expect(r.groups.length, 4);
      expect(r.groups[0].dice.map((d) => d.value), [4, 5]);
      expect(r.groups[3].label, '+3');
    });

    test('kh keeps highest, marks dropped', () {
      final r = parseDice('4d6kh3').roll(FakeDice([1, 4, 6, 3]));
      expect(r.total, 13);
      final kept = r.groups.single.dice.where((d) => d.kept).map((d) => d.value);
      expect(kept, containsAll([4, 6, 3]));
      expect(r.groups.single.dice.where((d) => !d.kept).single.value, 1);
    });

    test('kh1 over 2d2: enumerated max', () {
      for (final pair in [[1, 1], [1, 2], [2, 1], [2, 2]]) {
        final r = parseDice('2d2kh1').roll(FakeDice(pair));
        expect(r.total, pair.reduce((a, b) => a > b ? a : b));
      }
    });

    test('kl/dh/dl semantics', () {
      expect(parseDice('2d2kl1').roll(FakeDice([1, 2])).total, 1);
      // dh1 drops the highest (5): 2 + 3 = 5.
      expect(parseDice('3d6dh1').roll(FakeDice([2, 5, 3])).total, 5);
      // dl1 drops the lowest (2): 5 + 3 = 8.
      expect(parseDice('3d6dl1').roll(FakeDice([2, 5, 3])).total, 8);
    });

    test('adv/dis desugar', () {
      expect(parseDice('d20adv').normalized, '2d20kh1');
      expect(parseDice('d20adv').roll(FakeDice([7, 15])).total, 15);
      expect(parseDice('d20dis').roll(FakeDice([7, 15])).total, 7);
    });

    test('negative groups subtract', () {
      final r = parseDice('d20-2d4').roll(FakeDice([18, 1, 2]));
      expect(r.total, 15);
      expect(r.groups[1].sign, -1);
    });

    test('asText journal rendering', () {
      final r = parseDice('4d6kh3+2').roll(FakeDice([1, 4, 6, 3]));
      expect(r.asText, contains('4d6kh3+2 = 15'));
      expect(r.asText, contains('[1]'));
    });

    test('d% rolls 1..100 and dF dice sum in range', () {
      final rng = Dice(Random(7));
      for (var i = 0; i < 2000; i++) {
        expect(parseDice('d%').roll(rng).total, inInclusiveRange(1, 100));
        expect(parseDice('4dF').roll(rng).total, inInclusiveRange(-4, 4));
      }
    });

    test('3d6 distribution sanity (mean ~10.5)', () {
      final rng = Dice(Random(11));
      var sum = 0;
      const n = 20000;
      for (var i = 0; i < n; i++) {
        sum += parseDice('3d6').roll(rng).total;
      }
      expect(sum / n, closeTo(10.5, 0.1));
    });
  });
}
