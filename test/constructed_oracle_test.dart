import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/constructed_oracle.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseOracleDice', () {
    test('parses d-only, count, and modifier; tolerant of case/space', () {
      expect(parseOracleDice('d100')!.sides, 100);
      expect(parseOracleDice('2d6')!.count, 2);
      final m = parseOracleDice(' 3D8+1 ')!;
      expect([m.count, m.sides, m.mod], [3, 8, 1]);
      expect(parseOracleDice('d20-2')!.mod, -2);
    });
    test('rejects garbage / out of range', () {
      expect(parseOracleDice('hello'), isNull);
      expect(parseOracleDice('0d6'), isNull);
      expect(parseOracleDice('21d6'), isNull);
      expect(parseOracleDice('d1'), isNull);
    });
    test('min/max span', () {
      final d = parseOracleDice('2d6+1')!;
      expect(d.min, 3); // 2*1 + 1
      expect(d.max, 13); // 2*6 + 1
    });
    test('fate dice parse (dF / NdF+k)', () {
      final f = parseOracleDice('dF')!;
      expect(f.fate, isTrue);
      expect([f.count, f.mod], [1, 0]);
      final g = parseOracleDice('2dF+2')!;
      expect([g.fate, g.count, g.mod], [true, 2, 2]);
      expect(g.min, 0); // -2 + 2
      expect(g.max, 4); // +2 + 2
    });
  });

  group('fate + advantage/disadvantage pmf', () {
    test('single fate die is -1/0/+1 at 1/3 each', () {
      final p = oracleDicePmf(parseOracleDice('dF')!);
      expect(p[-1], closeTo(1 / 3, 1e-9));
      expect(p[0], closeTo(1 / 3, 1e-9));
      expect(p[1], closeTo(1 / 3, 1e-9));
    });
    test('2dF+2 shifts a triangular curve into 0..4 peaking at 2', () {
      final p = oracleDicePmf(parseOracleDice('2dF+2')!);
      expect(p.keys.reduce((a, b) => a < b ? a : b), 0);
      expect(p.keys.reduce((a, b) => a > b ? a : b), 4);
      expect(p[2], closeTo(3 / 9, 1e-9)); // (-1,+1),(0,0),(+1,-1)
      expect(p.values.reduce((a, b) => a + b), closeTo(1.0, 1e-9));
    });
    test('advantage on 2d20 skews the value distribution upward vs disadv', () {
      final d = parseOracleDice('2d20')!;
      double mean(Map<int, double> p) =>
          p.entries.fold<double>(0, (a, e) => a + e.key * e.value);
      final adv = oracleDicePmf(d, RollMode.advantage);
      final dis = oracleDicePmf(d, RollMode.disadvantage);
      // Both stay within a single die's face range.
      expect(adv.keys.reduce((a, b) => a > b ? a : b), 20);
      expect(dis.keys.reduce((a, b) => a < b ? a : b), 1);
      expect(mean(adv), greaterThan(mean(dis)));
      expect(adv.values.reduce((a, b) => a + b), closeTo(1.0, 1e-9));
      expect(dis.values.reduce((a, b) => a + b), closeTo(1.0, 1e-9));
    });
    test('adv/disadv fall back to sum with a single die', () {
      final d = parseOracleDice('d6')!;
      final adv = oracleDicePmf(d, RollMode.advantage);
      final sum = oracleDicePmf(d, RollMode.sum);
      expect(adv, sum);
    });
    test('advDisAvailable + effectiveMode gate on 2+ dice', () {
      const one = ConstructedOracle(
          id: 'a', name: 'A', notation: 'd20', mode: RollMode.advantage);
      const two = ConstructedOracle(
          id: 'b', name: 'B', notation: '2d20', mode: RollMode.advantage);
      expect(one.advDisAvailable, isFalse);
      expect(one.effectiveMode, RollMode.sum);
      expect(two.advDisAvailable, isTrue);
      expect(two.effectiveMode, RollMode.advantage);
    });
  });

  group('oracleDicePmf', () {
    test('single die is uniform and sums to 1', () {
      final p = oracleDicePmf(parseOracleDice('d6')!);
      expect(p.length, 6);
      expect(p[1], closeTo(1 / 6, 1e-9));
      expect(p.values.reduce((a, b) => a + b), closeTo(1.0, 1e-9));
    });
    test('2d6 is a bell curve peaking at 7', () {
      final p = oracleDicePmf(parseOracleDice('2d6')!);
      expect(p[7], closeTo(6 / 36, 1e-9));
      expect(p[2], closeTo(1 / 36, 1e-9));
      expect(p[12], closeTo(1 / 36, 1e-9));
      expect(p.values.reduce((a, b) => a + b), closeTo(1.0, 1e-9));
    });
  });

  group('resolveOracle', () {
    test('full 6-band d100 at 50/50 covers the whole range once', () {
      const o = ConstructedOracle(id: 'x', name: 'Full', notation: 'd100');
      final ranges = resolveOracle(o, OracleLikelihood.fiftyFifty);
      expect(ranges, isNotEmpty);
      // Contiguous, non-overlapping, covers 1..100.
      final sorted = [...ranges]..sort((a, b) => a.lo.compareTo(b.lo));
      expect(sorted.first.lo, 1);
      expect(sorted.last.hi, 100);
      for (var i = 1; i < sorted.length; i++) {
        expect(sorted[i].lo, sorted[i - 1].hi + 1);
      }
      expect(
          ranges
              .map((r) => (r.probability * 100).round())
              .reduce((a, b) => a + b),
          closeTo(100, 2));
    });

    test('roll high vs roll low mirror: yes sits high vs low', () {
      const hi = ConstructedOracle(id: 'h', name: 'H', notation: 'd20');
      const lo = ConstructedOracle(
          id: 'l',
          name: 'L',
          notation: 'd20',
          direction: OracleDirection.rollLow);
      final rh = resolveOracle(hi, OracleLikelihood.fiftyFifty);
      final rl = resolveOracle(lo, OracleLikelihood.fiftyFifty);
      // Highest range is a Yes for rollHigh, a No for rollLow.
      expect(rh.first.band.isYes, isTrue);
      expect(rl.first.band.isYes, isFalse);
    });

    test('mild oracle: only 3 bands still tiles the full range', () {
      const o = ConstructedOracle(
        id: 'm',
        name: 'Mild',
        notation: 'd10',
        bands: {OutcomeBand.yesAnd, OutcomeBand.yesBut, OutcomeBand.noBut},
      );
      final ranges = resolveOracle(o, OracleLikelihood.likely);
      final present = ranges.map((r) => r.band).toSet();
      expect(
          present, {OutcomeBand.yesAnd, OutcomeBand.yesBut, OutcomeBand.noBut});
      final sorted = [...ranges]..sort((a, b) => a.lo.compareTo(b.lo));
      expect(sorted.first.lo, 1);
      expect(sorted.last.hi, 10);
    });

    test(
        'every enabled-band subset + die + likelihood covers min..max with no '
        'gaps or overlaps', () {
      final dice = ['d4', 'd6', 'd20', 'd100', '2d6', '3d8+1', '2dF+2', '4dF'];
      final subsets = <Set<OutcomeBand>>[
        OutcomeBand.values.toSet(),
        {OutcomeBand.yes, OutcomeBand.no},
        {OutcomeBand.yesAnd, OutcomeBand.yesBut, OutcomeBand.noBut},
        {OutcomeBand.yes, OutcomeBand.yesBut}, // yes-only (no-zone empty)
        {OutcomeBand.no, OutcomeBand.noAnd}, // no-only (yes-zone empty)
        {OutcomeBand.yesAnd, OutcomeBand.noAnd},
      ];
      for (final notation in dice) {
        final d = parseOracleDice(notation)!;
        for (final bands in subsets) {
          for (final l in OracleLikelihood.values) {
            for (final dir in OracleDirection.values) {
              final o = ConstructedOracle(
                  id: 'x',
                  name: 'X',
                  notation: notation,
                  bands: bands,
                  direction: dir);
              final ranges = resolveOracle(o, l);
              final sorted = [...ranges]..sort((a, b) => a.lo.compareTo(b.lo));
              final why = '$notation $bands $l $dir';
              expect(sorted, isNotEmpty, reason: why);
              expect(sorted.first.lo, d.min, reason: why);
              expect(sorted.last.hi, d.max, reason: why);
              for (var i = 1; i < sorted.length; i++) {
                expect(sorted[i].lo, sorted[i - 1].hi + 1,
                    reason: 'gap/overlap in $why');
              }
              expect(
                  ranges.map((r) => r.band).toSet().difference(bands), isEmpty,
                  reason: why);
            }
          }
        }
      }
    });

    test('likelihood shifts the yes share', () {
      const o = ConstructedOracle(id: 'x', name: 'X', notation: 'd100');
      double yesShare(OracleLikelihood l) => resolveOracle(o, l)
          .where((r) => r.band.isYes)
          .fold<double>(0, (a, r) => a + r.probability);
      expect(yesShare(OracleLikelihood.almostCertain),
          greaterThan(yesShare(OracleLikelihood.almostImpossible)));
    });
  });

  group('rollOracle', () {
    test('deterministic with a seeded Dice; band matches the range', () {
      const o = ConstructedOracle(id: 'x', name: 'Seeded', notation: 'd20');
      final dice = Dice(Random(7));
      final r = rollOracle(o, OracleLikelihood.likely, dice);
      final ranges = resolveOracle(o, OracleLikelihood.likely);
      final hit = ranges.firstWhere((x) => r.roll >= x.lo && r.roll <= x.hi);
      expect(r.band, hit.band);
      expect(r.roll, inInclusiveRange(1, 20));
    });

    test('genResult carries the answer as title/summary + rolls', () {
      const o = ConstructedOracle(id: 'x', name: 'My Oracle', notation: 'd6');
      final g = oracleGenResult(o, OracleLikelihood.likely, Dice(Random(3)));
      expect(g.title, 'My Oracle');
      expect(g.summary, isNotNull);
      expect(g.rolls.first.label, 'Answer');
      expect(g.rolls.last.value, 'Likely');
    });
  });

  group('ConstructedOracle model', () {
    test('validity needs >=2 bands and a parseable notation', () {
      expect(const ConstructedOracle(id: 'a', name: 'A').valid, isTrue);
      expect(
          const ConstructedOracle(id: 'b', name: 'B', bands: {OutcomeBand.yes})
              .valid,
          isFalse);
      expect(
          const ConstructedOracle(id: 'c', name: 'C', notation: 'junk').valid,
          isFalse);
    });

    test('round-trips through JSON incl. direction/bands/chaos', () {
      const o = ConstructedOracle(
        id: 'x',
        name: 'Grim',
        notation: '2d6',
        direction: OracleDirection.rollLow,
        bands: {OutcomeBand.yes, OutcomeBand.no, OutcomeBand.noAnd},
        chaos: 7,
      );
      final back = ConstructedOracle.fromJson(o.toJson());
      expect(back.name, 'Grim');
      expect(back.notation, '2d6');
      expect(back.direction, OracleDirection.rollLow);
      expect(back.bands, {OutcomeBand.yes, OutcomeBand.no, OutcomeBand.noAnd});
      expect(back.chaos, 7);

      const bare = ConstructedOracle(id: 'y', name: 'Y');
      expect(bare.toJson().containsKey('dir'), isFalse);
      expect(bare.toJson().containsKey('chaos'), isFalse);
    });
  });

  test('provider add/upsert/remove persist (app-global)', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(constructedOraclesProvider.notifier);
    await c.read(constructedOraclesProvider.future);

    await n.add(const ConstructedOracle(id: 'o1', name: 'One'));
    expect(c.read(constructedOraclesProvider).value!.single.name, 'One');

    await n.upsert(const ConstructedOracle(id: 'o1', name: 'One v2'));
    expect(c.read(constructedOraclesProvider).value!.single.name, 'One v2');
    await n.upsert(const ConstructedOracle(id: 'o2', name: 'Two'));
    expect(c.read(constructedOraclesProvider).value!.length, 2);

    await n.remove('o1');
    expect(c.read(constructedOraclesProvider).value!.single.id, 'o2');
  });
}
