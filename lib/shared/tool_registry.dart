import 'package:flutter/material.dart';

import '../engine/models.dart';

/// Metadata for a tool in the tool-search sheet: identity, label, icon,
/// group, and optional source badge. The sheet navigates by [id] via the
/// shell route; it never builds the tool widget itself.
class ToolDef {
  const ToolDef({
    required this.id,
    required this.label,
    required this.icon,
    required this.group,
    this.badge,
  });
  final String id;
  final String label;
  final IconData icon;
  final String group;

  /// Source-system badge shown in the tool-search list ('Juice', 'Mythic', …).
  final String? badge;
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
  'Help',
];

/// Registry tool id -> the system that owns it; 'core' tools always show.
/// roll-high rides with the Juice profile (same Fate surface).
const toolSystem = <String, String>{
  'fate-check': 'juice',
  'roll-high': 'juice',
  'mythic': 'mythic',
  'dice': 'core',
  'gen-story': 'juice',
  'gen-npcs': 'juice',
  'party-emulator': 'party',
  'sidekick-dialogue': 'party',
  'behavior-tables': 'party',
  'gen-exploration': 'juice',
  'maps': 'juice',
  'verdant': 'verdant',
  'gen-encounters': 'juice',
  'encounter': 'core',
  'gen-details': 'juice',
  'threads-characters': 'core',
  'tables': 'juice',
  'lonelog-ref': 'lonelog',
  'moves': 'ironsworn',
  'help': 'core',
};

/// Registry tool id -> help page id (Help tool itself is absent).
const toolHelpPage = <String, String>{
  'fate-check': 'fate-check',
  'roll-high': 'roll-high',
  'mythic': 'mythic-gme',
  'dice': 'dice-roller',
  'gen-story': 'story-scenes',
  'gen-npcs': 'npcs-dialog',
  'gen-exploration': 'generators-tables',
  'gen-encounters': 'generators-tables',
  'gen-details': 'generators-tables',
  'tables': 'generators-tables',
  'party-emulator': 'party-emulator',
  'behavior-tables': 'behavior-tables',
  'sidekick-dialogue': 'sidekick-dialogue',
  'threads-characters': 'threads-characters',
  'encounter': 'encounter',
  'maps': 'maps',
  'verdant': 'verdant',
  'moves': 'moves',
};

/// Build the registry. [family] is the enabled Ironsworn family chain
/// (e.g. ['classic','delve']); empty = no Moves tool. [systems] is the set
/// of enabled optional systems; defaults to all (kAllSystems).
List<ToolDef> buildToolRegistry({
  required List<String> family,
  Set<String> systems = kAllSystems,
}) {
  final all = <ToolDef>[
    const ToolDef(
      id: 'fate-check',
      label: 'Fate Check',
      icon: Icons.help_outline,
      group: 'Ask the Oracle',
      badge: 'Juice',
    ),
    const ToolDef(
      id: 'roll-high',
      label: 'Roll High Oracle',
      icon: Icons.trending_up,
      group: 'Ask the Oracle',
    ),
    const ToolDef(
      id: 'mythic',
      label: 'Mythic GME',
      icon: Icons.theater_comedy_outlined,
      group: 'Ask the Oracle',
      badge: 'Mythic',
    ),
    const ToolDef(
      id: 'dice',
      label: 'Dice Roller',
      icon: Icons.casino_outlined,
      group: 'Dice',
    ),
    const ToolDef(
      id: 'gen-story',
      label: 'Story & Scenes',
      icon: Icons.auto_stories_outlined,
      group: 'Story & Scenes',
      badge: 'Juice',
    ),
    const ToolDef(
      id: 'gen-npcs',
      label: 'NPCs & Dialog',
      icon: Icons.people_outline,
      group: 'NPCs & Dialog',
      badge: 'Juice',
    ),
    const ToolDef(
      id: 'party-emulator',
      label: 'Party Emulator',
      icon: Icons.psychology_outlined,
      group: 'Party',
      badge: 'Triple-O',
    ),
    const ToolDef(
      id: 'sidekick-dialogue',
      label: 'Sidekick Dialogue',
      icon: Icons.forum_outlined,
      group: 'Party',
      badge: 'PET',
    ),
    const ToolDef(
      id: 'behavior-tables',
      label: 'Behavior Tables',
      icon: Icons.groups_outlined,
      group: 'Party',
      badge: 'Triple-O',
    ),
    const ToolDef(
      id: 'gen-exploration',
      label: 'Exploration & Crawl',
      icon: Icons.explore_outlined,
      group: 'Exploration',
      badge: 'Juice',
    ),
    const ToolDef(
      id: 'maps',
      label: 'Maps',
      icon: Icons.map_outlined,
      group: 'Exploration',
      badge: 'Juice',
    ),
    const ToolDef(
      id: 'verdant',
      label: 'Verdant Journey',
      icon: Icons.forest_outlined,
      group: 'Exploration',
      badge: 'Verdant',
    ),
    const ToolDef(
      id: 'gen-encounters',
      label: 'Monsters & Tracks',
      icon: Icons.pets_outlined,
      group: 'Encounters & Combat',
      badge: 'Juice',
    ),
    const ToolDef(
      id: 'encounter',
      label: 'Encounter Tracker',
      icon: Icons.shield_outlined,
      group: 'Encounters & Combat',
    ),
    const ToolDef(
      id: 'gen-details',
      label: 'Names & Details',
      icon: Icons.style_outlined,
      group: 'Names & Details',
      badge: 'Juice',
    ),
    const ToolDef(
      id: 'threads-characters',
      label: 'Threads & Characters',
      icon: Icons.bookmarks_outlined,
      group: 'Characters & Threads',
    ),
    const ToolDef(
      id: 'tables',
      label: 'Table Browser',
      icon: Icons.grid_view_outlined,
      group: 'Reference',
      badge: 'Juice',
    ),
    const ToolDef(
      id: 'lonelog-ref',
      label: 'Lonelog Notation',
      icon: Icons.notes_outlined,
      group: 'Reference',
      badge: 'Lonelog',
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
      ),
    const ToolDef(
      id: 'help',
      label: 'Help',
      icon: Icons.help_outline,
      group: 'Help',
    ),
  ];
  return all
      .where((t) =>
          (toolSystem[t.id] ?? 'core') == 'core' ||
          systems.contains(toolSystem[t.id]))
      .toList();
}
