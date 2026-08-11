import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/sheet_rolls.dart';

// The banding these functions perform used to live inline in each sheet
// widget alongside a bare Random(), so none of it could be asserted. These
// tests pin every boundary — the off-by-one at each threshold is exactly what
// a refactor of a sheet would otherwise break silently.
void main() {
  group('Argosa roll-under', () {
    test('under half the score is a Great Success', () {
      expect(argosaRollUnder(5, 12).outcome, 'Great Success'); // half = 6
      expect(argosaRollUnder(6, 12).outcome, 'Great Success'); // == half
    });
    test('at or under the score is a Success', () {
      expect(argosaRollUnder(7, 12).outcome, 'Success');
      expect(argosaRollUnder(12, 12).outcome, 'Success'); // == score
    });
    test('over the score fails', () {
      expect(argosaRollUnder(13, 12).outcome, 'Failure');
    });
    test('reports the die face, not a modified total', () {
      expect(argosaRollUnder(13, 12).total, 13);
    });
    test('odd scores floor the half', () {
      // score 11 -> half 5, so a 5 crits and a 6 does not.
      expect(argosaRollUnder(5, 11).outcome, 'Great Success');
      expect(argosaRollUnder(6, 11).outcome, 'Success');
    });
  });

  group('Cairn save', () {
    test('rolling at or under the score passes', () {
      expect(cairnSave(10, 10).outcome, 'Pass');
      expect(cairnSave(9, 10).outcome, 'Pass');
    });
    test('rolling over the score fails', () {
      expect(cairnSave(11, 10).outcome, 'Fail');
    });
  });

  group('Knave save', () {
    test('the stat is added to the die (2e scores ARE modifiers)', () {
      expect(knaveSave(8, 3).total, 11);
    });
    test('11 or better passes', () {
      expect(knaveSave(8, 3).outcome, 'Pass'); // exactly 11
      expect(knaveSave(7, 3).outcome, 'Fail'); // 10
    });
    test('a zero stat still resolves', () {
      expect(knaveSave(11, 0).outcome, 'Pass');
      expect(knaveSave(10, 0).outcome, 'Fail');
    });
  });

  group('OSE save', () {
    test('meeting the target passes', () {
      expect(oseSave(12, 12).outcome, 'Pass');
      expect(oseSave(11, 12).outcome, 'Fail');
    });
    test('the target is the character sheet value, not a constant', () {
      expect(oseSave(5, 4).outcome, 'Pass');
      expect(oseSave(5, 20).outcome, 'Fail');
    });
  });

  group('Embark check', () {
    test('d12 + attribute - injuries against 8', () {
      expect(embarkCheck(6, 2, 0).total, 8);
      expect(embarkCheck(6, 2, 0).outcome, 'Success');
    });
    test('injuries subtract — the death track doubles as a penalty', () {
      expect(embarkCheck(6, 2, 1).total, 7);
      expect(embarkCheck(6, 2, 1).outcome, 'Failure');
    });
    test('a negative attribute is honoured', () {
      expect(embarkCheck(10, -1, 0).total, 9);
      expect(embarkCheck(10, -1, 0).outcome, 'Success');
    });
  });

  group('Kal-Arath 2d6', () {
    test('2d6 + stat against 8', () {
      expect(kalArathRoll(4, 3, 1).total, 8);
      expect(kalArathRoll(4, 3, 1).outcome, 'Success');
      expect(kalArathRoll(3, 3, 1).outcome, 'Failure');
    });
    test('boxcars crit even when the total would already succeed', () {
      expect(kalArathRoll(6, 6, 5).outcome, 'Critical Success');
    });
    test('snake eyes crit-fail even with a huge stat bonus', () {
      final r = kalArathRoll(1, 1, 20);
      expect(r.total, 22); // the total is still reported honestly
      expect(r.outcome, 'Critical Failure');
    });
    test('a 6 and a 1 is an ordinary roll, not a crit either way', () {
      expect(kalArathRoll(6, 1, 1).outcome, 'Success'); // 8
      expect(kalArathRoll(6, 1, 0).outcome, 'Failure'); // 7
    });
  });

  group('Draw Steel power roll', () {
    test('11 or less is Tier 1', () {
      expect(drawSteelPowerRoll(5, 6, 0).outcome, 'Tier 1'); // 11
    });
    test('12 to 16 is Tier 2', () {
      expect(drawSteelPowerRoll(6, 6, 0).outcome, 'Tier 2'); // 12
      expect(drawSteelPowerRoll(8, 8, 0).outcome, 'Tier 2'); // 16
    });
    test('17 or more is Tier 3', () {
      expect(drawSteelPowerRoll(9, 8, 0).outcome, 'Tier 3'); // 17
    });
    test('the characteristic shifts the tier', () {
      expect(drawSteelPowerRoll(5, 6, 1).outcome, 'Tier 2'); // 11 + 1
    });
  });

  group('DCC', () {
    test('a save adds the bonus and compares to the DC', () {
      expect(dccSave(10, 5, 15).total, 15);
      expect(dccSave(10, 5, 15).outcome, 'Pass'); // exactly the DC
      expect(dccSave(9, 5, 15).outcome, 'Fail');
    });
    test('a negative save bonus is honoured', () {
      expect(dccSave(10, -2, 10).outcome, 'Fail');
    });
    test('a deed resolves independently of the attack', () {
      final r = dccDeed(10, 2, 3, 3);
      expect(r.attack, 12);
      expect(r.deed, 3);
      expect(r.deedSucceeds, isTrue); // exactly the minimum
      expect(dccDeed(1, 0, 2, 3).deedSucceeds, isFalse);
    });
    test('a spell check reports base separately from spellburn', () {
      final r = dccSpellCheck(
          actionDie: 10, level: 2, abilityMod: 1, spellburn: 4, dc: 15);
      expect(r.base, 13);
      expect(r.total, 17);
      expect(r.success, isTrue);
    });
    test('spellburn is what carries a failing check over the DC', () {
      const args = (actionDie: 10, level: 2, abilityMod: 1, dc: 15);
      expect(
          dccSpellCheck(
                  actionDie: args.actionDie,
                  level: args.level,
                  abilityMod: args.abilityMod,
                  spellburn: 0,
                  dc: args.dc)
              .success,
          isFalse);
      expect(
          dccSpellCheck(
                  actionDie: args.actionDie,
                  level: args.level,
                  abilityMod: args.abilityMod,
                  spellburn: 2,
                  dc: args.dc)
              .success,
          isTrue);
    });
    test('disapproval inverts — rolling LOW is the bad outcome', () {
      expect(dccDisapproval(1, 1).disapproves, isTrue);
      expect(dccDisapproval(2, 1).disapproves, isFalse);
      expect(dccDisapproval(5, 5).disapproves, isTrue); // at the range edge
    });
  });
}
