import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/generator_registry.dart';

void main() {
  test('registry holds all 28 generators', () {
    expect(kGenerators.length, 28);
  });

  test('flavorGenerators excludes exactly the 4 entity generators', () {
    final flavorLabels = flavorGenerators.map((g) => g.label).toSet();
    for (final entity in ['NPC', 'New Scene', 'Monster Encounter', 'Name']) {
      expect(flavorLabels.contains(entity), isFalse,
          reason: '$entity excluded');
    }
    expect(flavorGenerators.length, 24);
  });

  test('sourceToolFor maps sections to gen-* ids', () {
    expect(sourceToolFor(GenSection.story), 'gen-story');
    expect(sourceToolFor(GenSection.details), 'gen-details');
  });
}
