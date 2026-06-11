import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';

OracleData _loadData() {
  // Tests run with CWD = project root, so read the asset file directly
  // (avoids rootBundle, which needs a widget-test asset bundle).
  final raw = File('assets/oracle_data.json').readAsStringSync();
  return OracleData(jsonDecode(raw) as Map<String, dynamic>);
}

void main() {
  final data = _loadData();
  Oracle oracleWith(int seed) => Oracle(data, Dice(Random(seed)));

  group('Fate Check polarity invariants', () {
    test('non-zero primary determines yes/no under Normal', () {
      final o = oracleWith(1);
      for (var i = 0; i < 50000; i++) {
        final r = o.fateCheck(Likelihood.normal);
        if (r.primary > 0) {
          expect(r.result.contains('Yes'), isTrue,
              reason: 'primary + should be Yes-like: ${r.result}');
        } else if (r.primary < 0) {
          // -1,+1 -> "No But" still No-like under Normal; all contain "No".
          expect(r.result.contains('No'), isTrue,
              reason: 'primary - should be No-like under Normal: ${r.result}');
        }
      }
    });

    test('intensity label matches roll', () {
      final o = oracleWith(2);
      for (var i = 0; i < 1000; i++) {
        final r = o.fateCheck(Likelihood.normal);
        expect(r.intensityRoll, inInclusiveRange(1, 6));
        expect(r.intensity, data.intensity[r.intensityRoll - 1]);
      }
    });

    test('shorthand format is primary/secondary/intensity', () {
      final o = oracleWith(3);
      final r = o.fateCheck(Likelihood.normal);
      expect(r.shorthand.length, 3);
      expect('+-0'.contains(r.shorthand[0]), isTrue);
    });
  });

  group('Fate Check probabilities (from PDF design)', () {
    const n = 300000;

    double frac(Likelihood l, bool Function(FateResult) pred, int seed) {
      final o = oracleWith(seed);
      var hits = 0;
      for (var i = 0; i < n; i++) {
        if (pred(o.fateCheck(l))) hits++;
      }
      return hits / n;
    }

    bool yesLike(FateResult r) =>
        r.result.contains('Yes') || r.result == 'Favorable';

    test('Normal ~50% yes-like', () {
      expect(frac(Likelihood.normal, yesLike, 10), closeTo(0.50, 0.01));
    });

    test('Normal ~5.56% Random Event and ~5.56% Invalid Assumption', () {
      expect(frac(Likelihood.normal, (r) => r.isRandomEvent, 11),
          closeTo(0.0556, 0.006));
      expect(frac(Likelihood.normal, (r) => r.isInvalidAssumption, 12),
          closeTo(0.0556, 0.006));
    });

    test('Likely ~66.6% yes-like', () {
      expect(frac(Likelihood.likely, yesLike, 13), closeTo(0.666, 0.01));
    });

    test('Yes And ~11.1% under Normal', () {
      expect(frac(Likelihood.normal, (r) => r.result == 'Yes And', 14),
          closeTo(0.1111, 0.006));
    });
  });

  group('Dice skew', () {
    const n = 200000;
    double meanIndex(int skew, int seed) {
      final dice = Dice(Random(seed));
      var sum = 0;
      for (var i = 0; i < n; i++) {
        sum += dice.d10Index(skew: skew);
      }
      return sum / n;
    }

    test('advantage biases high, disadvantage biases low', () {
      final adv = meanIndex(1, 20);
      final none = meanIndex(0, 21);
      final dis = meanIndex(-1, 22);
      expect(adv, greaterThan(none));
      expect(none, greaterThan(dis));
      expect(none, closeTo(5.5, 0.05));
    });
  });

  group('Table data integrity', () {
    test('every d10 table has 10 entries; intensity has 6', () {
      expect(data.intensity.length, 6);
      for (final key in data.allTableKeys) {
        expect(data.table(key).length, 10, reason: '$key should have 10 rows');
      }
    });

    test('treasure has 6 categories each with 3 sub-columns of 6', () {
      expect(data.treasureCategories.length, 6);
      for (final cat in data.treasureCategories) {
        final sub = data.treasureSub(cat);
        expect(sub.length, 3);
        for (final col in sub.values) {
          expect((col as List).length, 6);
        }
      }
    });

    test('discover + name + extended tables present', () {
      expect(data.discoverVerb.length, 20);
      expect(data.discoverSubject.length, 20);
      expect(data.nameStart.length, 20);
      expect(data.ext('companion').length, 50);
      expect(data.ext('dialog_topic').length, 50);
    });
  });

  group('Composite generators produce results', () {
    final o = oracleWith(99);
    test('all generators return non-empty output', () {
      final gens = <GenResult>[
        o.newQuest(),
        o.newScene(),
        o.npc(),
        o.settlement(),
        o.wildernessStep(),
        o.dungeonRoom(),
        o.treasure(),
        o.generateName(),
        o.discoverMeaning(),
        o.immersion(),
        o.plotPoint(),
        o.extendedInfo(),
        o.companionResponse(),
      ];
      for (final g in gens) {
        expect(g.asText.trim().isNotEmpty, isTrue, reason: g.title);
      }
    });
  });
}
