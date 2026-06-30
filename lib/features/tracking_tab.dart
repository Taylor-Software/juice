import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import 'battle_pane.dart';
import 'behavior_tables_screen.dart';
import 'loop_pane.dart';
import 'encounter_screen.dart';
import 'party_emulator_screen.dart';
import 'resources_pane.dart';
import 'rumors_pane.dart';
import 'scenes_pane.dart';
import 'sidekick_screen.dart';
import 'tasks_pane.dart';
import 'track_home_pane.dart';
import 'tracker_screen.dart';
import 'tracks_pane.dart';

class TrackingTab extends ConsumerWidget {
  const TrackingTab({super.key, this.systems = kAllSystems});
  final Set<String> systems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lonelog = systems.contains('lonelog');
    final party = systems.contains('party');
    const rumors = true;
    final partyTools = party;
    return SubtabHost(
      destination: Destination.track,
      scrollable: true,
      tabs: [
        const SubtabDef('home', 'Home'),
        const SubtabDef('loop', 'Loop'),
        const SubtabDef('tasks', 'Tasks'),
        const SubtabDef('scenes', 'Scenes'),
        const SubtabDef('threads', 'Threads'),
        const SubtabDef('encounter', 'Encounter'),
        if (rumors) const SubtabDef('rumors', 'Rumors'),
        const SubtabDef('tracks', 'Tracks'),
        if (partyTools) const SubtabDef('emulator', 'Emulator'),
        if (partyTools) const SubtabDef('sidekick', 'Sidekick'),
        if (partyTools) const SubtabDef('behavior', 'Behavior'),
        if (lonelog) const SubtabDef('resources', 'Resources'),
        if (lonelog) const SubtabDef('battle', 'Battle'),
      ],
      children: [
        const TrackHomePane(),
        const LoopPane(),
        const TasksPane(),
        const ScenesPane(),
        const ThreadsPane(),
        const EncounterScreen(),
        if (rumors) const RumorsPane(),
        const TracksPane(),
        if (partyTools) const PartyEmulatorScreen(),
        if (partyTools) const SidekickScreen(),
        if (partyTools) const BehaviorTablesScreen(),
        if (lonelog) const ResourcesPane(),
        if (lonelog) const BattlePane(),
      ],
    );
  }
}
