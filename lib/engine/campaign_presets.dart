/// A one-tap campaign starting point: a curated lean system set.
/// Pure data — no Flutter dependency (icons are resolved in the UI layer).
class CampaignPreset {
  const CampaignPreset({
    required this.id,
    required this.label,
    required this.kind,
    required this.blurb,
    required this.systems,
  });

  final String id;

  /// The ruleset / system display name (e.g. 'D&D 5e').
  final String label;

  /// The kind-of-play headline (e.g. 'Heroic dungeon crawl').
  final String kind;

  /// A short play-fantasy descriptor (e.g. 'Classes & spells').
  final String blurb;

  final Set<String> systems;
}

/// Resolves a preset to the systems a new campaign is created with.
Set<String> presetConfig(CampaignPreset p) => p.systems;

/// Ruleset presets (juice oracle + party tools + the ruleset) +
/// two shape presets. "Custom" is a UI affordance, not a preset entry.
const kCampaignPresets = <CampaignPreset>[
  CampaignPreset(
      id: 'solo-ironsworn',
      label: 'Ironsworn / Starforged',
      kind: 'Gritty solo fantasy',
      blurb: 'Vows, perilous odds',
      systems: {'ironsworn', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-dnd',
      label: 'D&D 5e',
      kind: 'Heroic dungeon crawl',
      blurb: 'Classes & spells',
      systems: {'dnd', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-shadowdark',
      label: 'Shadowdark',
      kind: 'Deadly torch-lit delve',
      blurb: 'Light pressure',
      systems: {'shadowdark', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-nimble',
      label: 'Nimble',
      kind: 'Fast tactical fantasy',
      blurb: 'Lean, kinetic combat',
      systems: {'nimble', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-draw-steel',
      label: 'Draw Steel',
      kind: 'Cinematic heroic combat',
      blurb: 'Power rolls & heroics',
      systems: {'draw-steel', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-argosa',
      label: 'Tales of Argosa',
      kind: 'Sword & sorcery pulp',
      blurb: 'Roll-under, push your luck',
      systems: {'argosa', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-cairn',
      label: 'Cairn',
      kind: 'Grim woodland survival',
      blurb: 'No classes, just grit',
      systems: {'cairn', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-knave',
      label: 'Knave 2e',
      kind: 'Lean old-school romp',
      blurb: 'Slot-based scavenging',
      systems: {'knave', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-embark',
      label: 'Embark 2E',
      kind: 'Heroic, deadly OSR',
      blurb: 'd12 + attribute, track torches',
      systems: {'embark', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-ose',
      label: 'OSE / B/X',
      kind: 'Classic dungeon raid',
      blurb: 'Old-school B/X play',
      systems: {'ose', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-kal-arath',
      label: 'Kal-Arath',
      kind: 'Dark sword & sorcery',
      blurb: 'Demonic pacts & doom',
      systems: {'kal-arath', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-custom',
      label: 'Custom / Homebrew',
      kind: 'Build your own sheet',
      blurb: 'Any game, your blocks',
      systems: {'custom', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-dcc',
      label: 'Dungeon Crawl Classics',
      kind: 'Brutal 0-level funnel',
      blurb: 'Peasants die, heroes rise',
      systems: {'dcc', 'juice', 'party', 'funnel'}),
  CampaignPreset(
      id: 'solo-funnel',
      label: 'Character Funnel',
      kind: 'Session-zero gauntlet',
      blurb: 'Doomed peasants → survivors',
      // Seeds the funnel with DCC (the archetypal funnel game); the player can
      // enable other rulesets to graduate survivors into them.
      systems: {'funnel', 'dcc', 'juice', 'party'}),
  CampaignPreset(
      id: 'oracle',
      label: 'System-agnostic oracle',
      kind: 'Pure oracle / journaling',
      blurb: 'No rules, just ask',
      systems: {'juice', 'mythic', 'cards', 'party'}),
];
