/// Authored, facts-only per-system primers fed into the oracle and voice
/// prompts (see lib/engine/oracle_interpreter.dart). Each line is a setting
/// descriptor plus the system's core resolution vocabulary — non-copyrightable
/// game-mechanic facts, NOT rulebook prose. No attribution, no logos, no
/// taglines (see docs/superpowers/specs/2026-06-17-system-primer-design.md and
/// memory/licensing-constraint). Pure Dart.
library;

/// Budget guard: each primer stays a single dense line so it grounds without
/// crowding the recall/scene lines (the interpreter session is token-capped —
/// see interpreter_gemma.dart _loadModel). A test pins it; no runtime
/// truncation — these are authored constants, not user data.
const int kSystemPrimerMaxChars = 220;

const Map<String, String> kSystemPrimers = {
  'ironsworn':
      'Ironsworn: grim, mythic low-fantasy survival in the Ironlands, ruled by sworn vows. Resolution: action die +stat vs two challenge dice → strong/weak hit or miss; momentum; pay the price.',
  'starforged':
      'Starforged: hardscrabble space opera in a lawless frontier sector. Resolution: action die +stat vs two challenge dice → strong/weak hit or miss; momentum; pay the price.',
  'sundered_isles':
      'Sundered Isles: supernatural age-of-sail adventure across haunted, sundered seas. Resolution: action die +stat vs two challenge dice → strong/weak hit or miss; momentum; pay the price.',
  'dnd':
      'D&D 5e: heroic high fantasy. Resolution: d20 + modifier vs DC or AC; advantage/disadvantage; saving throws; conditions; hit points and death saves.',
  'shadowdark':
      'Shadowdark: lethal, gritty old-school dungeon-crawling where light and time are deadly resources. Resolution: d20 + modifier vs DC or AC; luck tokens; swift death.',
  'nimble':
      'Nimble: fast, tactical 5e-compatible fantasy. Resolution: d20 + stat vs DC or armor; advantage/disadvantage; a wounds dying-track; slot inventory.',
  'draw-steel':
      'Draw Steel: cinematic tactical fantasy. Resolution: power roll 2d10+characteristic → Tier 1 (≤11), Tier 2 (12-16), Tier 3 (≥17); heroic resources; stamina and recoveries.',
  'argosa':
      'Tales of Argosa: perilous sword & sorcery. Resolution: roll d20 under stat → Success; under half → Great Success; Luck = 10 + half level, degrades through the adventure.',
  'cairn':
      'Cairn: gritty OSR adventure. Saves: roll d20 equal or under stat to pass. HP is hit protection (avoidance); at 0 HP excess damage reduces STR. Deprived characters cannot heal.',
  'knave':
      'Knave 2e: classless OSR. Saves: d20 + ability score >= 11 to pass. No classes. Wounds fill inventory slots; 10 + CON slots total.',
  'embark':
      'Embark 2E: heroic, deadly OSR. Resolution: d12 + attribute (STR/DEX/WIL/INT) >= 8 to succeed; advantage/disadvantage. HP with a 3-Injury death track (each Injury -1 to Checks); AV armor; classes with resource pools.',
  'ose':
      'Old-School Essentials (B/X): classic fantasy. Saves: roll d20 equal or over target (Death/Wands/Paralysis/Breath/Spells). Descending AC (9=unarmored). THAC0 for attacks.',
  'kal-arath':
      'Kal-Arath: sword & sorcery OSR. Resolution: roll 2d6 + stat, 8+ to succeed; double 6s crit, double 1s fumble. Five stats; demonic pacts; Fate Points.',
  'dcc':
      'Dungeon Crawl Classics: pulpy sword & sorcery. Resolution: d20 + mod vs DC; warriors roll a deed die; casters make spell checks and can spellburn; spend Luck to boost rolls; Fort/Ref/Will saves.',
};

String _primerFor(String key) =>
    kSystemPrimers[key] ??
    (throw StateError('system_primer: no primer for system "$key"'));

/// Resolves a campaign's enabled [systems] + [rulesets] to one primer, or ''
/// when no covered TTRPG system is enabled. Priority: dnd > shadowdark >
/// Ironsworn-family. The Ironsworn family shares the `ironsworn` campaign flag,
/// so it is refined by the enabled ruleset (sundered_isles > starforged >
/// classic).
String resolveSystemPrimer(Set<String> systems, Set<String> rulesets) {
  if (systems.contains('dnd')) return _primerFor('dnd');
  if (systems.contains('shadowdark')) return _primerFor('shadowdark');
  if (systems.contains('nimble')) return _primerFor('nimble');
  if (systems.contains('draw-steel')) return _primerFor('draw-steel');
  if (systems.contains('argosa')) return _primerFor('argosa');
  if (systems.contains('cairn')) return _primerFor('cairn');
  if (systems.contains('knave')) return _primerFor('knave');
  if (systems.contains('embark')) return _primerFor('embark');
  if (systems.contains('ose')) return _primerFor('ose');
  if (systems.contains('kal-arath')) return _primerFor('kal-arath');
  if (systems.contains('dcc')) return _primerFor('dcc');
  if (systems.contains('ironsworn')) {
    if (rulesets.contains('sundered_isles')) {
      return _primerFor('sundered_isles');
    }
    if (rulesets.contains('starforged')) return _primerFor('starforged');
    return _primerFor('ironsworn');
  }
  return '';
}

/// The active system KEY, by the same priority as [resolveSystemPrimer]:
/// dnd > shadowdark > Ironsworn-family (sundered_isles > starforged > ironsworn).
/// Empty when no covered system is enabled.
String resolveSystem(Set<String> systems, Set<String> rulesets) {
  if (systems.contains('dnd')) return 'dnd';
  if (systems.contains('shadowdark')) return 'shadowdark';
  if (systems.contains('nimble')) return 'nimble';
  if (systems.contains('draw-steel')) return 'draw-steel';
  if (systems.contains('argosa')) return 'argosa';
  if (systems.contains('cairn')) return 'cairn';
  if (systems.contains('knave')) return 'knave';
  if (systems.contains('embark')) return 'embark';
  if (systems.contains('ose')) return 'ose';
  if (systems.contains('kal-arath')) return 'kal-arath';
  if (systems.contains('dcc')) return 'dcc';
  if (systems.contains('ironsworn')) {
    if (rulesets.contains('sundered_isles')) return 'sundered_isles';
    if (rulesets.contains('starforged')) return 'starforged';
    return 'ironsworn';
  }
  return '';
}
