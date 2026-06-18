import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
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
      );
      expect(ids(s), contains('combat-turn'));
    });

    test('make-move only when ironsworn family AND a focus character', () {
      List<String> run(bool fam, bool foc) => ids(suggestionsFor(
            hasScenes: true,
            hasOpenThreads: false,
            encounterActive: false,
            ironswornFamily: fam,
            hasFocusCharacter: foc,
          ));
      expect(run(true, true), contains('make-move'));
      expect(run(true, false), isNot(contains('make-move')));
      expect(run(false, true), isNot(contains('make-move')));
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
      expect(g.title, 'Fate Check');
      expect(g.rolls.map((x) => x.label), containsAll(['Answer', 'Intensity']));
      expect(g.asText, isNotEmpty);
    });
  });
}
