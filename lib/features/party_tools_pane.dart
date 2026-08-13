import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'behavior_tables_screen.dart';
import 'party_emulator_screen.dart';
import 'sidekick_screen.dart';

/// The Track party subtab shows ONE party-tools paradigm — Emulator,
/// Behavior, or Sidekick — chosen per campaign (SessionMeta.partyTool, set
/// in the creation wizard or Campaigns → Edit systems). The old in-pane
/// SegmentedButton stacked all three behind a switch; the paradigms answer
/// the same question, so the choice is campaign config, not pane state.
/// Unchosen paradigms keep their persisted state for a later switch back.
class PartyToolsPane extends ConsumerWidget {
  const PartyToolsPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(partyToolProvider)) {
      'behavior' => const BehaviorTablesScreen(),
      'sidekick' => const SidekickScreen(),
      _ => const PartyEmulatorScreen(),
    };
  }
}
