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
    // TEST C — multi-block round-trip through Character JSON
    test('Character round-trips a multi-block custom sheet', () {
      const sheet = CustomSheet(blocks: [
        CustomBlock(
            id: 'b1',
            type: CustomBlockType.stat,
            label: 'Stats',
            config: {
              'stats': [
                {'key': 'str', 'label': 'STR'}
              ],
              'min': 3,
              'max': 18,
              'modFormula': 'fived',
            }),
        CustomBlock(
            id: 'b2',
            type: CustomBlockType.hp,
            label: 'HP',
            config: {'allowTemp': true}),
        CustomBlock(
            id: 'b3',
            type: CustomBlockType.roll,
            label: 'Saves',
            config: {
              'rows': ['Fort'],
              'roll': {
                'dc': 1,
                'ds': 20,
                'ab': true,
                'dir': 'high',
                'tk': 'prompt',
                'crit': 'none'
              },
            }),
        CustomBlock(id: 'b4', type: CustomBlockType.freeform, label: 'Notes'),
      ], values: {
        'b1': {'str': 14},
        'b2': {'cur': 7, 'max': 10, 'temp': 2},
        'b3': [3],
        'b4': 'hi',
      });
      final back = Character.fromJson(
          const Character(id: 'c1', name: 'X', custom: sheet).toJson());
      expect(back.custom!.blocks.map((b) => b.type),
          sheet.blocks.map((b) => b.type));
      expect((back.custom!.values['b2'] as Map)['temp'], 2);
      expect(back.custom!.values['b4'], 'hi');
      expect((back.custom!.values['b1'] as Map)['str'], 14);
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
    // TEST A — FIX 2 coverage
    test('high bands below all thresholds returns Fail (no catch-all)', () {
      const cfg = RollConfig(
        diceCount: 2,
        diceSides: 10,
        direction: RollDirection.high,
        addBonus: true,
        bands: [
          RollBand(threshold: 17, label: 'Tier 3'),
          RollBand(threshold: 12, label: 'Tier 2'),
        ],
      );
      expect(resolveRoll(cfg, 0, [2, 3]).label, 'Fail'); // 5, below both
    });
    // TEST B — RollCrit.natural coverage
    test('natural crit on single die max/min', () {
      const cfg = RollConfig(
        diceCount: 1,
        diceSides: 20,
        direction: RollDirection.high,
        addBonus: true,
        targetKind: RollTargetKind.fixed,
        fixedTarget: 10,
        crit: RollCrit.natural,
      );
      expect(resolveRoll(cfg, 3, [20]).label, 'Critical Success');
      expect(resolveRoll(cfg, 3, [1]).label, 'Critical Failure');
      expect(resolveRoll(cfg, 3, [8]).label, 'Pass'); // 8+3=11 >= 10, no crit
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

  group('resolveComputed', () {
    const blocks = [
      CustomBlock(id: 's1', type: CustomBlockType.stat, label: 'Abilities', config: {
        'stats': [
          {'key': 'con', 'label': 'CON'}
        ],
        'min': 3,
        'max': 18,
      }),
      CustomBlock(id: 'h1', type: CustomBlockType.hp, label: 'HP'),
      CustomBlock(id: 'c1', type: CustomBlockType.counter, label: 'AC'),
    ];
    const values = {
      's1': {'con': 14},
      'h1': {'cur': 4, 'max': 10},
      'c1': 15,
    };

    test('10 + CON → number 24', () {
      const cfg = ComputedConfig(
        a: ComputedOperand(constant: 10),
        op: ComputedOp.add,
        b: ComputedOperand(isConst: false, blockId: 's1', subKey: 'con'),
      );
      final r = resolveComputed(blocks, values, cfg);
      expect(r.number, 24);
      expect(r.flag, isNull);
    });
    test('cur*2 <= max → flag (true then false)', () {
      const cfg = ComputedConfig(
        a: ComputedOperand(isConst: false, blockId: 'h1', subKey: 'cur', coeff: 2),
        op: ComputedOp.le,
        b: ComputedOperand(isConst: false, blockId: 'h1', subKey: 'max'),
      );
      expect(resolveComputed(blocks, values, cfg).flag, true);
      final hi = {...values, 'h1': {'cur': 6, 'max': 10}};
      expect(resolveComputed(blocks, hi, cfg).flag, false);
    });
    test('counter ref + arithmetic ops', () {
      ComputedConfig c(ComputedOp op, int k) => ComputedConfig(
          a: const ComputedOperand(isConst: false, blockId: 'c1'),
          op: op,
          b: ComputedOperand(constant: k));
      expect(resolveComputed(blocks, values, c(ComputedOp.sub, 5)).number, 10);
      expect(resolveComputed(blocks, values, c(ComputedOp.mul, 2)).number, 30);
      expect(resolveComputed(blocks, values, c(ComputedOp.divFloor, 4)).number, 3);
      expect(resolveComputed(blocks, values, c(ComputedOp.divFloor, 0)).number, 0);
    });
    test('comparison ops over constants', () {
      ({int? number, bool? flag}) r(ComputedOp op) => resolveComputed(blocks, values,
          ComputedConfig(
              a: const ComputedOperand(constant: 5), op: op, b: const ComputedOperand(constant: 5)));
      expect(r(ComputedOp.eq).flag, true);
      expect(r(ComputedOp.lt).flag, false);
      expect(r(ComputedOp.ge).flag, true);
      expect(r(ComputedOp.gt).flag, false);
    });
    test('graceful: missing block, missing key → 0', () {
      const missBlock = ComputedConfig(
          a: ComputedOperand(isConst: false, blockId: 'nope'),
          op: ComputedOp.add,
          b: ComputedOperand(constant: 7));
      expect(resolveComputed(blocks, values, missBlock).number, 7);
      const missKey = ComputedConfig(
          a: ComputedOperand(isConst: false, blockId: 's1', subKey: 'xyz'),
          op: ComputedOp.add,
          b: ComputedOperand(constant: 7));
      expect(resolveComputed(blocks, values, missKey).number, 7);
    });
    test('ComputedConfig JSON round-trips; fromJson tolerant', () {
      const cfg = ComputedConfig(
        a: ComputedOperand(isConst: false, blockId: 's1', subKey: 'con', coeff: 2),
        op: ComputedOp.ge,
        b: ComputedOperand(constant: 12),
      );
      final back = ComputedConfig.maybeFromJson(cfg.toJson());
      expect(back.op, ComputedOp.ge);
      expect(back.a.blockId, 's1');
      expect(back.a.coeff, 2);
      expect(back.b.constant, 12);
      final d = ComputedConfig.maybeFromJson('nope');
      expect(d.op, ComputedOp.add);
      expect(d.a.isConst, true);
      expect(d.a.constant, 0);
    });
  });
}
