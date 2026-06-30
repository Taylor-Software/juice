import 'models.dart';
import 'spell.dart';

enum ContentType { all, monsters, spells, rules }

class ContentResults {
  const ContentResults({required this.monsters, required this.spells});
  final List<Creature> monsters;
  final List<SpellEntry> spells;
}

/// Pure search over already-loaded content. Case-insensitive substring match on
/// name (plus monster type / spell school). Empty query returns all (filtered).
ContentResults searchContent({
  required String query,
  required ContentType filter,
  String? system,
  List<Creature> monsters = const [],
  List<SpellEntry> spells = const [],
}) {
  final q = query.trim().toLowerCase();
  bool monsterMatch(Creature c) {
    if (system != null && _monsterSystem(c) != system) return false;
    if (q.isEmpty) return true;
    return c.name.toLowerCase().contains(q) ||
        (c.statBlock.creatureType?.toLowerCase().contains(q) ?? false);
  }

  bool spellMatch(SpellEntry s) {
    if (system != null && s.system != system) return false;
    if (q.isEmpty) return true;
    return s.name.toLowerCase().contains(q) ||
        s.school.toLowerCase().contains(q);
  }

  final m = (filter == ContentType.spells)
      ? <Creature>[]
      : monsters.where(monsterMatch).toList();
  final s = (filter == ContentType.monsters)
      ? <SpellEntry>[]
      : spells.where(spellMatch).toList();
  return ContentResults(monsters: m, spells: s);
}

/// Best-effort system inference from a creature id prefix (e.g. "dnd-goblin").
String? _monsterSystem(Creature c) {
  final dash = c.id.indexOf('-');
  return dash > 0 ? c.id.substring(0, dash) : null;
}

/// Adapts an Ironsworn-family [FoeEntry] into the unified [Creature] shape so it
/// shows alongside bundled monsters in the registry. Rank x10 HP (matching the
/// encounter foe picker); tactics + features folded into the stat block notes.
Creature foeEntryToCreature(FoeEntry e) {
  final noteParts = [
    if (e.nature.isNotEmpty) 'Nature: ${e.nature}',
    if (e.tactics.isNotEmpty) 'Tactics: ${e.tactics.join(', ')}',
    if (e.features.isNotEmpty) 'Features: ${e.features.join(', ')}',
  ];
  return Creature(
    id: e.id,
    name: e.name,
    maxHp: e.rank * 10,
    statBlock:
        noteParts.isNotEmpty ? StatBlock(notes: noteParts.join('\n')) : const StatBlock(),
  );
}

/// System -> attribution/license line, shown in the reference footer + settings.
/// Only systems with bundled content appear.
const kContentAttributions = <String, String>{
  'dnd':
      'Includes content from the System Reference Document 5.1, © Wizards of '
          'the Coast LLC, available under the Creative Commons Attribution 4.0 '
          'International License (CC-BY-4.0).',
  'cairn': 'Cairn © Yochai Gal, licensed under CC-BY-SA-4.0.',
  'ose':
      'Compatible with Old-School Essentials (Necrotic Gnome). B/X mechanics; '
          'not affiliated.',
  'argosa': 'Tales of Argosa © S.J. Grodzicki / Pickpocket Press, licensed '
      'under CC-BY-SA-4.0.',
  'knave': 'Knave Second Edition © Ben Milton / Questing Beast Games, licensed '
      'under CC-BY-4.0.',
  'dcc': 'Dungeon Crawl Classics mechanics used under the Open Game License '
      '1.0a. Not affiliated with Goodman Games.',
};
