/// Pure resolution for the per-system character-sheet rolls.
///
/// Each sheet used to roll a bare `Random()` inline and band the result in the
/// widget, so none of this logic could be tested without pumping a sheet — and
/// none of it was. Every function here takes the raw die faces already rolled
/// (through the injected [Dice], so a test can seed them) and returns the
/// number shown to the player plus that system's own word for the outcome.
/// The widget keeps only the snackbar.
///
/// Facts-only, like the sheets themselves: these are bare resolution
/// procedures (roll-under, roll-plus-modifier-vs-target), which carry no
/// rulebook prose and no licensing burden — the same basis as
/// `system_primer.dart` and `quick_ref.dart`.
library;

/// A resolved sheet roll: the number to show, and the outcome word.
typedef SheetRoll = ({int total, String outcome});

/// Tales of Argosa — roll d20 under the stat. Under half the score is a
/// Great Success. The die face itself is what's shown.
SheetRoll argosaRollUnder(int d20, int score) => (
      total: d20,
      outcome: d20 <= score ~/ 2
          ? 'Great Success'
          : d20 <= score
              ? 'Success'
              : 'Failure',
    );

/// Cairn — roll d20 under or equal to the ability score to pass the save.
SheetRoll cairnSave(int d20, int score) =>
    (total: d20, outcome: d20 <= score ? 'Pass' : 'Fail');

/// Knave 2e — d20 plus the stat (scores ARE modifiers in 2e) against 11.
SheetRoll knaveSave(int d20, int score) => (
      total: d20 + score,
      outcome: d20 + score >= kKnaveSaveTarget ? 'Pass' : 'Fail',
    );

/// The fixed Knave 2e save target.
const kKnaveSaveTarget = 11;

/// OSE / B/X — d20 at or above the character's own save target. The target is
/// player-managed on the sheet, so it is passed in rather than derived.
SheetRoll oseSave(int d20, int target) =>
    (total: d20, outcome: d20 >= target ? 'Pass' : 'Fail');

/// Embark 2E — d12 plus the attribute, minus accumulated injuries (the death
/// track doubles as a penalty), against 8.
SheetRoll embarkCheck(int d12, int score, int injuries) {
  final total = d12 + score - injuries;
  return (
    total: total,
    outcome: total >= kEmbarkCheckTarget ? 'Success' : 'Failure'
  );
}

/// The fixed Embark 2E check target.
const kEmbarkCheckTarget = 8;

/// Kal-Arath — 2d6 plus the stat against 8. Doubles override the total:
/// snake eyes always fail and boxcars always succeed, however good the stat.
SheetRoll kalArathRoll(int d6a, int d6b, int score) {
  final total = d6a + d6b + score;
  final String outcome;
  if (d6a == 6 && d6b == 6) {
    outcome = 'Critical Success';
  } else if (d6a == 1 && d6b == 1) {
    outcome = 'Critical Failure';
  } else {
    outcome = total >= kKalArathTarget ? 'Success' : 'Failure';
  }
  return (total: total, outcome: outcome);
}

/// The fixed Kal-Arath target number.
const kKalArathTarget = 8;

/// Draw Steel — the power roll: 2d10 plus the characteristic, banded into
/// three tiers at 11 and 16.
SheetRoll drawSteelPowerRoll(int d10a, int d10b, int score) {
  final total = d10a + d10b + score;
  return (
    total: total,
    outcome: total <= 11
        ? 'Tier 1'
        : total <= 16
            ? 'Tier 2'
            : 'Tier 3',
  );
}

/// DCC — a save: d20 plus the save bonus against a GM-set DC.
SheetRoll dccSave(int d20, int bonus, int dc) {
  final total = d20 + bonus;
  return (total: total, outcome: total >= dc ? 'Pass' : 'Fail');
}

/// DCC — Mighty Deed: the attack roll and the deed die resolve separately;
/// the deed lands on [kDccDeedSuccessMin] or better regardless of the attack.
({int attack, int deed, bool deedSucceeds}) dccDeed(
  int d20,
  int attackBonus,
  int deedDie,
  int deedSuccessMin,
) =>
    (
      attack: d20 + attackBonus,
      deed: deedDie,
      deedSucceeds: deedDie >= deedSuccessMin,
    );

/// DCC — a spell check: the action die plus caster level plus the casting
/// ability modifier, then spellburn on top. [base] is reported separately so
/// the player can see what the burn actually bought.
({int base, int total, bool success}) dccSpellCheck({
  required int actionDie,
  required int level,
  required int abilityMod,
  required int spellburn,
  required int dc,
}) {
  final base = actionDie + level + abilityMod;
  final total = base + spellburn;
  return (base: base, total: total, success: total >= dc);
}

/// DCC — a cleric's disapproval check: d20 at or under the current range is
/// disapproval. Note this is the inverse of a save — low is bad.
({int roll, bool disapproves}) dccDisapproval(int d20, int range) =>
    (roll: d20, disapproves: d20 <= range);
