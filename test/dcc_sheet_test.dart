import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/campaign_presets.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/shared/home_shell.dart';

void main() {
  group('dccAbilityMod', () {
    test('maps the 3-18 curve capped at +/-3', () {
      expect(dccAbilityMod(3), -3);
      expect(dccAbilityMod(4), -2);
      expect(dccAbilityMod(5), -2);
      expect(dccAbilityMod(6), -1);
      expect(dccAbilityMod(8), -1);
      expect(dccAbilityMod(9), 0);
      expect(dccAbilityMod(12), 0);
      expect(dccAbilityMod(13), 1);
      expect(dccAbilityMod(15), 1);
      expect(dccAbilityMod(16), 2);
      expect(dccAbilityMod(17), 2);
      expect(dccAbilityMod(18), 3);
    });
    test('clamps out-of-range input', () {
      expect(dccAbilityMod(0), -3);
      expect(dccAbilityMod(25), 3);
    });
  });

  test('DCC constants are well-formed', () {
    expect(kDccClasses, contains('Warrior'));
    expect(kDccClasses.length, 7);
    expect(kDccStats, ['str', 'agi', 'sta', 'per', 'int', 'lck']);
    expect(kDccClassHitDie['Warrior'], 12);
    expect(kDccDeedDieClasses, containsAll(['Warrior', 'Dwarf']));
    expect(kDccCasterClasses, containsAll(['Wizard', 'Elf', 'Cleric']));
    expect(kDccSpellburnStats['Cleric'], ['per']);
  });

  group('DccPeasant', () {
    test('premade has clamped stats and is alive', () {
      const p = DccPeasant();
      expect(p.alive, true);
      expect(p.hp, 1);
      for (final k in kDccStats) {
        expect(p.stats[k], 10);
      }
    });
    test('copyWith clamps hp and stats', () {
      const p = DccPeasant();
      final p2 = p.copyWith(hp: 99, stats: {...p.stats, 'str': 25});
      expect(p2.hp, 8);
      expect(p2.stats['str'], 18);
    });
    test('round-trips through json', () {
      const p = DccPeasant(
          name: 'Bob', occupation: 'Farmer', weapon: 'Pitchfork', hp: 4);
      final back = DccPeasant.fromJson(p.toJson());
      expect(back.name, 'Bob');
      expect(back.occupation, 'Farmer');
      expect(back.weapon, 'Pitchfork');
      expect(back.hp, 4);
    });
  });

  group('DccSheet', () {
    test('premade is a one-peasant funnel', () {
      final s = DccSheet.premade();
      expect(s.mode, 'funnel');
      expect(s.peasants.length, 1);
      expect(s.peasants.first.alive, true);
    });

    test('graduate copies stats, sets hp/lckMax, preserves peasants', () {
      final s = DccSheet.premade().copyWith(peasants: [
        const DccPeasant(
            name: 'Survivor',
            occupation: 'Blacksmith',
            hp: 5,
            stats: {
              'str': 16,
              'agi': 12,
              'sta': 14,
              'per': 9,
              'int': 8,
              'lck': 11,
            }),
      ]);
      final g = s.graduate(0, 'Warrior', 'Lawful');
      expect(g.mode, 'leveled');
      expect(g.className, 'Warrior');
      expect(g.alignment, 'Lawful');
      expect(g.occupation, 'Blacksmith');
      expect(g.stats['str'], 16);
      expect(g.stats['lck'], 11);
      expect(g.lckMax, 11);
      expect(g.currentHp, 5);
      expect(g.maxHp, 5);
      expect(g.peasants.length, 1); // preserved
    });

    test('round-trips both modes through json', () {
      final funnel = DccSheet.premade();
      expect(DccSheet.maybeFromJson(funnel.toJson())!.mode, 'funnel');

      final leveled = funnel
          .copyWith(peasants: [
            const DccPeasant(hp: 6, stats: {
              'str': 13,
              'agi': 10,
              'sta': 12,
              'per': 10,
              'int': 14,
              'lck': 9,
            })
          ])
          .graduate(0, 'Wizard', 'Chaotic')
          .copyWith(level: 2, ac: 11, burns: {'str': 2});
      final back = DccSheet.maybeFromJson(leveled.toJson())!;
      expect(back.mode, 'leveled');
      expect(back.className, 'Wizard');
      expect(back.level, 2);
      expect(back.ac, 11);
      expect(back.burns['str'], 2);
      expect(back.stats['int'], 14);
    });

    test('maybeFromJson returns null for non-map', () {
      expect(DccSheet.maybeFromJson(null), isNull);
      expect(DccSheet.maybeFromJson('x'), isNull);
    });

    test('maybeFromJson sanitizes corrupted dice tokens', () {
      // The leveled UI parses dice sides via substring(1) + int.parse, so a
      // malformed token must default rather than survive (would crash on roll).
      final j = DccSheet.premade().toJson()
        ..['actionDie'] = 'foo'
        ..['deedDie'] = '';
      final s = DccSheet.maybeFromJson(j)!;
      expect(s.actionDie, 'd20');
      expect(s.deedDie, 'd3');
    });
  });

  group('Character DCC wiring', () {
    test('forSheet builds a DCC funnel character', () {
      final c = Character.forSheet('dcc', 'id1');
      expect(c.dcc, isNotNull);
      expect(c.dcc!.mode, 'funnel');
    });

    test('round-trips a dcc character through json', () {
      final c = Character.forSheet('dcc', 'id1')
          .copyWith(dcc: DccSheet.premade().copyWith(notes: 'hi'));
      final back = Character.fromJson(c.toJson());
      expect(back.dcc, isNotNull);
      expect(back.dcc!.notes, 'hi');
    });

    test('withHpDelta adjusts leveled DCC hp clamped to maxHp', () {
      final leveled = DccSheet.premade()
          .copyWith(peasants: [const DccPeasant(hp: 6)]).graduate(
              0, 'Warrior', 'Neutral');
      final c = Character.forSheet('dcc', 'id1').copyWith(dcc: leveled);
      expect(c.dcc!.currentHp, 6);
      final hurt = c.withHpDelta(-4);
      expect(hurt.dcc!.currentHp, 2);
      final overheal = hurt.withHpDelta(99);
      expect(overheal.dcc!.currentHp, 6); // clamped to maxHp
    });

    test('clearDcc drops the sheet', () {
      final c = Character.forSheet('dcc', 'id1');
      expect(c.copyWith(clearDcc: true).dcc, isNull);
    });
  });

  group('DCC system registration', () {
    test('dcc is a known ruleset', () {
      expect(kKnownSystems, contains('dcc'));
      expect(kSystemCategory['dcc'], SystemCategory.ruleset);
    });
    test('solo-dcc preset resolves to dcc ruleset', () {
      final preset = kCampaignPresets.firstWhere((p) => p.id == 'solo-dcc');
      final (mode, systems) = presetConfig(preset);
      expect(systems, contains('dcc'));
      expect(mode, CampaignMode.party);
    });
    test('kSystemBlurbs dcc carries the non-affiliation note', () {
      final blurb = kSystemBlurbs['dcc'] ?? '';
      expect(blurb.toLowerCase(), contains('not affiliated'));
    });
  });
}
