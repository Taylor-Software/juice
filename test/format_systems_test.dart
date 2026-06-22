import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  group('formatSystems', () {
    test('leads with the distinctive sheet systems', () {
      expect(formatSystems({'mythic', 'dnd'}), 'D&D · Mythic');
      expect(formatSystems({'juice', 'shadowdark'}), 'Shadowdark · Juice');
    });

    test('the default profile lists all base systems in order', () {
      expect(formatSystems(kAllSystems),
          'Ironsworn · Mythic · Juice · Party · Verdant');
    });

    test('empty set is empty; unknown keys keep their raw id', () {
      expect(formatSystems({}), '');
      expect(formatSystems({'dnd', 'wat'}), 'D&D · wat');
    });
  });
}
