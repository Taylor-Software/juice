import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/spell.dart';

void main() {
  test('round-trips through json', () {
    const s = SpellEntry(
      id: 'dnd-fireball', system: 'dnd', edition: '5.1', name: 'Fireball',
      level: 3, school: 'Evocation', castingTime: '1 action', range: '150 feet',
      components: 'V, S, M', duration: 'Instantaneous', concentration: false,
      ritual: false, classes: ['Sorcerer', 'Wizard'],
      description: 'A bright streak flashes...', higherLevels: 'At higher levels...',
    );
    final back = SpellEntry.maybeFromJson(s.toJson());
    expect(back, isNotNull);
    expect(back!.name, 'Fireball');
    expect(back.level, 3);
    expect(back.classes, ['Sorcerer', 'Wizard']);
    expect(back.edition, '5.1');
    expect(back.higherLevels, 'At higher levels...');
  });

  test('tolerant: missing id or name returns null', () {
    expect(SpellEntry.maybeFromJson({'name': 'X'}), isNull);
    expect(SpellEntry.maybeFromJson({'id': 'x'}), isNull);
    expect(SpellEntry.maybeFromJson('not a map'), isNull);
  });

  test('tolerant: defaults for absent optional fields', () {
    final s = SpellEntry.maybeFromJson({'id': 'a', 'name': 'A'})!;
    expect(s.level, 0);
    expect(s.classes, isEmpty);
    expect(s.concentration, isFalse);
    expect(s.edition, isNull);
    expect(s.higherLevels, isNull);
  });
}
