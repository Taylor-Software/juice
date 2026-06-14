import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import 'party_emulator_screen.dart';
import 'sidekick_screen.dart';
import 'behavior_tables_screen.dart';

class PartyTab extends ConsumerWidget {
  const PartyTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SubtabHost(
      destination: Destination.party,
      tabs: [
        SubtabDef('emulator', 'Emulator'),
        SubtabDef('sidekick', 'Sidekick'),
        SubtabDef('behavior', 'Behavior'),
      ],
      children: [
        PartyEmulatorScreen(),
        SidekickScreen(),
        BehaviorTablesScreen(),
      ],
    );
  }
}
