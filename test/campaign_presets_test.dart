import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  group('kKnownSystems + kSystemCategory', () {
    test('kKnownSystems has the 16 ids', () {
      expect(kKnownSystems, {
        'juice',
        'mythic',
        'ironsworn',
        'party',
        'verdant',
        'lonelog',
        'hexcrawl',
        'dnd',
        'shadowdark',
        'nimble',
        'draw-steel',
        'argosa',
        'cairn',
        'knave',
        'ose',
        'cards',
      });
    });

    test('kAllSystems is a subset of kKnownSystems (and unchanged)', () {
      expect(kAllSystems, {'juice', 'mythic', 'ironsworn', 'party', 'verdant'});
      expect(kKnownSystems.containsAll(kAllSystems), isTrue);
    });

    test('every known system is categorized exactly once', () {
      expect(kSystemCategory.keys.toSet(), kKnownSystems);
    });

    test('9 ruleset systems', () {
      final rulesets = kSystemCategory.entries
          .where((e) => e.value == SystemCategory.ruleset)
          .map((e) => e.key)
          .toSet();
      expect(rulesets, {
        'ironsworn',
        'dnd',
        'shadowdark',
        'nimble',
        'draw-steel',
        'argosa',
        'cairn',
        'knave',
        'ose',
      });
    });

    test('oracle/exploration/tools categories', () {
      Set<String> of(SystemCategory c) => kSystemCategory.entries
          .where((e) => e.value == c)
          .map((e) => e.key)
          .toSet();
      expect(of(SystemCategory.oracle), {'juice', 'mythic', 'cards'});
      expect(of(SystemCategory.exploration), {'verdant', 'hexcrawl'});
      expect(of(SystemCategory.tools), {'party', 'lonelog'});
    });
  });
}
