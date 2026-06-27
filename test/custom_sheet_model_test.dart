import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/campaign_presets.dart';
import 'package:juice_oracle/engine/campaign_surfaces.dart';
import 'package:juice_oracle/engine/custom_sheet.dart';
import 'package:juice_oracle/engine/custom_templates.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/shared/home_shell.dart';

void main() {
  group('customStatMod', () {
    test('fived: 5e curve', () {
      expect(customStatMod(StatModFormula.fived, 10), 0);
      expect(customStatMod(StatModFormula.fived, 18), 4);
      expect(customStatMod(StatModFormula.fived, 3), -4);
    });
    test('dccTight: capped +/-3 table', () {
      expect(customStatMod(StatModFormula.dccTight, 3), -3);
      expect(customStatMod(StatModFormula.dccTight, 8), -1);
      expect(customStatMod(StatModFormula.dccTight, 9), 0);
      expect(customStatMod(StatModFormula.dccTight, 12), 0);
      expect(customStatMod(StatModFormula.dccTight, 13), 1);
      expect(customStatMod(StatModFormula.dccTight, 18), 3);
    });
    test('scoreIsMod: identity', () {
      expect(customStatMod(StatModFormula.scoreIsMod, 4), 4);
      expect(customStatMod(StatModFormula.scoreIsMod, -2), -2);
    });
    test('halfFloor', () {
      expect(customStatMod(StatModFormula.halfFloor, 7), 3);
      expect(customStatMod(StatModFormula.halfFloor, 4), 2);
    });
    test('statModFormulaFromName: known + unknown fallback to raw', () {
      expect(statModFormulaFromName('fived'), StatModFormula.fived);
      expect(statModFormulaFromName('bogus'), StatModFormula.raw);
      expect(statModFormulaFromName(null), StatModFormula.raw);
    });
  });

  group('CustomSheet JSON', () {
    test('round-trips blocks + values', () {
      const sheet = CustomSheet(blocks: [
        CustomBlock(
            id: 'b1',
            type: CustomBlockType.counter,
            label: 'AC',
            config: {'min': 0, 'max': 30}),
        CustomBlock(id: 'b2', type: CustomBlockType.freeform, label: 'Notes'),
      ], values: {
        'b1': 15,
        'b2': 'hello',
      });
      final back = CustomSheet.maybeFromJson(sheet.toJson())!;
      expect(back.blocks.length, 2);
      expect(back.blocks[0].id, 'b1');
      expect(back.blocks[0].type, CustomBlockType.counter);
      expect(back.blocks[0].label, 'AC');
      expect(back.blocks[0].config['max'], 30);
      expect(back.values['b1'], 15);
      expect(back.values['b2'], 'hello');
    });
    test('drops a block with an unknown type', () {
      final back = CustomSheet.maybeFromJson({
        'blocks': [
          {'id': 'x', 'type': 'counter', 'label': 'A'},
          {'id': 'y', 'type': 'bogus', 'label': 'B'},
        ],
      })!;
      expect(back.blocks.map((b) => b.id), ['x']);
    });
    test('drops an id-less block', () {
      final back = CustomSheet.maybeFromJson({
        'blocks': [
          {'type': 'counter', 'label': 'A'},
        ],
      })!;
      expect(back.blocks, isEmpty);
    });
    test('maybeFromJson tolerates non-map / null', () {
      expect(CustomSheet.maybeFromJson(null), isNull);
      expect(CustomSheet.maybeFromJson(42), isNull);
      final empty = CustomSheet.maybeFromJson({})!;
      expect(empty.blocks, isEmpty);
      expect(empty.values, isEmpty);
    });
  });

  group('Character.custom integration', () {
    test('round-trips through Character JSON', () {
      const sheet = CustomSheet(blocks: [
        CustomBlock(id: 'b1', type: CustomBlockType.freeform, label: 'Notes'),
      ], values: {
        'b1': 'hi'
      });
      const c = Character(id: 'c1', name: 'Homebrew', custom: sheet);
      final back = Character.fromJson(c.toJson());
      expect(back.custom, isNotNull);
      expect(back.custom!.blocks.single.label, 'Notes');
      expect(back.custom!.values['b1'], 'hi');
    });
    test('forSheet seeds a blank custom sheet', () {
      final c = Character.forSheet('custom', 'c9');
      expect(c.custom, isNotNull);
      expect(c.custom!.blocks, isEmpty);
    });
    test('copyWith clearCustom drops the sheet', () {
      const c = Character(
          id: 'c1', name: 'X', custom: CustomSheet(blocks: []));
      expect(c.copyWith(clearCustom: true).custom, isNull);
    });
    test('custom is a known, categorized ruleset system', () {
      expect(kKnownSystems.contains('custom'), isTrue);
      expect(kSystemCategory['custom'], SystemCategory.ruleset);
    });
  });

  test('kSystemBlurbs covers custom (new_campaign_dialog completeness)', () {
    expect(kSystemBlurbs['custom'], isNotNull);
    expect(kSystemBlurbs['custom']!.toLowerCase(), contains('custom'));
  });

  group('resolveRoll', () {
    // dice are passed explicitly so the tests are deterministic.
    test('Cairn-style roll-under own value: pass/fail', () {
      const cfg = RollConfig(
          direction: RollDirection.low,
          addBonus: false,
          targetKind: RollTargetKind.rowValue);
      expect(resolveRoll(cfg, 14, [10]).label, 'Pass');
      expect(resolveRoll(cfg, 14, [18]).label, 'Fail');
    });
    test('Argosa-style low with great-on-half ladder', () {
      const cfg = RollConfig(
        direction: RollDirection.low,
        addBonus: false,
        targetKind: RollTargetKind.rowValue,
        bands: [
          RollBand(threshold: 0.5, label: 'Great Success'),
          RollBand(threshold: 1.0, label: 'Success'),
        ],
      );
      expect(resolveRoll(cfg, 16, [4]).label, 'Great Success'); // 4 <= 8
      expect(resolveRoll(cfg, 16, [12]).label, 'Success'); // 12 <= 16
      expect(resolveRoll(cfg, 16, [18]).label, 'Fail');
    });
    test('D&D/DCC high + bonus vs prompted DC', () {
      const cfg = RollConfig(
          direction: RollDirection.high,
          addBonus: true,
          targetKind: RollTargetKind.prompt);
      expect(resolveRoll(cfg, 3, [11], promptTarget: 11).total, 14);
      expect(resolveRoll(cfg, 3, [11], promptTarget: 11).label, 'Pass');
      expect(resolveRoll(cfg, 3, [5], promptTarget: 11).label, 'Fail');
    });
    test('Knave high + bonus vs fixed target', () {
      const cfg = RollConfig(
          direction: RollDirection.high,
          addBonus: true,
          targetKind: RollTargetKind.fixed,
          fixedTarget: 11);
      expect(resolveRoll(cfg, 4, [7]).label, 'Pass'); // 7+4=11 >= 11
      expect(resolveRoll(cfg, 4, [6]).label, 'Fail');
    });
    test('PbtA 2d6 ladder', () {
      const cfg = RollConfig(
        diceCount: 2,
        diceSides: 6,
        direction: RollDirection.high,
        addBonus: true,
        bands: [
          RollBand(threshold: 10, label: 'Strong hit'),
          RollBand(threshold: 7, label: 'Weak hit'),
          RollBand(threshold: 0, label: 'Miss'),
        ],
      );
      expect(resolveRoll(cfg, 2, [5, 4]).label, 'Strong hit'); // 11
      expect(resolveRoll(cfg, 1, [4, 3]).label, 'Weak hit'); // 8
      expect(resolveRoll(cfg, 0, [1, 2]).label, 'Miss'); // 3
    });
    test('Kal-Arath crit on matching dice', () {
      const cfg = RollConfig(
          diceCount: 2,
          diceSides: 6,
          direction: RollDirection.high,
          addBonus: true,
          targetKind: RollTargetKind.fixed,
          fixedTarget: 8,
          crit: RollCrit.matchingDice);
      expect(resolveRoll(cfg, 0, [6, 6]).label, 'Critical Success');
      expect(resolveRoll(cfg, 0, [1, 1]).label, 'Critical Failure');
      expect(resolveRoll(cfg, 2, [4, 2]).label, 'Pass'); // 6+2=8 >= 8
    });
    test('Draw Steel 2d10 tiers', () {
      const cfg = RollConfig(
        diceCount: 2,
        diceSides: 10,
        direction: RollDirection.high,
        addBonus: true,
        bands: [
          RollBand(threshold: 17, label: 'Tier 3'),
          RollBand(threshold: 12, label: 'Tier 2'),
          RollBand(threshold: 0, label: 'Tier 1'),
        ],
      );
      expect(resolveRoll(cfg, 2, [9, 8]).label, 'Tier 3'); // 19
      expect(resolveRoll(cfg, 1, [7, 5]).label, 'Tier 2'); // 13
      expect(resolveRoll(cfg, 0, [2, 3]).label, 'Tier 1'); // 5
    });
    test('RollConfig JSON round-trips', () {
      const cfg = RollConfig(
          diceCount: 2,
          diceSides: 6,
          bands: [RollBand(threshold: 10, label: 'Hit')],
          crit: RollCrit.matchingDice);
      final back = RollConfig.fromJson(cfg.toJson());
      expect(back.diceSides, 6);
      expect(back.bands.single.label, 'Hit');
      expect(back.crit, RollCrit.matchingDice);
    });
  });

  group('kCustomTemplates', () {
    test('has the four authored starters incl. Blank', () {
      final ids = kCustomTemplates.map((t) => t.id).toList();
      expect(ids, containsAll(['blank', 'generic-d20', 'osr', 'pbta']));
    });
    test('blank has no blocks; others have blocks with unique ids', () {
      for (final t in kCustomTemplates) {
        if (t.id == 'blank') {
          expect(t.blocks, isEmpty);
          continue;
        }
        expect(t.blocks, isNotEmpty, reason: t.id);
        final ids = t.blocks.map((b) => b.id).toList();
        expect(ids.toSet().length, ids.length, reason: '${t.id} dup ids');
      }
    });
    test('every block type/formula referenced is valid (round-trips)', () {
      for (final t in kCustomTemplates) {
        final back = CustomSheet.maybeFromJson(
            CustomSheet(blocks: t.blocks).toJson())!;
        expect(back.blocks.length, t.blocks.length, reason: t.id);
      }
    });
  });

  test('solo-custom preset resolves to the custom ruleset', () {
    final p = kCampaignPresets.firstWhere((p) => p.id == 'solo-custom');
    final (mode, systems) = presetConfig(p);
    expect(systems.contains('custom'), isTrue);
    expect(mode, CampaignMode.party);
  });

  test('custom lights up a Sheet surface', () {
    final sheet = surfacesFor(CampaignMode.party, {'custom'})
        .firstWhere((v) => v.verb == 'Sheet');
    expect(sheet.rows.any((r) => r.on && r.requiresSystem == 'custom'), isTrue);
  });
}
