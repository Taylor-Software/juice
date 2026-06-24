/// Authored, facts-only per-system primers fed into the oracle and voice
/// prompts (see lib/engine/oracle_interpreter.dart). Each line is a setting
/// descriptor plus the system's core resolution vocabulary — non-copyrightable
/// game-mechanic facts, NOT rulebook prose. No attribution, no logos, no
/// taglines (see docs/superpowers/specs/2026-06-17-system-primer-design.md and
/// memory/licensing-constraint). Pure Dart.
library;

/// Budget guard: each primer stays short so the worst-case oracle prompt fits
/// the web model's ~1280-token context (spec "Token budget"). A test pins it;
/// no runtime truncation — these are authored constants, not user data.
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
};

/// Resolves a campaign's enabled [systems] + [rulesets] to one primer, or ''
/// when no covered TTRPG system is enabled. Priority: dnd > shadowdark >
/// Ironsworn-family. The Ironsworn family shares the `ironsworn` campaign flag,
/// so it is refined by the enabled ruleset (sundered_isles > starforged >
/// classic).
String resolveSystemPrimer(Set<String> systems, Set<String> rulesets) {
  if (systems.contains('dnd')) return kSystemPrimers['dnd']!;
  if (systems.contains('shadowdark')) return kSystemPrimers['shadowdark']!;
  if (systems.contains('nimble')) return kSystemPrimers['nimble']!;
  if (systems.contains('draw-steel')) return kSystemPrimers['draw-steel']!;
  if (systems.contains('argosa')) return kSystemPrimers['argosa']!;
  if (systems.contains('cairn')) return kSystemPrimers['cairn']!;
  if (systems.contains('knave')) return kSystemPrimers['knave']!;
  if (systems.contains('ironsworn')) {
    if (rulesets.contains('sundered_isles')) {
      return kSystemPrimers['sundered_isles']!;
    }
    if (rulesets.contains('starforged')) return kSystemPrimers['starforged']!;
    return kSystemPrimers['ironsworn']!;
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
  if (systems.contains('ironsworn')) {
    if (rulesets.contains('sundered_isles')) return 'sundered_isles';
    if (rulesets.contains('starforged')) return 'starforged';
    return 'ironsworn';
  }
  return '';
}
