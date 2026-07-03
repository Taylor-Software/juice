import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/combat.dart';

void main() {
  group('resolveHit', () {
    test('total >= ac is a hit', () {
      expect(resolveHit(18, 15), AttackOutcome.hit);
      expect(resolveHit(15, 15), AttackOutcome.hit);
    });
    test('total < ac is a miss', () {
      expect(resolveHit(12, 15), AttackOutcome.miss);
    });
    test('ac <= 0 (no recorded AC) is unknown', () {
      expect(resolveHit(20, 0), AttackOutcome.unknown);
      expect(resolveHit(1, -3), AttackOutcome.unknown);
    });
  });

  group('combatLogLine', () {
    test('hit with AC, damage, and an HP pool', () {
      expect(
        combatLogLine(
          attacker: 'Goblin',
          target: 'Mira',
          attackTotal: 18,
          targetAc: 15,
          hit: true,
          damage: 7,
          hp: (12, 5),
        ),
        'Goblin → Mira: 18 vs AC 15 — Hit, 7 dmg (Mira 12→5)',
      );
    });
    test('miss omits damage and HP', () {
      expect(
        combatLogLine(
          attacker: 'Goblin',
          target: 'Mira',
          attackTotal: 9,
          targetAc: 15,
          hit: false,
        ),
        'Goblin → Mira: 9 vs AC 15 — Miss',
      );
    });
    test('unknown AC omits the "vs AC" clause', () {
      expect(
        combatLogLine(
          attacker: 'Goblin',
          target: 'Mira',
          attackTotal: 14,
          targetAc: 0,
          hit: true,
          damage: 4,
          hp: (10, 6),
        ),
        'Goblin → Mira: 14 — Hit, 4 dmg (Mira 10→6)',
      );
    });
    test('hit without an HP pool omits the parenthetical', () {
      expect(
        combatLogLine(
          attacker: 'Goblin',
          target: 'Mira',
          attackTotal: 18,
          targetAc: 15,
          hit: true,
          damage: 7,
        ),
        'Goblin → Mira: 18 vs AC 15 — Hit, 7 dmg',
      );
    });
  });

  group('attackDiceFromDetail', () {
    test('d20 token is the attack, the other die is damage', () {
      final r = attackDiceFromDetail('Longbow 1d20+5, 1d8+3');
      expect(r.attack, '1d20+5');
      expect(r.damage, '1d8+3');
    });
    test('a bare +N modifier is not a die; only damage is filled', () {
      final r = attackDiceFromDetail('Scimitar +4, 1d6+2 slashing');
      expect(r.attack, isNull);
      expect(r.damage, '1d6+2');
    });
    test('damage-only attack fills damage, leaves attack null', () {
      final r = attackDiceFromDetail('Claw 2d4');
      expect(r.attack, isNull);
      expect(r.damage, '2d4');
    });
    test('attack-only detail fills attack, leaves damage null', () {
      final r = attackDiceFromDetail('1d20+7 to hit');
      expect(r.attack, '1d20+7');
      expect(r.damage, isNull);
    });
    test('no dice yields two nulls', () {
      expect(attackDiceFromDetail('grapple, no damage').attack, isNull);
      expect(attackDiceFromDetail('').damage, isNull);
    });
  });
}
