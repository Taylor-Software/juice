import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/oracle.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import 'map_screen.dart';
import 'verdant_screen.dart';
import 'hexcrawl_screen.dart';

class MapsTab extends ConsumerWidget {
  const MapsTab({super.key, required this.oracle, required this.systems});
  final Oracle oracle;
  final Set<String> systems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showJourney = systems.contains('verdant');
    final showHexcrawl = systems.contains('hexcrawl');
    return SubtabHost(
      destination: Destination.maps,
      tabs: [
        const SubtabDef('world', 'World'),
        const SubtabDef('dungeon', 'Dungeon'),
        if (showJourney) const SubtabDef('journey', 'Journey'),
        if (showHexcrawl) const SubtabDef('hexcrawl', 'Hexcrawl'),
      ],
      children: [
        HexMapPane(oracle: oracle),
        DungeonMapPane(oracle: oracle),
        if (showJourney) VerdantScreen(oracle: oracle),
        if (showHexcrawl) const HexcrawlScreen(),
      ],
    );
  }
}
