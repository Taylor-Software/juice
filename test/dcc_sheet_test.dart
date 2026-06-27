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

  group('DccSheet', () {
    test('premade is a leveled level-1 hero', () {
      final s = DccSheet.premade();
      expect(s.className, 'Warrior');
      expect(s.level, 1);
    });

    test('round-trips through json', () {
      final sheet = const DccSheet(
        className: 'Wizard',
        level: 2,
        alignment: 'Chaotic',
        stats: {
          'str': 13,
          'agi': 10,
          'sta': 12,
          'per': 10,
          'int': 14,
          'lck': 9,
        },
        lckMax: 9,
        currentHp: 5,
        maxHp: 6,
        ac: 11,
        burns: {'str': 2, 'agi': 0, 'sta': 0, 'per': 0},
      );
      final back = DccSheet.maybeFromJson(sheet.toJson())!;
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
      final j = const DccSheet().toJson()
        ..['actionDie'] = 'foo'
        ..['deedDie'] = '';
      final s = DccSheet.maybeFromJson(j)!;
      expect(s.actionDie, 'd20');
      expect(s.deedDie, 'd3');
    });
  });

  group('Character DCC wiring', () {
    test('forSheet builds a leveled DCC character', () {
      final c = Character.forSheet('dcc', 'id1');
      expect(c.dcc, isNotNull);
      expect(c.name, 'New DCC character');
    });

    test('round-trips a dcc character through json', () {
      final c = Character.forSheet('dcc', 'id1')
          .copyWith(dcc: const DccSheet(notes: 'hi'));
      final back = Character.fromJson(c.toJson());
      expect(back.dcc, isNotNull);
      expect(back.dcc!.notes, 'hi');
    });

    test('withHpDelta adjusts DCC hp clamped to maxHp', () {
      final sheet = const DccSheet(
        className: 'Warrior',
        stats: {'str': 16, 'agi': 12, 'sta': 13, 'per': 9, 'int': 8, 'lck': 11},
        lckMax: 11,
        currentHp: 6,
        maxHp: 6,
      );
      final c = Character.forSheet('dcc', 'id1').copyWith(dcc: sheet);
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
