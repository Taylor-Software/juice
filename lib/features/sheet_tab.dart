import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import 'moves_screen.dart';
import 'tracker_screen.dart';

/// The Sheet verb: the character roster, plus Moves for Ironsworn-family
/// campaigns. With no family active it is just the roster.
class SheetTab extends ConsumerWidget {
  const SheetTab({super.key, required this.family});
  final List<String> family;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Bare roster when there's no Ironsworn family.
    if (family.isEmpty) {
      return const CharactersPane();
    }
    return SubtabHost(
      destination: Destination.sheet,
      tabs: const [
        SubtabDef('characters', 'Characters'),
        SubtabDef('moves', 'Moves'),
      ],
      children: [
        const CharactersPane(),
        MovesScreen(rulesetIds: family),
      ],
    );
  }
}
