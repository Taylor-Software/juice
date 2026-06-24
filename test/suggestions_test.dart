import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';
import 'package:juice_oracle/engine/suggestions.dart';

List<String> ids(List<Suggestion> s) => s.map((e) => e.id).toList();

void main() {
  group('suggestionsFor', () {
    test('roll-oracle is always present and first', () {
      final s = suggestionsFor(
        hasScenes: false,
        hasOpenThreads: false,
        encounterActive: false,
        ironswornFamily: false,
        hasFocusCharacter: false,
        partyMode: true,
      );
      expect(s.first.id, 'roll-oracle');
      expect(s.first.action, SuggestionAction.inline);
    });

    test('no scenes → start-scene (navigate), not scene-event', () {
      final s = suggestionsFor(
        hasScenes: false,
        hasOpenThreads: false,
        encounterActive: false,
        ironswornFamily: false,
        hasFocusCharacter: false,
        partyMode: true,
      );
      expect(ids(s), contains('start-scene'));
      expect(ids(s), isNot(contains('scene-event')));
    });

    test('has scenes → scene-event (inline), not start-scene', () {
      final s = suggestionsFor(
        hasScenes: true,
        hasOpenThreads: false,
        encounterActive: false,
        ironswornFamily: false,
        hasFocusCharacter: false,
        partyMode: true,
      );
      expect(ids(s), contains('scene-event'));
      expect(ids(s), isNot(contains('start-scene')));
      expect(s.firstWhere((e) => e.id == 'scene-event').action,
          SuggestionAction.inline);
    });

    test('open threads → advance-thread', () {
      final s = suggestionsFor(
        hasScenes: true,
        hasOpenThreads: true,
        encounterActive: false,
        ironswornFamily: false,
        hasFocusCharacter: false,
        partyMode: true,
      );
      expect(ids(s), contains('advance-thread'));
    });

    test('encounter active → combat-turn', () {
      final s = suggestionsFor(
        hasScenes: true,
        hasOpenThreads: false,
        encounterActive: true,
        ironswornFamily: false,
        hasFocusCharacter: false,
        partyMode: true,
      );
      expect(ids(s), contains('combat-turn'));
    });

    test('make-move only when ironsworn family AND focus character AND party',
        () {
      List<String> run(bool fam, bool foc, bool party) => ids(suggestionsFor(
            hasScenes: true,
            hasOpenThreads: false,
            encounterActive: false,
            ironswornFamily: fam,
            hasFocusCharacter: foc,
            partyMode: party,
          ));
      expect(run(true, true, true), contains('make-move'));
      expect(run(true, false, true), isNot(contains('make-move')));
      expect(run(false, true, true), isNot(contains('make-move')));
      // GM mode hides Moves → no make-move even with family + focus character.
      expect(run(true, true, false), isNot(contains('make-move')));
    });

    test('gm-only suggestions appear in gm mode, hidden in party', () {
      List<String> run(bool party) => ids(suggestionsFor(
            hasScenes: true,
            hasOpenThreads: false,
            encounterActive: false,
            ironswornFamily: false,
            hasFocusCharacter: false,
            partyMode: party,
          ));
      expect(run(false), containsAll(['develop-rumor', 'seed-npc']));
      expect(run(true), isNot(contains('develop-rumor')));
      expect(run(true), isNot(contains('seed-npc')));
    });
  });

  group('applyRanking', () {
    final rule = [
      const Suggestion('a', 'A', SuggestionAction.inline),
      const Suggestion('b', 'B', SuggestionAction.navigate),
      const Suggestion('c', 'C', SuggestionAction.navigate),
    ];

    test('reorders by order, drops unknown ids, appends omitted, trims why',
        () {
      final r = applyRanking(
          rule, const RankResult(order: ['c', 'zzz', 'a'], why: ' do C '));
      expect(r.chips.map((s) => s.id).toList(), ['c', 'a', 'b']);
      expect(r.why, 'do C');
    });

    test('empty result -> rule order, null why', () {
      final r = applyRanking(rule, const RankResult());
      expect(r.chips.map((s) => s.id).toList(), ['a', 'b', 'c']);
      expect(r.why, isNull);
    });

    test('whitespace-only why -> null', () {
      final r = applyRanking(rule, const RankResult(order: ['a'], why: '   '));
      expect(r.why, isNull);
    });

    test('duplicate ids in order are taken once', () {
      final r = applyRanking(rule, const RankResult(order: ['b', 'b', 'a']));
      expect(r.chips.map((s) => s.id).toList(), ['b', 'a', 'c']);
    });
  });

  group('fateCheckGenResult', () {
    test('wraps a FateResult into a journal GenResult', () {
      const r = FateResult(
        primary: 1,
        secondary: 0,
        side: null,
        intensityRoll: 3,
        intensity: 'Moderate',
        likelihood: Likelihood.normal,
        result: 'Yes',
      );
      final g = fateCheckGenResult(r);
      expect(g.title, 'Fate Check (Normal)');
      expect(g.rolls.map((x) => x.label), containsAll(['Answer', 'Intensity']));
      expect(g.asText, isNotEmpty);
    });
  });
}
