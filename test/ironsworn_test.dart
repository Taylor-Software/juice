import 'package:flutter_test/flutter_test.dart';

import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/ironsworn.dart';

void main() {
  group('Action roll', () {
    test('outcome ladder and match flag behave statistically', () {
      final iron = Ironsworn(Dice());
      var strong = 0, weak = 0, miss = 0, matches = 0;
      const n = 30000;
      for (var i = 0; i < n; i++) {
        final r = iron.actionRoll(stat: 2, adds: 1);
        switch (r.outcome) {
          case 'Strong Hit':
            strong++;
          case 'Weak Hit':
            weak++;
          default:
            miss++;
        }
        if (r.match) matches++;
        expect(r.total, r.actionDie + 3);
        expect(r.actionDie, inInclusiveRange(1, 6));
      }
      // Exact probabilities for 1d6+3 vs 2d10 (enumerated over 600 outcomes):
      // strong 0.3317, weak 0.4367, miss 0.2317; match = 1/10.
      // (Plan comment stated 0.2517/0.3683/0.3800 — those were incorrect;
      // corrected here by exhaustive enumeration.)
      expect(strong / n, closeTo(0.3317, 0.02));
      expect(weak / n, closeTo(0.4367, 0.02));
      expect(miss / n, closeTo(0.2317, 0.02));
      expect(matches / n, closeTo(0.10, 0.01));
    });

    test('progress roll uses the score directly', () {
      final iron = Ironsworn(Dice());
      var strong = 0;
      const n = 20000;
      for (var i = 0; i < n; i++) {
        if (iron.progressRoll(score: 10).outcome == 'Strong Hit') strong++;
      }
      // 10 beats any challenge die except a 10: P(both < 10) = 0.81
      expect(strong / n, closeTo(0.81, 0.02));
    });

    test('oracle roll picks the matching row', () {
      final iron = Ironsworn(Dice());
      const rows = [
        [1, 50, 'low'],
        [51, 100, 'high'],
      ];
      for (var i = 0; i < 500; i++) {
        final r = iron.oracleRoll(rows);
        expect(r.text, r.roll <= 50 ? 'low' : 'high');
      }
    });
  });
}
