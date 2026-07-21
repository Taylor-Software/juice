import 'package:flutter/material.dart';

import 'behavior_tables_screen.dart';
import 'party_emulator_screen.dart';
import 'sidekick_screen.dart';

/// One Track subtab hosting the three party-tools surfaces — Emulator,
/// Behavior, and Sidekick — behind a segmented switch (was three separate
/// same-weight subtabs). An [IndexedStack] keeps all three mounted so each
/// keeps its state across switches (and dodges the TabBarView loose-constraints
/// gotcha in the tool host).
class PartyToolsPane extends StatefulWidget {
  const PartyToolsPane({super.key, this.initial = 0});

  /// Which inner surface to show first (0 Emulator, 1 Behavior, 2 Sidekick).
  final int initial;

  @override
  State<PartyToolsPane> createState() => _PartyToolsPaneState();
}

class _PartyToolsPaneState extends State<PartyToolsPane> {
  late int _tab = widget.initial.clamp(0, 2);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SegmentedButton<int>(
            key: const Key('party-tools-switch'),
            segments: const [
              ButtonSegment(value: 0, label: Text('Emulator')),
              ButtonSegment(value: 1, label: Text('Behavior')),
              ButtonSegment(value: 2, label: Text('Sidekick')),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: const [
              PartyEmulatorScreen(),
              BehaviorTablesScreen(),
              SidekickScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
