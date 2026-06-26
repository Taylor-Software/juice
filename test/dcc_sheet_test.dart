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
}
