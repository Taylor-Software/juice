import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/generators_screen.dart';

void main() {
  test('every generator belongs to exactly one section', () {
    final seen = <String>{};
    for (final s in GenSection.values) {
      for (final label in GeneratorsScreen.labelsFor(s)) {
        expect(seen.add(label), isTrue, reason: '$label in two sections');
      }
    }
    expect(seen.length, greaterThanOrEqualTo(28));
  });

  test('section labels cover the activity taxonomy', () {
    expect(
        GenSection.values.map((s) => s.label),
        containsAll([
          'Story & Scenes',
          'NPCs & Dialog',
          'Exploration',
          'Encounters & Combat',
          'Names & Details',
        ]));
  });
}
