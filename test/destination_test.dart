import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/shared/destination.dart';

void main() {
  test('landingDestination maps mode to its home verb', () {
    expect(landingDestination(CampaignMode.gm), Destination.run);
    expect(landingDestination(CampaignMode.party), Destination.journal);
  });

  test('toolLocation maps tools to destination + subtab key', () {
    expect(toolLocation['verdant'], (Destination.map, 'journey'));
    expect(toolLocation['encounter'], (Destination.track, 'encounter'));
    expect(toolLocation['tables'], (Destination.ask, 'tables'));
    expect(toolLocation.containsKey('gen-npcs'), isFalse);
    // dice has no tab home (entry line + modal)
    expect(toolLocation.containsKey('dice'), isFalse);
  });

  test('every destination has display metadata', () {
    for (final d in Destination.values) {
      expect(destinationMeta[d], isNotNull);
    }
  });
}
