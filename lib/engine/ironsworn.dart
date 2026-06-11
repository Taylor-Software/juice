import 'dice.dart';

/// Ironsworn/Starforged dice mechanics (rules CC-BY-4.0, Shawn Tomkin).
/// Pure mechanics — ruleset content comes from the Datasworn assets.
class Ironsworn {
  Ironsworn(this.dice);
  final Dice dice;

  IronswornRoll actionRoll({required int stat, int adds = 0}) {
    final action = dice.dN(6);
    return _resolve(action + stat + adds, actionDie: action);
  }

  IronswornRoll progressRoll({required int score}) =>
      _resolve(score, actionDie: null);

  IronswornRoll _resolve(int total, {int? actionDie}) {
    final c1 = dice.dN(10), c2 = dice.dN(10);
    final beats = (total > c1 ? 1 : 0) + (total > c2 ? 1 : 0);
    return IronswornRoll(
      total: total,
      actionDie: actionDie ?? 0,
      challenge1: c1,
      challenge2: c2,
      outcome: beats == 2
          ? 'Strong Hit'
          : beats == 1
              ? 'Weak Hit'
              : 'Miss',
      match: c1 == c2,
    );
  }

  /// d100 oracle against [rows] of [min, max, text].
  ({int roll, String text}) oracleRoll(List<dynamic> rows) {
    final roll = dice.d100();
    dynamic row;
    for (final r in rows) {
      if (roll >= (r[0] as int) && roll <= (r[1] as int)) {
        row = r;
        break;
      }
    }
    row ??= rows.last;
    return (roll: roll, text: row[2] as String);
  }
}

class IronswornRoll {
  const IronswornRoll({
    required this.total,
    required this.actionDie,
    required this.challenge1,
    required this.challenge2,
    required this.outcome,
    required this.match,
  });
  final int total;
  final int actionDie;
  final int challenge1;
  final int challenge2;
  final String outcome; // Strong Hit | Weak Hit | Miss
  final bool match;
}
