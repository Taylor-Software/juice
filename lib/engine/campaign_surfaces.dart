/// One surface row in the preview. `on` is computed; `requiresSystem` is the
/// authored gate (kept as data so a test can validate every system gate against
/// kKnownSystems — no drift).
class SurfaceRow {
  const SurfaceRow(this.name, {this.requiresSystem});
  final String name;
  final String? requiresSystem;

  bool on(Set<String> systems) {
    return requiresSystem == null || systems.contains(requiresSystem);
  }
}

/// A verb (top-level destination) and its computed surface rows.
class VerbSurfaces {
  const VerbSurfaces(this.verb, this.rows);
  final String verb;
  final List<({String name, bool on, String? requiresSystem})> rows;
}

/// Authored surface table — the single source the live preview reads. System
/// gates are validated against kKnownSystems by a test.
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
    SurfaceRow('Embark 2E sheet', requiresSystem: 'embark'),
    SurfaceRow('OSE / B/X sheet', requiresSystem: 'ose'),
    SurfaceRow('Kal-Arath sheet', requiresSystem: 'kal-arath'),
    SurfaceRow('Custom / Homebrew sheet', requiresSystem: 'custom'),
    SurfaceRow('Dungeon Crawl Classics sheet', requiresSystem: 'dcc'),
    SurfaceRow('0-Level Funnel', requiresSystem: 'funnel'),
    SurfaceRow('Moves', requiresSystem: 'ironsworn'),
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
    SurfaceRow('Classic dungeon crawl', requiresSystem: 'classic-dungeon'),
  ],
  'Track': [
    SurfaceRow('Scenes / threads / tracks'),
    SurfaceRow('Encounter'),
    SurfaceRow('Rumors'),
    SurfaceRow('Party emulator', requiresSystem: 'party'),
    SurfaceRow('Sidekick', requiresSystem: 'party'),
    SurfaceRow('NPC behavior', requiresSystem: 'party'),
    SurfaceRow('Lonelog resources / battle', requiresSystem: 'lonelog'),
  ],
};

/// The 5 verbs in shell order.
const _verbOrder = ['Journal', 'Sheet', 'Ask', 'Map', 'Track'];

/// Resolves the surface visibility for a systems set.
List<VerbSurfaces> surfacesFor(Set<String> systems) {
  return [
    for (final verb in _verbOrder)
      VerbSurfaces(verb, [
        for (final row in _table[verb]!)
          (
            name: row.name,
            on: row.on(systems),
            requiresSystem: row.requiresSystem,
          ),
      ]),
  ];
}

/// Capability groups where enabling more than one member stacks overlapping
/// UI for the same job. The dialogs render each group as a radio row, and
/// [normalizeExclusive] resolves a both-on legacy set by keeping the FIRST
/// member listed here. Gates elsewhere stay tolerant of both-on sets.
const Map<String, List<String>> kExclusiveGroups = {
  'hex-flavor': ['verdant', 'hexcrawl'],
};

/// Every system id that belongs to some exclusive group — the dialogs skip
/// these in their plain checkbox/filter loops.
final Set<String> kExclusiveSystemIds =
    kExclusiveGroups.values.expand((m) => m).toSet();

/// Keeps at most one member per exclusive group (the first listed), leaving
/// everything else untouched.
Set<String> normalizeExclusive(Set<String> systems) {
  final out = {...systems};
  for (final members in kExclusiveGroups.values) {
    final present = members.where(out.contains).toList();
    if (present.length > 1) {
      out.removeAll(present);
      out.add(present.first);
    }
  }
  return out;
}
