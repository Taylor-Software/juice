import 'package:flutter/material.dart';

import '../engine/oracle.dart';
import '../features/behavior_tables_screen.dart';
import '../features/dice_roller_screen.dart';
import '../features/encounter_screen.dart';
import '../features/fate_screen.dart';
import '../features/generators_screen.dart';
import '../features/map_screen.dart';
import '../features/moves_screen.dart';
import '../features/party_emulator_screen.dart';
import '../features/sidekick_screen.dart';
import '../features/tables_screen.dart';
import '../features/tracker_screen.dart';

/// A tool the launcher can summon over the journal.
class ToolDef {
  const ToolDef({
    required this.id,
    required this.label,
    required this.icon,
    required this.group,
    this.badge,
    required this.builder,
  });
  final String id;
  final String label;
  final IconData icon;
  final String group;

  /// Source-system badge shown in the launcher ('Juice', 'Mythic', …).
  final String? badge;

  /// Oracle is nullable so tests can inject self-contained fake tools;
  /// real builders use `o!`.
  final Widget Function(Oracle? oracle) builder;
}

/// Launcher group order (activity-based; see redesign spec phase 2).
const toolGroups = [
  'Ask the Oracle',
  'Dice',
  'Story & Scenes',
  'NPCs & Dialog',
  'Party',
  'Exploration',
  'Encounters & Combat',
  'Names & Details',
  'Characters & Threads',
  'Reference',
];

/// Build the registry. [family] is the enabled Ironsworn family chain
/// (e.g. ['classic','delve']); empty = no Moves tool.
List<ToolDef> buildToolRegistry({required List<String> family}) => [
      ToolDef(
        id: 'fate-check',
        label: 'Fate Check',
        icon: Icons.help_outline,
        group: 'Ask the Oracle',
        badge: 'Juice',
        builder: (o) =>
            FateScreen(oracle: o!, initialSection: FateSection.fateCheck),
      ),
      ToolDef(
        id: 'roll-high',
        label: 'Roll High Oracle',
        icon: Icons.trending_up,
        group: 'Ask the Oracle',
        builder: (o) =>
            FateScreen(oracle: o!, initialSection: FateSection.rollHigh),
      ),
      ToolDef(
        id: 'mythic',
        label: 'Mythic GME',
        icon: Icons.theater_comedy_outlined,
        group: 'Ask the Oracle',
        badge: 'Mythic',
        builder: (o) =>
            FateScreen(oracle: o!, initialSection: FateSection.mythic),
      ),
      ToolDef(
        id: 'dice',
        label: 'Dice Roller',
        icon: Icons.casino_outlined,
        group: 'Dice',
        builder: (o) => DiceRollerScreen(dice: o!.dice),
      ),
      ToolDef(
        id: 'gen-story',
        label: 'Story & Scenes',
        icon: Icons.auto_stories_outlined,
        group: 'Story & Scenes',
        badge: 'Juice',
        builder: (o) => GeneratorsScreen(oracle: o!, section: GenSection.story),
      ),
      ToolDef(
        id: 'gen-npcs',
        label: 'NPCs & Dialog',
        icon: Icons.people_outline,
        group: 'NPCs & Dialog',
        badge: 'Juice',
        builder: (o) => GeneratorsScreen(oracle: o!, section: GenSection.npcs),
      ),
      ToolDef(
        id: 'party-emulator',
        label: 'Party Emulator',
        icon: Icons.psychology_outlined,
        group: 'Party',
        badge: 'Triple-O',
        builder: (_) => const PartyEmulatorScreen(),
      ),
      ToolDef(
        id: 'sidekick-dialogue',
        label: 'Sidekick Dialogue',
        icon: Icons.forum_outlined,
        group: 'Party',
        badge: 'PET',
        builder: (_) => const SidekickScreen(),
      ),
      ToolDef(
        id: 'behavior-tables',
        label: 'Behavior Tables',
        icon: Icons.groups_outlined,
        group: 'Party',
        badge: 'Triple-O',
        builder: (_) => const BehaviorTablesScreen(),
      ),
      ToolDef(
        id: 'gen-exploration',
        label: 'Exploration & Crawl',
        icon: Icons.explore_outlined,
        group: 'Exploration',
        badge: 'Juice',
        builder: (o) =>
            GeneratorsScreen(oracle: o!, section: GenSection.exploration),
      ),
      ToolDef(
        id: 'maps',
        label: 'Maps',
        icon: Icons.map_outlined,
        group: 'Exploration',
        badge: 'Juice',
        builder: (o) => MapScreen(oracle: o!),
      ),
      ToolDef(
        id: 'gen-encounters',
        label: 'Monsters & Tracks',
        icon: Icons.pets_outlined,
        group: 'Encounters & Combat',
        badge: 'Juice',
        builder: (o) =>
            GeneratorsScreen(oracle: o!, section: GenSection.encounters),
      ),
      ToolDef(
        id: 'encounter',
        label: 'Encounter Tracker',
        icon: Icons.shield_outlined,
        group: 'Encounters & Combat',
        builder: (_) => const EncounterScreen(),
      ),
      ToolDef(
        id: 'gen-details',
        label: 'Names & Details',
        icon: Icons.style_outlined,
        group: 'Names & Details',
        badge: 'Juice',
        builder: (o) =>
            GeneratorsScreen(oracle: o!, section: GenSection.details),
      ),
      ToolDef(
        id: 'threads-characters',
        label: 'Threads & Characters',
        icon: Icons.bookmarks_outlined,
        group: 'Characters & Threads',
        builder: (_) => const TrackerScreen(),
      ),
      ToolDef(
        id: 'tables',
        label: 'Table Browser',
        icon: Icons.grid_view_outlined,
        group: 'Reference',
        badge: 'Juice',
        builder: (o) => TablesScreen(oracle: o!),
      ),
      if (family.isNotEmpty)
        ToolDef(
          id: 'moves',
          label: family.contains('starforged')
              ? 'Starforged Moves & Oracles'
              : 'Ironsworn Moves & Oracles',
          icon: Icons.flash_on_outlined,
          group: 'Reference',
          badge: 'Ironsworn',
          builder: (_) => MovesScreen(rulesetIds: family),
        ),
    ];
