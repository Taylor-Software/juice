import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/models.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import '../state/providers.dart';
import 'rumors_pane.dart';
import 'scenes_pane.dart';
import 'tracker_screen.dart';
import 'tracks_pane.dart';
import 'encounter_screen.dart';
import 'resources_pane.dart';

class TrackingTab extends ConsumerWidget {
  const TrackingTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lonelog =
        (ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
                kAllSystems)
            .contains('lonelog');
    return SubtabHost(
      destination: Destination.tracking,
      scrollable: true,
      tabs: [
        const SubtabDef('scenes', 'Scenes'),
        const SubtabDef('npcs', 'NPCs'),
        const SubtabDef('threads', 'Threads'),
        const SubtabDef('rumors', 'Rumors'),
        const SubtabDef('tracks', 'Tracks'),
        const SubtabDef('encounter', 'Encounter'),
        if (lonelog) const SubtabDef('resources', 'Resources'),
      ],
      children: [
        const ScenesPane(),
        const CharactersPane(),
        const ThreadsPane(),
        const RumorsPane(),
        const TracksPane(),
        const EncounterScreen(),
        if (lonelog) const ResourcesPane(),
      ],
    );
  }
}
