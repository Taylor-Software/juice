import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/destination.dart';

void main() {
  test('toolLocation maps tools to destination + subtab key', () {
    expect(toolLocation['verdant'], (Destination.maps, 'journey'));
    expect(toolLocation['encounter'], (Destination.tracking, 'encounter'));
    expect(toolLocation['tables'], (Destination.oracles, 'tables'));
    expect(toolLocation['gen-npcs'], (Destination.oracles, 'generators'));
    // dice has no tab home (entry line + modal)
    expect(toolLocation.containsKey('dice'), isFalse);
  });

  test('every destination has display metadata', () {
    for (final d in Destination.values) {
      expect(destinationMeta[d], isNotNull);
    }
  });
}
