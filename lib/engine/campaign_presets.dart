import 'models.dart';

/// A one-tap campaign starting point: a mode + a curated lean system set.
/// Pure data — no Flutter dependency (icons are resolved in the UI layer).
class CampaignPreset {
  const CampaignPreset({
    required this.id,
    required this.label,
    required this.mode,
    required this.systems,
  });

  final String id;
  final String label;
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
      mode: CampaignMode.party,
      systems: {'ironsworn', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-dnd',
      label: 'D&D 5e',
      mode: CampaignMode.party,
      systems: {'dnd', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-shadowdark',
      label: 'Shadowdark',
      mode: CampaignMode.party,
      systems: {'shadowdark', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-nimble',
      label: 'Nimble',
      mode: CampaignMode.party,
      systems: {'nimble', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-draw-steel',
      label: 'Draw Steel',
      mode: CampaignMode.party,
      systems: {'draw-steel', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-argosa',
      label: 'Tales of Argosa',
      mode: CampaignMode.party,
      systems: {'argosa', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-cairn',
      label: 'Cairn',
      mode: CampaignMode.party,
      systems: {'cairn', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-knave',
      label: 'Knave 2e',
      mode: CampaignMode.party,
      systems: {'knave', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-ose',
      label: 'OSE / B/X',
      mode: CampaignMode.party,
      systems: {'ose', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-kal-arath',
      label: 'Kal-Arath',
      mode: CampaignMode.party,
      systems: {'kal-arath', 'juice', 'party'}),
  CampaignPreset(
      id: 'oracle',
      label: 'System-agnostic oracle',
      mode: CampaignMode.party,
      systems: {'juice', 'mythic', 'cards', 'party'}),
  CampaignPreset(
      id: 'gm-toolkit',
      label: 'GM toolkit',
      mode: CampaignMode.gm,
      systems: {'juice', 'mythic'}),
];
