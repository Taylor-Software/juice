import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/oracle.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';

class OraclesTab extends ConsumerWidget {
  const OraclesTab({super.key, required this.oracle, required this.family});
  final Oracle oracle;
  final List<String> family;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SubtabHost(
      destination: Destination.oracles,
      tabs: [
        SubtabDef('oracle', 'Oracle'),
        SubtabDef('generators', 'Generators'),
        SubtabDef('tables', 'Tables'),
      ],
      children: [
        Center(child: Text('Oracle')),
        Center(child: Text('Generators')),
        Center(child: Text('Tables')),
      ],
    );
  }
}
