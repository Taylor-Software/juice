import 'verdant_data.dart';
import 'dice.dart';

/// Travel pace (Optional Rule: Travel Pace).
enum Pace { normal, slow, fast }

/// Result of an end-of-round Random Encounter check.
enum EncounterOutcome { none, danger, benign }

/// ER = 4 + (characters in party / 2), rounded down. Independent Followers
/// are excluded by callers (they pass the contributing party count only).
int encounterRisk(int partySize) => 4 + (partySize ~/ 2);

/// Live website v1.2 rule: a dangerous encounter when `d12 + safety < er`;
/// a natural 12 is a benign encounter (no immediate danger); otherwise none.
/// There is no natural-1 special case.
EncounterOutcome resolveEncounter(
    {required int d12, required int safety, required int er}) {
  if (d12 == 12) return EncounterOutcome.benign;
  if (d12 + safety < er) return EncounterOutcome.danger;
  return EncounterOutcome.none;
}

/// Round-start Safety baseline: standing conditions stack. Nighttime (Evening
/// or Night watch) is Deadly (−2); Slow pace is Safer (+2); Fast pace is
/// Deadly (−2). Task outcomes are added on top during the round.
int baselineSafety({required bool night, Pace pace = Pace.normal}) {
  var s = night ? -2 : 0;
  if (pace == Pace.slow) s += 2;
  if (pace == Pace.fast) s += -2;
  return s;
}

/// d12 + safety vs er, returning the die and the outcome.
({int d12, EncounterOutcome outcome}) rollEncounter(Dice dice,
    {required int safety, required int er}) {
  final d12 = dice.dN(12);
  return (
    d12: d12,
    outcome: resolveEncounter(d12: d12, safety: safety, er: er)
  );
}

VerdantRow rollPoi(Dice dice, VerdantData data) =>
    data.pointsOfInterest[dice.dN(12) - 1];

VerdantRow rollQuickEncounter(Dice dice, VerdantData data) =>
    data.quickEncounters[dice.dN(10) - 1];

/// Homebrew (not a Verdant rule): pick a terrain at random for solo map-gen.
VerdantTerrain rollTerrain(Dice dice, VerdantData data) =>
    data.terrain[dice.dN(10) - 1];
