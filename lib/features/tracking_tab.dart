import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/role_tags.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import '../state/providers.dart';
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
    final mode = ref.watch(modeProvider);
    final rumors = visibleForMode('rumors', mode);
    final partyTools = party &&
        visibleForMode('emulator',
            mode); // emulator/sidekick/behavior share the party role
    return SubtabHost(
      destination: Destination.track,
      scrollable: true,
      tabs: [
        const SubtabDef('scenes', 'Scenes'),
        const SubtabDef('threads', 'Threads'),
        if (rumors) const SubtabDef('rumors', 'Rumors'),
        const SubtabDef('tracks', 'Tracks'),
        const SubtabDef('encounter', 'Encounter'),
        if (partyTools) const SubtabDef('emulator', 'Emulator'),
        if (partyTools) const SubtabDef('sidekick', 'Sidekick'),
        if (partyTools) const SubtabDef('behavior', 'Behavior'),
        if (lonelog) const SubtabDef('resources', 'Resources'),
        if (lonelog) const SubtabDef('battle', 'Battle'),
      ],
      children: [
        const ScenesPane(),
        const ThreadsPane(),
        if (rumors) const RumorsPane(),
        const TracksPane(),
        const EncounterScreen(),
        if (partyTools) const PartyEmulatorScreen(),
        if (partyTools) const SidekickScreen(),
        if (partyTools) const BehaviorTablesScreen(),
        if (lonelog) const ResourcesPane(),
        if (lonelog) const BattlePane(),
      ],
    );
  }
}
