import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import 'battle_pane.dart';
import 'encounter_screen.dart';
import 'party_tools_pane.dart';
import 'resources_pane.dart';
import 'scenes_pane.dart';
import 'track_home_pane.dart';
import 'tracker_screen.dart';
import 'world_pane.dart';

class TrackingTab extends ConsumerWidget {
  const TrackingTab({super.key, this.systems = kAllSystems});
  final Set<String> systems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lonelog = systems.contains('lonelog');
    final party = systems.contains('party');
    final partyTools = party;
    return SubtabHost(
      destination: Destination.track,
      scrollable: true,
      // Consolidated (was 11+ same-weight tabs): a task IS a thread with a
      // tally, so Tasks routes into Threads; People + Places share the World
      // pane; Rumors + Tracks are threads with a stage, so they route into
      // Threads too. Legacy subtab keys keep working via SubtabDef aliases.
      tabs: [
        const SubtabDef('home', 'Home'),
        const SubtabDef('scenes', 'Scenes'),
        const SubtabDef('threads', 'Threads',
            aliases: ['tasks', 'rumors', 'tracks']),
        const SubtabDef('world', 'World', aliases: ['people', 'places']),
        const SubtabDef('encounter', 'Encounter'),
        // One party paradigm renders per SessionMeta.partyTool (Emulator /
        // Behavior / Sidekick are mutually exclusive, not stacked). The
        // aliases only keep legacy routes ('emulator'/'sidekick'/'behavior')
        // resolving to this subtab.
        if (partyTools)
          const SubtabDef('party', 'Party',
              aliases: ['emulator', 'sidekick', 'behavior']),
        if (lonelog) const SubtabDef('resources', 'Resources'),
        if (lonelog) const SubtabDef('battle', 'Battle'),
      ],
      children: [
        const TrackHomePane(),
        const ScenesPane(),
        const ThreadsPane(),
        const WorldPane(),
        const EncounterScreen(),
        if (partyTools) const PartyToolsPane(),
        if (lonelog) const ResourcesPane(),
        if (lonelog) const BattlePane(),
      ],
    );
  }
}
