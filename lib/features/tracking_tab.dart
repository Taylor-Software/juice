import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import 'battle_pane.dart';
import 'behavior_tables_screen.dart';
import 'encounter_screen.dart';
import 'party_emulator_screen.dart';
import 'resources_pane.dart';
import 'rumors_pane.dart';
import 'scenes_pane.dart';
import 'sidekick_screen.dart';
import 'tracker_screen.dart';
import 'tracks_pane.dart';

class TrackingTab extends ConsumerWidget {
  const TrackingTab({super.key, this.systems = kAllSystems});
  final Set<String> systems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lonelog = systems.contains('lonelog');
    final party = systems.contains('party');
    return SubtabHost(
      destination: Destination.track,
      scrollable: true,
      tabs: [
        const SubtabDef('scenes', 'Scenes'),
        const SubtabDef('threads', 'Threads'),
        const SubtabDef('rumors', 'Rumors'),
        const SubtabDef('tracks', 'Tracks'),
        const SubtabDef('encounter', 'Encounter'),
        if (party) const SubtabDef('emulator', 'Emulator'),
        if (party) const SubtabDef('sidekick', 'Sidekick'),
        if (party) const SubtabDef('behavior', 'Behavior'),
        if (lonelog) const SubtabDef('resources', 'Resources'),
        if (lonelog) const SubtabDef('battle', 'Battle'),
      ],
      children: [
        const ScenesPane(),
        const ThreadsPane(),
        const RumorsPane(),
        const TracksPane(),
        const EncounterScreen(),
        if (party) const PartyEmulatorScreen(),
        if (party) const SidekickScreen(),
        if (party) const BehaviorTablesScreen(),
        if (lonelog) const ResourcesPane(),
        if (lonelog) const BattlePane(),
      ],
    );
  }
}
