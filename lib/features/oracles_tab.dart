import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/oracle.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import 'fate_screen.dart';
import 'generators_screen.dart';
import 'tables_screen.dart';
import 'moves_screen.dart';

class OraclesTab extends ConsumerWidget {
  const OraclesTab({super.key, required this.oracle, required this.family});
  final Oracle oracle;
  final List<String> family;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = <SubtabDef>[
      const SubtabDef('oracle', 'Oracle'),
      const SubtabDef('generators', 'Generators'),
      const SubtabDef('tables', 'Tables'),
      if (family.isNotEmpty) const SubtabDef('moves', 'Moves'),
    ];
    final children = <Widget>[
      FateScreen(oracle: oracle, initialSection: FateSection.fateCheck),
      // section: null shows ALL generator sections (Story/NPCs/Exploration/
      // Encounters/Details) plus the wilderness-crawl controls in one surface.
      GeneratorsScreen(oracle: oracle),
      TablesScreen(oracle: oracle),
      if (family.isNotEmpty) MovesScreen(rulesetIds: family),
    ];
    return SubtabHost(
      destination: Destination.oracles,
      tabs: tabs,
      children: children,
    );
  }
}
