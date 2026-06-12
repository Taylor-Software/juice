import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/engine/party_emulator.dart';

void main() {
  final data = EmulatorData(
      jsonDecode(File('assets/emulator_data.json').readAsStringSync())
          as Map<String, dynamic>);

  test('rollD66 reads two d6 as tens then units and reaches all 36 keys', () {
    final dice = Dice(Random(42));
    final seen = <int>{};
    for (var i = 0; i < 5000; i++) {
      final r = rollD66(dice);
      expect(r.tens, inInclusiveRange(1, 6));
      expect(r.units, inInclusiveRange(1, 6));
      expect(r.key, r.tens * 10 + r.units);
      seen.add(r.key);
    }
    expect(seen.length, 36);
  });

  test('rollD66 is deterministic under a seeded Dice', () {
    List<int> run() {
      final dice = Dice(Random(7));
      return [for (var i = 0; i < 50; i++) rollD66(dice).key];
    }

    expect(run(), run());
  });

  test('rollBehavior returns table, key, and the matching cell text', () {
    final dice = Dice(Random(1));
    for (var i = 0; i < 500; i++) {
      final r = rollBehavior(data, 'combat', dice);
      expect(r.table, 'combat');
      expect(r.text, data.d66Entry('combat', r.key));
    }
  });

  test('rollBehavior covers all 13 spark + specific tables', () {
    final dice = Dice(Random(2));
    for (final name in [...data.sparkNames, ...data.specificNames]) {
      final r = rollBehavior(data, name, dice);
      expect(r.table, name);
      expect(r.text, data.d66Entry(name, r.key));
    }
  });

  test('rollBehavior throws on an unknown table', () {
    expect(
        () => rollBehavior(data, 'nope', Dice(Random(3))), throwsArgumentError);
  });

  test('rollCombo rolls each named table in order', () {
    final results = rollCombo(data, ['action', 'focus'], Dice(Random(4)));
    expect(results, hasLength(2));
    expect(results[0].table, 'action');
    expect(results[1].table, 'focus');
    for (final r in results) {
      expect(r.text, data.d66Entry(r.table, r.key));
    }
  });

  test('rollCombo is deterministic under the same seed', () {
    List<int> run() => [
          for (final r
              in rollCombo(data, ['action', 'method'], Dice(Random(9))))
            r.key,
        ];
    expect(run(), run());
  });

  test('bandFor maps 4-6 obvious, 2-3 option, 1 odd', () {
    expect(bandFor(1), TripleOBand.odd);
    expect(bandFor(2), TripleOBand.option);
    expect(bandFor(3), TripleOBand.option);
    expect(bandFor(4), TripleOBand.obvious);
    expect(bandFor(5), TripleOBand.obvious);
    expect(bandFor(6), TripleOBand.obvious);
  });

  test('band labels carry the zine article', () {
    expect(TripleOBand.obvious.label, 'The Obvious');
    expect(TripleOBand.option.label, 'The Option');
    expect(TripleOBand.odd.label, 'The Odd');
  });

  test('rollTripleO is a single die with a decided band', () {
    final r = rollTripleO(Dice(Random(7))); // first d6 = 5
    expect(r.die, 5);
    expect(r.dice, isNull);
    expect(r.isDoubles, isFalse);
    expect(r.band, TripleOBand.obvious);
  });

  test('rollDoubleDown rolls both dice and decides no band', () {
    final r = rollDoubleDown(Dice(Random(5))); // rolls 5, 1
    expect(r.die, isNull);
    expect(r.dice, (5, 1));
    expect(r.band, isNull, reason: 'the player picks the favorite die');
    expect(r.isDoubles, isFalse);
  });

  test('double-down doubles are flagged for trait growth', () {
    expect(rollDoubleDown(Dice(Random(2))).isDoubles, isTrue); // rolls 4, 4
    final dice = Dice(Random(11));
    var seenDoubles = false, seenDistinct = false;
    for (var i = 0; i < 200; i++) {
      final r = rollDoubleDown(dice);
      expect(r.isDoubles, r.dice!.$1 == r.dice!.$2);
      r.isDoubles ? seenDoubles = true : seenDistinct = true;
    }
    expect(seenDoubles, isTrue);
    expect(seenDistinct, isTrue);
  });

  test('assignOrder ranks courses highest→obvious; ties keep list order', () {
    expect(assignOrder([1, 2, 3]), [2, 1, 0]);
    expect(assignOrder([6, 5, 4]), [0, 1, 2]);
    expect(assignOrder([4, 4, 2]), [0, 1, 2]); // tie: earlier keeps obvious
    expect(assignOrder([2, 5, 5]), [1, 2, 0]); // tie: earlier keeps obvious
    expect(assignOrder([3, 3, 3]), [0, 1, 2]); // triple tie: list order
  });

  test('roll2d6Key sums two d6: curved range 2-12, deterministic', () {
    final dice = Dice(Random(13));
    final seen = <int>{};
    for (var i = 0; i < 200; i++) {
      final k = roll2d6Key(dice);
      expect(k, inInclusiveRange(2, 12));
      seen.add(k);
    }
    expect(seen.length, 11, reason: '200 curved rolls reach all keys 2-12');
    List<int> run() {
      final d = Dice(Random(21));
      return [for (var i = 0; i < 50; i++) roll2d6Key(d)];
    }

    expect(run(), run());
    // Arity pin: the key is the sum of exactly the first two d6.
    final probe = Dice(Random(3));
    expect(roll2d6Key(Dice(Random(3))), probe.dN(6) + probe.dN(6));
  });

  test('rollAct draws agenda 2d6, then coin d2, then modifier d6', () {
    for (var seed = 0; seed < 20; seed++) {
      // Probe replays the documented dice order on the same seed; any
      // reordering or extra draw in rollAct would desynchronize the stream.
      final probe = Dice(Random(seed));
      final key = probe.dN(6) + probe.dN(6);
      final heads = probe.dN(2) == 1;
      final mod = probe.dN(6);
      final r = rollAct(Dice(Random(seed)));
      expect(r.agendaKey, key, reason: 'seed $seed');
      expect(r.heads, heads, reason: 'seed $seed');
      expect(r.modifierDie, mod, reason: 'seed $seed');
    }
  });

  test('rollAct stays in range and shows both coin faces over 200 rolls', () {
    final dice = Dice(Random(99));
    var headsSeen = false, tailsSeen = false;
    for (var i = 0; i < 200; i++) {
      final r = rollAct(dice);
      expect(r.agendaKey, inInclusiveRange(2, 12));
      expect(r.modifierDie, inInclusiveRange(1, 6));
      r.heads ? headsSeen = true : tailsSeen = true;
    }
    expect(headsSeen, isTrue);
    expect(tailsSeen, isTrue);
  });

  test('modifier die bands 1-2 as written, 3-4 inverted, 5-6 exaggerated', () {
    ActMode modeFor(int die) =>
        ActResult(agendaKey: 7, heads: true, modifierDie: die).modifier;
    expect(modeFor(1), ActMode.asWritten);
    expect(modeFor(2), ActMode.asWritten);
    expect(modeFor(3), ActMode.inverted);
    expect(modeFor(4), ActMode.inverted);
    expect(modeFor(5), ActMode.exaggerated);
    expect(modeFor(6), ActMode.exaggerated);
  });

  test('actModeLabel renders the guidance wording', () {
    expect(actModeLabel(ActMode.asWritten), 'as written');
    expect(actModeLabel(ActMode.inverted), 'inverted');
    expect(actModeLabel(ActMode.exaggerated), 'exaggerated');
  });

  test('rollDialogue dice order: 2d6 line, doubles mood+reroll, four chips',
      () {
    for (var seed = 0; seed < 30; seed++) {
      // Probe replays the documented order on the same seed (rollAct
      // pattern): 2d6 line → if doubles: d6 mood + 2d6 reroll → d6 tone →
      // d6 topic → d6 saidHowA → d6 saidHowB. Any reordering or extra draw
      // in rollDialogue would desynchronize the stream.
      final probe = Dice(Random(seed));
      final a = probe.dN(6), b = probe.dN(6);
      String? newMood;
      var lineKey = a + b;
      if (a == b) {
        newMood = kSidekickMoods[probe.dN(6) - 1];
        lineKey = probe.dN(6) + probe.dN(6);
      }
      final toneIx = probe.dN(6) - 1;
      final topicIx = probe.dN(6) - 1;
      final saidHowAIx = probe.dN(6) - 1;
      final saidHowBIx = probe.dN(6) - 1;
      final r = rollDialogue(Dice(Random(seed)));
      expect(r.dice, (a, b), reason: 'seed $seed');
      expect(r.moodChanged, a == b, reason: 'seed $seed');
      expect(r.newMood, newMood, reason: 'seed $seed');
      expect(r.lineKey, lineKey, reason: 'seed $seed');
      expect(r.toneIx, toneIx, reason: 'seed $seed');
      expect(r.topicIx, topicIx, reason: 'seed $seed');
      expect(r.saidHowAIx, saidHowAIx, reason: 'seed $seed');
      expect(r.saidHowBIx, saidHowBIx, reason: 'seed $seed');
    }
  });

  test('rollDialogue non-doubles keeps the mood and sums the line dice', () {
    final r = rollDialogue(Dice(Random(7))); // rolls 5 & 6
    expect(r.dice, (5, 6));
    expect(r.moodChanged, isFalse);
    expect(r.newMood, isNull);
    expect(r.lineKey, 11);
  });

  test('rollDialogue doubles changes the mood first, then rerolls the line',
      () {
    final r = rollDialogue(Dice(Random(2))); // rolls 4 & 4
    expect(r.dice, (4, 4));
    expect(r.moodChanged, isTrue);
    // Probe-derived: the mood d6, then the 2d6 reroll.
    final probe = Dice(Random(2))
      ..dN(6)
      ..dN(6);
    expect(r.newMood, kSidekickMoods[probe.dN(6) - 1]);
    expect(r.lineKey, probe.dN(6) + probe.dN(6));
  });

  test('rollDialogue ranges: keys 2-12, chip indices 0-5, both mood paths', () {
    final dice = Dice(Random(31));
    var changed = false, kept = false;
    final tones = <int>{}, topics = <int>{}, saidA = <int>{}, saidB = <int>{};
    for (var i = 0; i < 300; i++) {
      final r = rollDialogue(dice);
      expect(r.lineKey, inInclusiveRange(2, 12));
      if (r.moodChanged) {
        expect(kSidekickMoods, contains(r.newMood));
        changed = true;
      } else {
        kept = true;
      }
      tones.add(r.toneIx);
      topics.add(r.topicIx);
      saidA.add(r.saidHowAIx);
      saidB.add(r.saidHowBIx);
    }
    expect(changed, isTrue);
    expect(kept, isTrue);
    for (final seen in [tones, topics, saidA, saidB]) {
      expect(seen.toList()..sort(), [0, 1, 2, 3, 4, 5]);
    }
  });

  test('assignCourses orders courses by three d6, ties deterministic', () {
    // Seed 0 rolls [4, 6, 5]: course 1 highest, then 2, then 0.
    expect(assignCourses(Dice(Random(0))), [1, 2, 0]);
    // Seed 2 rolls [4, 4, 5]: 5 takes obvious; the tied 4s keep list order.
    expect(assignCourses(Dice(Random(2))), [2, 0, 1]);
    // Seed 4 rolls [1, 4, 4]: tied 4s take obvious/option in list order.
    expect(assignCourses(Dice(Random(4))), [1, 2, 0]);
    for (var s = 0; s < 30; s++) {
      expect(assignCourses(Dice(Random(s)))..sort(), [0, 1, 2],
          reason: 'seed $s must yield a permutation of 0-2');
    }
  });
}
