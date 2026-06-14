import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/oracle.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';

class MapsTab extends ConsumerWidget {
  const MapsTab({super.key, required this.oracle});
  final Oracle oracle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SubtabHost(
      destination: Destination.maps,
      tabs: [
        SubtabDef('world', 'World'),
        SubtabDef('dungeon', 'Dungeon'),
        SubtabDef('journey', 'Journey'),
      ],
      children: [
        Center(child: Text('World')),
        Center(child: Text('Dungeon')),
        Center(child: Text('Journey')),
      ],
    );
  }
}
