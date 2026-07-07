import 'dice.dart';
import 'models.dart';

/// d10 likelihood target (Cairn Solo p.27): yes on <= target, with twists.
enum SoloLikelihood { unlikely, even, likely }

extension SoloLikelihoodX on SoloLikelihood {
  int get target => switch (this) {
        SoloLikelihood.unlikely => 3,
        SoloLikelihood.even => 5,
        SoloLikelihood.likely => 7,
      };
  String get label => switch (this) {
        SoloLikelihood.unlikely => 'Unlikely',
        SoloLikelihood.even => 'Even',
        SoloLikelihood.likely => 'Likely',
      };
}

enum SoloTwist { none, boon, complication }

class SoloYesNo {
  const SoloYesNo({
    required this.yes,
    required this.twist,
    required this.roll,
    required this.odds,
  });
  final bool yes;
  final SoloTwist twist;
  final int roll;
  final SoloLikelihood odds;

  String get phrase {
    final base = yes ? 'Yes' : 'No';
    return switch (twist) {
      SoloTwist.none => base,
      SoloTwist.boon => '$base, and a boon',
      SoloTwist.complication =>
        yes ? '$base, but a complication' : '$base, and a complication',
    };
  }

  /// [question] is the player's asked question; when given it becomes the
  /// entry title so the journal reads "Q — Yes" instead of a context-free
  /// answer (stranger-test audit S1).
  GenResult toGenResult({String question = ''}) {
    final q = question.trim();
    return GenResult(
      title: q.isEmpty ? 'Yes/No — ${odds.label}' : q,
      summary: phrase,
      rolls: [
        Roll(label: 'Result', value: phrase, detail: 'd10=$roll'),
        if (q.isNotEmpty) Roll(label: 'Odds', value: odds.label, detail: ''),
      ],
    );
  }
}

/// Pure mapping of a known d10 [roll] under [odds] (Cairn Solo p.27 table).
SoloYesNo classifyYesNo(SoloLikelihood odds, int roll) {
  final t = odds.target;
  late final bool yes;
  late final SoloTwist twist;
  if (roll == 1) {
    yes = true;
    twist = SoloTwist.boon;
  } else if (roll == 10) {
    yes = false;
    twist = SoloTwist.complication;
  } else if (roll < t) {
    yes = true;
    twist = SoloTwist.none;
  } else if (roll == t) {
    yes = true;
    twist = SoloTwist.complication;
  } else {
    yes = false;
    twist = SoloTwist.none;
  }
  return SoloYesNo(yes: yes, twist: twist, roll: roll, odds: odds);
}

SoloYesNo soloYesNo(SoloLikelihood odds, Dice dice) =>
    classifyYesNo(odds, dice.dN(10));
