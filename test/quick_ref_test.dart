// test/quick_ref_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/quick_ref.dart';

void main() {
  group('resolveSystemQuickRef', () {
    test('priority: dnd wins, cairn resolves, ironsworn-family shares a card', () {
      expect(resolveSystemQuickRef({'dnd', 'ironsworn'}, {})?.system, 'dnd');
      expect(resolveSystemQuickRef({'cairn'}, {})?.system, 'cairn');
      // starforged/sundered_isles rulesets resolve to the ironsworn card
      final sf = resolveSystemQuickRef({'ironsworn'}, {'starforged'});
      expect(sf, isNotNull);
      expect(sf, same(kSystemQuickRefs['ironsworn']));
    });

    test('null when the resolved system has no card', () {
      expect(resolveSystemQuickRef({'lonelog'}, {}), isNull); // no card
      expect(resolveSystemQuickRef({}, {}), isNull);
    });
  });

  group('kSystemQuickRefs content integrity', () {
    test('each card is well-formed (drop-in guard)', () {
      kSystemQuickRefs.forEach((key, card) {
        expect(card.title.trim(), isNotEmpty, reason: '$key title');
        expect(card.sections.length, greaterThanOrEqualTo(3),
            reason: '$key needs >= 3 sections');
        for (final s in card.sections) {
          expect(s.title.trim(), isNotEmpty, reason: '$key section title');
          expect(s.lines, isNotEmpty, reason: '$key section "${s.title}" lines');
          expect(s.lines.every((l) => l.trim().isNotEmpty), isTrue,
              reason: '$key section "${s.title}" has an empty line');
        }
      });
    });

    test('all covered systems are present (ironsworn under 3 keys)', () {
      for (final k in [
        'argosa', 'cairn', 'knave', 'ose', 'kal-arath', 'dnd', 'ironsworn',
        'starforged', 'sundered_isles', 'shadowdark', 'nimble', 'draw-steel',
        'dcc',
      ]) {
        expect(kSystemQuickRefs.containsKey(k), isTrue, reason: k);
      }
    });
  });
}
