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
    test('every d10 table has 10 entries; intensity has 6; word d66 have 36',
        () {
      expect(data.intensity.length, 6);
      // The Word Oracle columns are d66 (36 rows), not d10.
      const d66 = {'word_action', 'word_descriptor', 'word_subject'};
      for (final key in data.allTableKeys) {
        if (d66.contains(key)) {
          expect(data.table(key).length, 36,
              reason: '$key should have 36 rows');
        } else {
          expect(data.table(key).length, 10,
              reason: '$key should have 10 rows');
        }
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

  group('Monster encounter + dialog data integrity', () {
    test('monster grid is 12 rows of 5', () {
      expect(data.monsterGrid.length, 12);
      for (final row in data.monsterGrid.values) {
        expect(row.length, 5);
      }
      expect(data.monsterEnvFormula.length, 10);
    });

    test('dialog grid is 5x5 with Fact center', () {
      expect(data.dialogGrid.length, 5);
      for (final row in data.dialogGrid) {
        expect(row.length, 5);
      }
      expect(data.dialogGrid[2][2], 'Fact');
    });
  });

  group('Monster encounter generator', () {
    test('always yields difficulty, environment, and rolls', () {
      final oracle = Oracle(data);
      for (var i = 0; i < 2000; i++) {
        final r = oracle.monsterEncounter();
        expect(r.title, 'Monster Encounter');
        expect(r.rolls, isNotEmpty);
        final labels = r.rolls.map((x) => x.label).toList();
        expect(labels, contains('Environment'));
        expect(labels, contains('Difficulty'));
      }
    });

    test('boss appears roughly 10% of the time', () {
      final oracle = Oracle(data);
      var bosses = 0;
      const n = 20000;
      for (var i = 0; i < n; i++) {
        final r = oracle.monsterEncounter();
        if (r.rolls.any((x) => x.label == 'Boss')) bosses++;
      }
      expect(bosses / n, closeTo(0.10, 0.01));
    });
  });

  group('NPC dialog walk', () {
    test('walks the grid, wraps, and ends on doubles', () {
      final oracle = Oracle(data);
      var sawEnd = false;
      var sawPast = false;
      var sawPresent = false;
      for (var i = 0; i < 2000; i++) {
        final r = oracle.npcDialog();
        if (r.summary == 'Conversation ends') {
          sawEnd = true;
          continue;
        }
        final labels = r.rolls.map((x) => x.label).toList();
        expect(labels, containsAll(['Fragment', 'Tone', 'Subject']));
        final tense = r.rolls.firstWhere((x) => x.label == 'Fragment').detail!;
        if (tense.contains('past')) sawPast = true;
        if (tense.contains('present')) sawPresent = true;
      }
      expect(sawEnd, isTrue, reason: 'doubles (10%) must end conversations');
      expect(sawPast && sawPresent, isTrue,
          reason: 'walk must reach both tense bands over 2000 beats');
    });

    test('walking off a grid edge wraps, never throws RangeError', () {
      // Regression: a −1 direction delta from row/col 0 used to yield −1
      // (Dart % keeps the dividend sign) and crash on dialogGrid[-1].
      final o = oracleWith(7);
      for (var i = 0; i < 1000; i++) {
        o.restoreDialogPos(0, 0); // force the top-left corner each beat
        o.npcDialog(); // must not throw regardless of the rolled direction
        final pos = o.dialogPos;
        expect(pos.row, inInclusiveRange(0, 4));
        expect(pos.col, inInclusiveRange(0, 4));
      }
    });
  });

  group('NPC race + occupation', () {
    final o = oracleWith(7);
    test('npc() includes Race and Occupation before the traits', () {
      final labels = o.npc().rolls.map((r) => r.label).toList();
      expect(labels, ['Race', 'Occupation', 'Personality', 'Need', 'Motive']);
    });
    test('npcTraits() is the three trait rows only', () {
      expect(o.npcTraits().rolls.map((r) => r.label).toList(),
          ['Personality', 'Need', 'Motive']);
    });
    test('npcRace and npcOccupation return from the authored d10 lists', () {
      const races = {
        'Human',
        'Elf',
        'Dwarf',
        'Halfling',
        'Gnome',
        'Half-Elf',
        'Half-Orc',
        'Orc',
        'Goblin',
        'Beastfolk'
      };
      const jobs = {
        'Merchant',
        'Guard',
        'Scholar',
        'Priest',
        'Farmer',
        'Blacksmith',
        'Innkeeper',
        'Hunter',
        'Sailor',
        'Thief'
      };
      for (var s = 0; s < 30; s++) {
        final oo = oracleWith(s);
        expect(races, contains(oo.npcRace()));
        expect(jobs, contains(oo.npcOccupation()));
      }
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
        o.wildernessTravel(const CrawlState()).result,
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

  group('Abstract icon roll', () {
    test('maps rolls onto the 10x6 icon grid assets', () {
      final oracle = Oracle(data);
      final seen = <String>{};
      for (var i = 0; i < 3000; i++) {
        final r = oracle.abstractIcon();
        expect(r.asset,
            matches(RegExp(r'^assets/abstract_icons/[0-9]_[1-6]\.png$')));
        expect(r.d10, inInclusiveRange(1, 10));
        expect(r.d6, inInclusiveRange(1, 6));
        seen.add(r.asset);
      }
      expect(seen.length, 60); // every icon reachable
    });

    test('abstractIcons rolls N independent icons in the same grid', () {
      final oracle = Oracle(data);
      for (final n in [1, 3, 5]) {
        final icons = oracle.abstractIcons(n);
        expect(icons.length, n);
        for (final r in icons) {
          expect(r.asset,
              matches(RegExp(r'^assets/abstract_icons/[0-9]_[1-6]\.png$')));
          expect(r.d10, inInclusiveRange(1, 10));
          expect(r.d6, inInclusiveRange(1, 6));
        }
      }
    });
  });

  group('Roll High oracle', () {
    test('data shape: 3 dice, 7 odds rows, 6 outcome slots each', () {
      expect(data.rollHighOdds.length, 7);
      expect(data.rollHighOutcomes.length, 6);
      for (final die in ['d100', 'd20', '2d6']) {
        final rows = data.rollHighRows(die);
        expect(rows.length, 7, reason: die);
        for (final row in rows) {
          expect(row.length, 6, reason: die);
        }
      }
    });

    test('every roll maps to exactly one outcome (mirrors Python coverage)',
        () {
      const bounds = {'d100': (1, 100), 'd20': (1, 20), '2d6': (2, 12)};
      for (final entry in bounds.entries) {
        final rows = data.rollHighRows(entry.key);
        final (lo, hi) = entry.value;
        for (final row in rows) {
          for (var v = lo; v <= hi; v++) {
            final hits =
                row.where((r) => r != null && v >= r[0] && v <= r[1]).length;
            expect(hits, 1, reason: '${entry.key} value $v');
          }
        }
      }
    });

    test('rollHigh produces only outcomes present in the row', () {
      final o = oracleWith(42);
      for (final die in ['d100', 'd20', '2d6']) {
        for (final oddsIndex in [0, 3, 6]) {
          final row = data.rollHighRows(die)[oddsIndex];
          final allowed = <String>{
            for (var i = 0; i < row.length; i++)
              if (row[i] != null) data.rollHighOutcomes[i],
          };
          for (var i = 0; i < 2000; i++) {
            final r = o.rollHigh(die, oddsIndex);
            expect(allowed, contains(r.rolls.first.value),
                reason: '$die odds $oddsIndex');
          }
        }
      }
    });

    test('extreme rows omit the impossible outcome', () {
      // Almost Certain has no "No, and"; Almost Impossible no "Yes, and".
      for (final die in ['d100', 'd20', '2d6']) {
        expect(data.rollHighRows(die)[0][5], isNull, reason: die);
        expect(data.rollHighRows(die)[6][0], isNull, reason: die);
      }
    });
  });
}
