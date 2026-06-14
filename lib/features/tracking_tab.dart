import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';

class TrackingTab extends ConsumerWidget {
  const TrackingTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SubtabHost(
      destination: Destination.tracking,
      scrollable: true,
      tabs: [
        SubtabDef('scenes', 'Scenes'),
        SubtabDef('npcs', 'NPCs'),
        SubtabDef('threads', 'Threads'),
        SubtabDef('rumors', 'Rumors'),
        SubtabDef('tracks', 'Tracks'),
        SubtabDef('encounter', 'Encounter'),
      ],
      children: [
        Center(child: Text('Scenes')),
        Center(child: Text('NPCs')),
        Center(child: Text('Threads')),
        Center(child: Text('Rumors')),
        Center(child: Text('Tracks')),
        Center(child: Text('Encounter')),
      ],
    );
  }
}
