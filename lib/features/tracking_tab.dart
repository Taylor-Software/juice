import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import 'scenes_pane.dart';
import 'tracker_screen.dart';
import 'encounter_screen.dart';

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
        ScenesPane(),
        CharactersPane(),
        ThreadsPane(),
        Center(child: Text('Rumors')),
        Center(child: Text('Tracks')),
        EncounterScreen(),
      ],
    );
  }
}
