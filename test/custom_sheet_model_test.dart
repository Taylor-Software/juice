import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/custom_sheet.dart';

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
    test('maybeFromJson tolerates non-map / null', () {
      expect(CustomSheet.maybeFromJson(null), isNull);
      expect(CustomSheet.maybeFromJson(42), isNull);
      final empty = CustomSheet.maybeFromJson({})!;
      expect(empty.blocks, isEmpty);
      expect(empty.values, isEmpty);
    });
  });
}
