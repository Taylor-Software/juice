import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/oracle.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import '../state/providers.dart';
import 'fate_screen.dart';
import 'tables_screen.dart';
import 'lonelog_reference_screen.dart';

class OraclesTab extends ConsumerWidget {
  const OraclesTab({super.key, required this.oracle, this.systems = const {}});
  final Oracle oracle;
  final Set<String> systems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // resolvedSystemProvider depends on the async sessionsProvider; gate on it
    // so SubtabHost is constructed exactly once with the correct initialTabIndex.
    final sessionsAsync = ref.watch(sessionsProvider);
    if (!sessionsAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final lonelog = systems.contains('lonelog');
    final tabs = <SubtabDef>[
      const SubtabDef('oracle', 'Oracle'),
      const SubtabDef('tables', 'Tables'),
      if (lonelog) const SubtabDef('lonelog', 'Lonelog'),
    ];
    final children = <Widget>[
      FateScreen(oracle: oracle, initialSection: FateSection.fateCheck),
      TablesScreen(oracle: oracle),
      if (lonelog) const LonelogReferenceScreen(),
    ];
    // D&D / Shadowdark lean on dice tables, not the yes/no oracle — open Ask
    // on Tables for them; everyone else lands on Oracle.
    final resolved = ref.watch(resolvedSystemProvider);
    final dice = resolved == 'dnd' || resolved == 'shadowdark';
    final initial = dice ? tabs.indexWhere((t) => t.key == 'tables') : 0;
    return SubtabHost(
      destination: Destination.ask,
      tabs: tabs,
      initialTabIndex: initial < 0 ? 0 : initial,
      children: children,
    );
  }
}
