import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/campaign_surfaces.dart';

void main() {
  Map<String, bool> flat(Set<String> systems) {
    final out = <String, bool>{};
    for (final v in surfacesFor(systems)) {
      for (final r in v.rows) {
        out['${v.verb}/${r.name}'] = r.on;
      }
    }
    return out;
  }

  test('every authored system gate is a known system (no drift)', () {
    for (final v in surfacesFor(const {})) {
      for (final r in v.rows) {
        if (r.requiresSystem != null) {
          expect(kKnownSystems.contains(r.requiresSystem), isTrue,
              reason: '${v.verb}/${r.name} → ${r.requiresSystem}');
        }
      }
    }
  });

  test('empty systems: only always-on rows are on', () {
    final f = flat(const {});
    expect(f['Sheet/Character roster'], isTrue);
    expect(f['Sheet/D&D 5e sheet'], isFalse);
    expect(f['Ask/Juice oracle'], isFalse);
    expect(f['Map/Region / dungeon map'], isTrue);
    expect(f['Track/Encounter'], isTrue);
  });

  test('cairn + juice + party campaign lights the correct rows', () {
    final f = flat({'cairn', 'juice', 'party'});
    expect(f['Sheet/Cairn sheet'], isTrue);
    expect(f['Sheet/D&D 5e sheet'], isFalse);
    expect(f['Ask/Juice oracle'], isTrue);
    expect(f['Track/Party emulator'], isTrue);
  });

  test('Rumors is always on (no mode gate)', () {
    expect(flat(const {})['Track/Rumors'], isTrue);
    expect(flat({'party'})['Track/Rumors'], isTrue);
  });

  test('party tools gated by party system only', () {
    expect(flat(const {})['Track/Party emulator'], isFalse);
    expect(flat({'party'})['Track/Party emulator'], isTrue);
  });

  test('Moves needs ironsworn system only (no mode gate)', () {
    expect(flat({'ironsworn'})['Sheet/Moves'], isTrue);
    expect(flat(const {})['Sheet/Moves'], isFalse);
  });

  test('surfacesFor returns the 5 verbs in order', () {
    final verbs = surfacesFor(const {}).map((v) => v.verb);
    expect(verbs, ['Journal', 'Sheet', 'Ask', 'Map', 'Track']);
  });
}
