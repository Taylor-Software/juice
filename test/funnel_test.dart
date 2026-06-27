import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  group('FunnelPeasant', () {
    test('defaults: alive, not graduated, empty maps', () {
      const p = FunnelPeasant();
      expect(p.alive, true);
      expect(p.graduated, false);
      expect(p.hp, 0);
      expect(p.stats, isEmpty);
      expect(p.flavor, isEmpty);
    });
    test('copyWith replaces fields', () {
      const p = FunnelPeasant();
      final p2 = p.copyWith(
          name: 'Bob', hp: 4, alive: false, graduated: true,
          stats: {'str': 12}, flavor: {'occupation': 'Farmer'});
      expect(p2.name, 'Bob');
      expect(p2.hp, 4);
      expect(p2.alive, false);
      expect(p2.graduated, true);
      expect(p2.stats['str'], 12);
      expect(p2.flavor['occupation'], 'Farmer');
    });
    test('round-trips through json', () {
      const p = FunnelPeasant(
          name: 'Ada', hp: 3, stats: {'str': 9}, flavor: {'weapon': 'Sling'});
      final back = FunnelPeasant.fromJson(p.toJson());
      expect(back.name, 'Ada');
      expect(back.hp, 3);
      expect(back.stats['str'], 9);
      expect(back.flavor['weapon'], 'Sling');
      expect(back.alive, true);
      expect(back.graduated, false);
    });
    test('fromJson tolerates missing fields', () {
      final p = FunnelPeasant.fromJson(const {});
      expect(p.name, '');
      expect(p.hp, 0);
      expect(p.stats, isEmpty);
    });
  });

  group('FunnelSheet', () {
    test('premade has the seed system + one empty peasant', () {
      final s = FunnelSheet.premade('dcc', const [FunnelPeasant(hp: 1)]);
      expect(s.seedSystem, 'dcc');
      expect(s.peasants.length, 1);
      expect(s.peasants.first.hp, 1);
    });
    test('markGraduated flips one peasant', () {
      final s = FunnelSheet(seedSystem: 'dcc', peasants: const [
        FunnelPeasant(name: 'A'),
        FunnelPeasant(name: 'B'),
      ]);
      final s2 = s.markGraduated(1);
      expect(s2.peasants[0].graduated, false);
      expect(s2.peasants[1].graduated, true);
    });
    test('round-trips through json', () {
      final s = FunnelSheet(seedSystem: 'ose', peasants: const [
        FunnelPeasant(name: 'A', hp: 4, stats: {'str': 12}),
      ]);
      final back = FunnelSheet.maybeFromJson(s.toJson())!;
      expect(back.seedSystem, 'ose');
      expect(back.peasants.single.name, 'A');
      expect(back.peasants.single.stats['str'], 12);
    });
    test('maybeFromJson returns null for non-map', () {
      expect(FunnelSheet.maybeFromJson(null), isNull);
      expect(FunnelSheet.maybeFromJson('x'), isNull);
    });
    test('maybeFromJson defaults a missing seedSystem to empty + tolerates no peasants', () {
      final s = FunnelSheet.maybeFromJson(const {})!;
      expect(s.seedSystem, '');
      expect(s.peasants, isEmpty);
    });
  });
}
