import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/oracle.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import 'map_screen.dart';
import 'verdant_screen.dart';

class MapsTab extends ConsumerWidget {
  const MapsTab({super.key, required this.oracle});
  final Oracle oracle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SubtabHost(
      destination: Destination.maps,
      tabs: const [
        SubtabDef('world', 'World'),
        SubtabDef('dungeon', 'Dungeon'),
        SubtabDef('journey', 'Journey'),
      ],
      children: [
        HexMapPane(oracle: oracle),
        DungeonMapPane(oracle: oracle),
        VerdantScreen(oracle: oracle),
      ],
    );
  }
}
