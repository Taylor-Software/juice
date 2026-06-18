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
};

/// Resolves a campaign's enabled [systems] + [rulesets] to one primer, or ''
/// when no covered TTRPG system is enabled. Priority: dnd > shadowdark >
/// Ironsworn-family. The Ironsworn family shares the `ironsworn` campaign flag,
/// so it is refined by the enabled ruleset (sundered_isles > starforged >
/// classic).
String resolveSystemPrimer(Set<String> systems, Set<String> rulesets) {
  if (systems.contains('dnd')) return kSystemPrimers['dnd']!;
  if (systems.contains('shadowdark')) return kSystemPrimers['shadowdark']!;
  if (systems.contains('ironsworn')) {
    if (rulesets.contains('sundered_isles')) {
      return kSystemPrimers['sundered_isles']!;
    }
    if (rulesets.contains('starforged')) return kSystemPrimers['starforged']!;
    return kSystemPrimers['ironsworn']!;
  }
  return '';
}
