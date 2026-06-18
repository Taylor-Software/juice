import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/system_primer.dart';

void main() {
  group('resolveSystemPrimer', () {
    test('dnd wins over a co-enabled ironsworn', () {
      final p = resolveSystemPrimer({'ironsworn', 'dnd'}, {'classic'});
      expect(p, kSystemPrimers['dnd']);
    });

    test('shadowdark wins over ironsworn', () {
      final p = resolveSystemPrimer({'ironsworn', 'shadowdark'}, {'classic'});
      expect(p, kSystemPrimers['shadowdark']);
    });

    test('ironsworn family refined by ruleset: sundered_isles', () {
      final p =
          resolveSystemPrimer({'ironsworn'}, {'classic', 'sundered_isles'});
      expect(p, kSystemPrimers['sundered_isles']);
    });

    test('ironsworn family refined by ruleset: starforged', () {
      final p = resolveSystemPrimer({'ironsworn'}, {'starforged'});
      expect(p, kSystemPrimers['starforged']);
    });

    test('ironsworn alone -> classic Ironsworn primer', () {
      final p = resolveSystemPrimer({'ironsworn'}, {'classic'});
      expect(p, kSystemPrimers['ironsworn']);
    });

    test('sundered_isles outranks starforged when both rulesets on', () {
      final p =
          resolveSystemPrimer({'ironsworn'}, {'starforged', 'sundered_isles'});
      expect(p, kSystemPrimers['sundered_isles']);
    });

    test('no covered system -> empty string', () {
      expect(resolveSystemPrimer({'juice', 'mythic', 'party'}, {}), '');
      expect(resolveSystemPrimer({}, {}), '');
    });
  });

  group('kSystemPrimers', () {
    test('every primer is non-empty and within the budget cap', () {
      expect(kSystemPrimers, isNotEmpty);
      for (final entry in kSystemPrimers.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
        expect(entry.value.length, lessThanOrEqualTo(kSystemPrimerMaxChars),
            reason: '${entry.key} exceeds kSystemPrimerMaxChars');
      }
    });

    test('covers the five sheet systems', () {
      expect(
          kSystemPrimers.keys,
          containsAll([
            'ironsworn',
            'starforged',
            'sundered_isles',
            'dnd',
            'shadowdark'
          ]));
    });
  });
}
