import 'models.dart';

/// A one-tap campaign starting point: a mode + a curated lean system set.
/// Pure data — no Flutter dependency (icons are resolved in the UI layer).
class CampaignPreset {
  const CampaignPreset({
    required this.id,
    required this.label,
    required this.kind,
    required this.blurb,
    required this.mode,
    required this.systems,
  });

  final String id;

  /// The ruleset / system display name (e.g. 'D&D 5e').
  final String label;

  /// The kind-of-play headline (e.g. 'Heroic dungeon crawl').
  final String kind;

  /// A short play-fantasy descriptor (e.g. 'Classes & spells').
  final String blurb;

  final CampaignMode mode;
  final Set<String> systems;
}

/// Resolves a preset to the (mode, systems) a new campaign is created with.
(CampaignMode, Set<String>) presetConfig(CampaignPreset p) =>
    (p.mode, p.systems);

/// Ruleset presets (party mode, juice oracle + party tools + the ruleset) +
/// two shape presets. "Custom" is a UI affordance, not a preset entry.
const kCampaignPresets = <CampaignPreset>[
  CampaignPreset(
      id: 'solo-ironsworn',
      label: 'Ironsworn / Starforged',
      kind: 'Gritty solo fantasy',
      blurb: 'Vows, perilous odds',
      mode: CampaignMode.party,
      systems: {'ironsworn', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-dnd',
      label: 'D&D 5e',
      kind: 'Heroic dungeon crawl',
      blurb: 'Classes & spells',
      mode: CampaignMode.party,
      systems: {'dnd', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-shadowdark',
      label: 'Shadowdark',
      kind: 'Deadly torch-lit delve',
      blurb: 'Light pressure',
      mode: CampaignMode.party,
      systems: {'shadowdark', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-nimble',
      label: 'Nimble',
      kind: 'Fast tactical fantasy',
      blurb: 'Lean, kinetic combat',
      mode: CampaignMode.party,
      systems: {'nimble', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-draw-steel',
      label: 'Draw Steel',
      kind: 'Cinematic heroic combat',
      blurb: 'Power rolls & heroics',
      mode: CampaignMode.party,
      systems: {'draw-steel', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-argosa',
      label: 'Tales of Argosa',
      kind: 'Sword & sorcery pulp',
      blurb: 'Roll-under, push your luck',
      mode: CampaignMode.party,
      systems: {'argosa', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-cairn',
      label: 'Cairn',
      kind: 'Grim woodland survival',
      blurb: 'No classes, just grit',
      mode: CampaignMode.party,
      systems: {'cairn', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-knave',
      label: 'Knave 2e',
      kind: 'Lean old-school romp',
      blurb: 'Slot-based scavenging',
      mode: CampaignMode.party,
      systems: {'knave', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-ose',
      label: 'OSE / B/X',
      kind: 'Classic dungeon raid',
      blurb: 'Old-school B/X play',
      mode: CampaignMode.party,
      systems: {'ose', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-kal-arath',
      label: 'Kal-Arath',
      kind: 'Dark sword & sorcery',
      blurb: 'Demonic pacts & doom',
      mode: CampaignMode.party,
      systems: {'kal-arath', 'juice', 'party'}),
  CampaignPreset(
      id: 'oracle',
      label: 'System-agnostic oracle',
      kind: 'Pure oracle / journaling',
      blurb: 'No rules, just ask',
      mode: CampaignMode.party,
      systems: {'juice', 'mythic', 'cards', 'party'}),
  CampaignPreset(
      id: 'gm-toolkit',
      label: 'GM toolkit',
      kind: 'GM toolkit',
      blurb: 'Run a table',
      mode: CampaignMode.gm,
      systems: {'juice', 'mythic'}),
];
