import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/campaign_surfaces.dart';

void main() {
  Map<String, bool> flat(CampaignMode mode, Set<String> systems) {
    final out = <String, bool>{};
    for (final v in surfacesFor(mode, systems)) {
      for (final r in v.rows) {
        out['${v.verb}/${r.name}'] = r.on;
      }
    }
    return out;
  }

  test('every authored system gate is a known system (no drift)', () {
    for (final v in surfacesFor(CampaignMode.party, const {})) {
      for (final r in v.rows) {
        if (r.requiresSystem != null) {
          expect(kKnownSystems.contains(r.requiresSystem), isTrue,
              reason: '${v.verb}/${r.name} → ${r.requiresSystem}');
        }
      }
    }
  });

  test('empty systems: only always-on rows are on', () {
    final f = flat(CampaignMode.party, const {});
    expect(f['Sheet/Character roster'], isTrue);
    expect(f['Sheet/D&D 5e sheet'], isFalse);
    expect(f['Ask/Juice oracle'], isFalse);
    expect(f['Map/Region / dungeon map'], isTrue);
    expect(f['Track/Encounter'], isTrue);
  });

  test('cairn party campaign lights the Cairn sheet only', () {
    final f = flat(CampaignMode.party, {'cairn', 'juice', 'party'});
    expect(f['Sheet/Cairn sheet'], isTrue);
    expect(f['Sheet/D&D 5e sheet'], isFalse);
    expect(f['Ask/Juice oracle'], isTrue);
    expect(f['Track/Party emulator'], isTrue);
  });

  test('party vs gm mode flips Rumors and party tools', () {
    final party = flat(CampaignMode.party, {'party'});
    expect(party['Track/Rumors'], isFalse);
    expect(party['Track/Party emulator'], isTrue);
    final gm = flat(CampaignMode.gm, {'party'});
    expect(gm['Track/Rumors'], isTrue);
    expect(gm['Track/Party emulator'], isFalse);
  });

  test('Moves needs ironsworn AND party mode', () {
    expect(flat(CampaignMode.party, {'ironsworn'})['Sheet/Moves'], isTrue);
    expect(flat(CampaignMode.gm, {'ironsworn'})['Sheet/Moves'], isFalse);
    expect(flat(CampaignMode.party, const {})['Sheet/Moves'], isFalse);
  });

  test('surfacesFor returns the 5 verbs in order', () {
    final verbs = surfacesFor(CampaignMode.party, const {}).map((v) => v.verb);
    expect(verbs, ['Journal', 'Sheet', 'Ask', 'Map', 'Track']);
  });
}
