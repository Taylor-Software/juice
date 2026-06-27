import 'models.dart';
import 'role_tags.dart';

/// One surface row in the preview. `on` is computed; `requiresSystem` /
/// `requiresModeKey` are the authored gates (kept as data so a test can
/// validate every system gate against kKnownSystems — no drift).
class SurfaceRow {
  const SurfaceRow(this.name, {this.requiresSystem, this.requiresModeKey});
  final String name;
  final String? requiresSystem;
  final String? requiresModeKey; // a visibleForMode key (role_tags)

  bool on(CampaignMode mode, Set<String> systems) {
    final sysOk = requiresSystem == null || systems.contains(requiresSystem);
    final modeOk =
        requiresModeKey == null || visibleForMode(requiresModeKey!, mode);
    return sysOk && modeOk;
  }
}

/// A verb (top-level destination) and its computed surface rows.
class VerbSurfaces {
  const VerbSurfaces(this.verb, this.rows);
  final String verb;
  final List<({String name, bool on, String? requiresSystem})> rows;
}

/// Authored surface table — the single source the live preview reads. Mode
/// gates call the real `visibleForMode`; system gates are validated against
/// kKnownSystems by a test.
const _table = <String, List<SurfaceRow>>{
  'Journal': [
    SurfaceRow('Entries + composer'),
    SurfaceRow('Assistant rail'),
  ],
  'Sheet': [
    SurfaceRow('Character roster'),
    SurfaceRow('Ironsworn / Starforged', requiresSystem: 'ironsworn'),
    SurfaceRow('D&D 5e sheet', requiresSystem: 'dnd'),
    SurfaceRow('Shadowdark sheet', requiresSystem: 'shadowdark'),
    SurfaceRow('Nimble sheet', requiresSystem: 'nimble'),
    SurfaceRow('Draw Steel sheet', requiresSystem: 'draw-steel'),
    SurfaceRow('Argosa sheet', requiresSystem: 'argosa'),
    SurfaceRow('Cairn sheet', requiresSystem: 'cairn'),
    SurfaceRow('Knave sheet', requiresSystem: 'knave'),
    SurfaceRow('OSE / B/X sheet', requiresSystem: 'ose'),
    SurfaceRow('Kal-Arath sheet', requiresSystem: 'kal-arath'),
    SurfaceRow('Dungeon Crawl Classics sheet', requiresSystem: 'dcc'),
    SurfaceRow('0-Level Funnel', requiresSystem: 'funnel'),
    SurfaceRow('Moves', requiresSystem: 'ironsworn', requiresModeKey: 'moves'),
  ],
  'Ask': [
    SurfaceRow('Juice oracle', requiresSystem: 'juice'),
    SurfaceRow('Mythic GME', requiresSystem: 'mythic'),
    SurfaceRow('Cards / tarot / spreads', requiresSystem: 'cards'),
    SurfaceRow('Lonelog legend', requiresSystem: 'lonelog'),
    SurfaceRow('Generators'),
  ],
  'Map': [
    SurfaceRow('Region / dungeon map'),
    SurfaceRow('Verdant Journey', requiresSystem: 'verdant'),
    SurfaceRow('Hexcrawl toolkit', requiresSystem: 'hexcrawl'),
  ],
  'Track': [
    SurfaceRow('Scenes / threads / tracks'),
    SurfaceRow('Encounter'),
    SurfaceRow('Rumors', requiresModeKey: 'rumors'),
    SurfaceRow('Party emulator',
        requiresSystem: 'party', requiresModeKey: 'emulator'),
    SurfaceRow('Sidekick',
        requiresSystem: 'party', requiresModeKey: 'sidekick'),
    SurfaceRow('NPC behavior',
        requiresSystem: 'party', requiresModeKey: 'behavior'),
    SurfaceRow('Lonelog resources / battle', requiresSystem: 'lonelog'),
  ],
};

/// The 5 verbs in shell order.
const _verbOrder = ['Journal', 'Sheet', 'Ask', 'Map', 'Track'];

/// Resolves the surface visibility for a (mode, systems) pair.
List<VerbSurfaces> surfacesFor(CampaignMode mode, Set<String> systems) {
  return [
    for (final verb in _verbOrder)
      VerbSurfaces(verb, [
        for (final row in _table[verb]!)
          (
            name: row.name,
            on: row.on(mode, systems),
            requiresSystem: row.requiresSystem,
          ),
      ]),
  ];
}
