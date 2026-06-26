import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

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
}
