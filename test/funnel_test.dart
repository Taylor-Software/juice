import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/funnel.dart';
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

  group('FunnelProfile registry', () {
    test('funnelProfileFor returns null for unknown', () {
      expect(funnelProfileFor('nope'), isNull);
    });
    test('dcc profile shape', () {
      final p = funnelProfileFor('dcc')!;
      expect(p.system, 'dcc');
      expect(p.statKeys.map((s) => s.key),
          containsAll(['str', 'agi', 'sta', 'per', 'int', 'lck']));
      expect(p.flavorFields.map((f) => f.key),
          containsAll(['occupation', 'weapon', 'tradeGoods']));
      expect(p.graduateChoices.map((c) => c.key),
          containsAll(['className', 'alignment']));
    });
    test('dcc seedPeasant has mid-range stats + hpMin hp', () {
      final p = funnelProfileFor('dcc')!;
      final peasant = p.seedPeasant();
      expect(peasant.stats['str'], p.statDefault);
      expect(peasant.hp, p.hpMin);
      expect(peasant.alive, true);
    });
    test('dcc graduate builds a leveled DCC hero copying stats + hp', () {
      final p = funnelProfileFor('dcc')!;
      const peasant = FunnelPeasant(
        name: 'Survivor',
        hp: 5,
        stats: {'str': 16, 'agi': 12, 'sta': 14, 'per': 9, 'int': 8, 'lck': 11},
        flavor: {'occupation': 'Blacksmith'},
      );
      final hero = p.graduate('h1', peasant, {'className': 'Warrior', 'alignment': 'Lawful'});
      expect(hero.id, 'h1');
      expect(hero.name, 'Survivor');
      expect(hero.dcc, isNotNull);
      expect(hero.dcc!.className, 'Warrior');
      expect(hero.dcc!.alignment, 'Lawful');
      expect(hero.dcc!.stats['str'], 16);
      expect(hero.dcc!.stats['lck'], 11);
      expect(hero.dcc!.lckMax, 11);
      expect(hero.dcc!.currentHp, 5);
      expect(hero.dcc!.maxHp, 5);
      expect(hero.dcc!.occupation, 'Blacksmith');
    });
  });

  group('Character funnel wiring', () {
    test('round-trips a funnel character through json', () {
      final c = Character(
        id: 'f1',
        name: 'Funnel',
        funnel: FunnelSheet(seedSystem: 'dcc', peasants: const [
          FunnelPeasant(name: 'A', hp: 3, stats: {'str': 12}),
        ]),
      );
      final back = Character.fromJson(c.toJson());
      expect(back.funnel, isNotNull);
      expect(back.funnel!.seedSystem, 'dcc');
      expect(back.funnel!.peasants.single.name, 'A');
    });
    test('clearFunnel drops the sheet', () {
      final c = Character(
          id: 'f1', name: 'F', funnel: const FunnelSheet(seedSystem: 'dcc'));
      expect(c.copyWith(clearFunnel: true).funnel, isNull);
    });
    test('withHpDelta leaves a funnel character unchanged', () {
      final c = Character(
          id: 'f1', name: 'F', funnel: const FunnelSheet(seedSystem: 'dcc'));
      expect(identical(c.withHpDelta(-5), c), true);
    });
  });
}
