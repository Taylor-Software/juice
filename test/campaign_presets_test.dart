import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/campaign_presets.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  group('kKnownSystems + kSystemCategory', () {
    test('kKnownSystems has the 21 ids', () {
      expect(kKnownSystems, {
        'juice',
        'mythic',
        'ironsworn',
        'party',
        'verdant',
        'lonelog',
        'hexcrawl',
        'classic-dungeon',
        'dnd',
        'shadowdark',
        'nimble',
        'draw-steel',
        'argosa',
        'cairn',
        'knave',
        'ose',
        'kal-arath',
        'dcc',
        'funnel',
        'cards',
        'custom',
      });
    });

    test('kAllSystems is a subset of kKnownSystems (and unchanged)', () {
      expect(kAllSystems, {'juice', 'mythic', 'ironsworn', 'party', 'verdant'});
      expect(kKnownSystems.containsAll(kAllSystems), isTrue);
    });

    test('every known system is categorized exactly once', () {
      expect(kSystemCategory.keys.toSet(), kKnownSystems);
    });

    test('12 ruleset systems', () {
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
        'kal-arath',
        'dcc',
        'custom',
      });
    });

    test('oracle/exploration/tools categories', () {
      Set<String> of(SystemCategory c) => kSystemCategory.entries
          .where((e) => e.value == c)
          .map((e) => e.key)
          .toSet();
      expect(of(SystemCategory.oracle), {'juice', 'mythic', 'cards'});
      expect(of(SystemCategory.exploration),
          {'verdant', 'hexcrawl', 'classic-dungeon'});
      expect(of(SystemCategory.tools), {'party', 'lonelog', 'funnel'});
    });
  });

  group('kCampaignPresets', () {
    test('every preset references only known systems', () {
      for (final p in kCampaignPresets) {
        for (final s in p.systems) {
          expect(kKnownSystems.contains(s), isTrue, reason: '${p.id}: $s');
        }
      }
    });

    test('solo-* presets are party mode with juice + party', () {
      final soloPresets =
          kCampaignPresets.where((p) => p.id.startsWith('solo-'));
      expect(soloPresets.length, 13);
      for (final p in soloPresets) {
        expect(p.mode, CampaignMode.party, reason: p.id);
        expect(p.systems.contains('juice'), isTrue, reason: p.id);
        expect(p.systems.contains('party'), isTrue, reason: p.id);
      }
    });

    test('solo-* presets have exactly one ruleset', () {
      final soloPresets =
          kCampaignPresets.where((p) => p.id.startsWith('solo-'));
      for (final p in soloPresets) {
        final rulesets = p.systems
            .where((s) => kSystemCategory[s] == SystemCategory.ruleset);
        expect(rulesets.length, 1, reason: p.id);
      }
    });

    test('shape presets: oracle (party) and gm-toolkit (gm)', () {
      final oracle = kCampaignPresets.firstWhere((p) => p.id == 'oracle');
      expect(oracle.mode, CampaignMode.party);
      expect(oracle.systems, {'juice', 'mythic', 'cards', 'party'});
      final gm = kCampaignPresets.firstWhere((p) => p.id == 'gm-toolkit');
      expect(gm.mode, CampaignMode.gm);
      expect(gm.systems, {'juice', 'mythic'});
    });

    test('preset ids are unique', () {
      final ids = kCampaignPresets.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every preset has a non-empty kind and blurb', () {
      for (final p in kCampaignPresets) {
        expect(p.kind.trim(), isNotEmpty, reason: '${p.id}.kind');
        expect(p.blurb.trim(), isNotEmpty, reason: '${p.id}.blurb');
      }
    });

    test('presetConfig returns the preset mode + systems', () {
      final p = kCampaignPresets.firstWhere((p) => p.id == 'solo-cairn');
      final (mode, systems) = presetConfig(p);
      expect(mode, CampaignMode.party);
      expect(systems, {'cairn', 'juice', 'party'});
    });
  });
}
