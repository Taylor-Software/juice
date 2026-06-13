import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/verdant.dart';
import 'package:juice_oracle/engine/verdant_data.dart';

void main() {
  final data = VerdantData(
      jsonDecode(File('assets/verdant_data.json').readAsStringSync())
          as Map<String, dynamic>);

  test('encounterRisk = 4 + party ~/ 2', () {
    expect(encounterRisk(1), 4);
    expect(encounterRisk(2), 5);
    expect(encounterRisk(3), 5);
    expect(encounterRisk(4), 6);
  });

  test('resolveEncounter: natural 12 is benign, low total is danger', () {
    // ER 5: d12+safety < 5 => danger.
    expect(
        resolveEncounter(d12: 12, safety: 0, er: 5), EncounterOutcome.benign);
    expect(
        resolveEncounter(d12: 12, safety: -4, er: 5), EncounterOutcome.benign);
    expect(resolveEncounter(d12: 2, safety: 0, er: 5), EncounterOutcome.danger);
    expect(resolveEncounter(d12: 5, safety: 0, er: 5), EncounterOutcome.none);
    expect(resolveEncounter(d12: 1, safety: 0, er: 5), EncounterOutcome.danger);
    // No natural-1 special case: 1 only triggers via the < ER comparison.
    expect(resolveEncounter(d12: 1, safety: 10, er: 5), EncounterOutcome.none);
  });

  test('baselineSafety stacks night and pace', () {
    expect(baselineSafety(night: false, pace: Pace.normal), 0);
    expect(baselineSafety(night: true, pace: Pace.normal), -2);
    expect(baselineSafety(night: false, pace: Pace.slow), 2);
    expect(baselineSafety(night: false, pace: Pace.fast), -2);
    expect(baselineSafety(night: true, pace: Pace.slow), 0);
    expect(baselineSafety(night: true, pace: Pace.fast), -4);
  });

  test('rolls land in range and map to the right table rows', () {
    // Queue: d12=1 for rollPoi, d10=3 for rollQuickEncounter, d10=7 for rollTerrain.
    // _SeqRandom([1, 3, 7]): nextInt(12) returns (1-1)%12=0 => dN(12)=1
    //                        nextInt(10) returns (3-1)%10=2 => dN(10)=3
    //                        nextInt(10) returns (7-1)%10=6 => dN(10)=7
    final dice = Dice(_SeqRandom([1, 3, 7]));
    expect(rollPoi(dice, data).n, 1);
    final qe = rollQuickEncounter(dice, data);
    expect(qe.n, 3);
    expect(rollTerrain(dice, data).key,
        data.terrain[6].key); // dN(10)=7 -> index 6
  });
}

/// Deterministic RNG: returns (value-1) so Dice.dN(n) yields the queued value.
class _SeqRandom implements Random {
  _SeqRandom(this._values);
  final List<int> _values;
  int _i = 0;
  @override
  int nextInt(int max) {
    final v = _values[_i++ % _values.length];
    return (v - 1) % max; // so Dice.dN returns v
  }

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}
