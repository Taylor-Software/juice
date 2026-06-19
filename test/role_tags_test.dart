import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/role_tags.dart';

void main() {
  group('visibleForMode', () {
    test('untagged keys are always visible', () {
      expect(visibleForMode('scenes', CampaignMode.gm), isTrue);
      expect(visibleForMode('scenes', CampaignMode.party), isTrue);
      expect(visibleForMode('encounter', CampaignMode.party), isTrue);
    });
    test('rumors is gm-only', () {
      expect(visibleForMode('rumors', CampaignMode.gm), isTrue);
      expect(visibleForMode('rumors', CampaignMode.party), isFalse);
    });
    test('party tools + moves are party-only', () {
      for (final k in ['emulator', 'sidekick', 'behavior', 'moves']) {
        expect(visibleForMode(k, CampaignMode.party), isTrue, reason: k);
        expect(visibleForMode(k, CampaignMode.gm), isFalse, reason: k);
      }
    });
  });
}
