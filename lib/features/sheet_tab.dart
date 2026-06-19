import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/role_tags.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import '../state/providers.dart';
import 'moves_screen.dart';
import 'tracker_screen.dart';

/// The Sheet verb: the character roster, plus Moves for Ironsworn-family
/// campaigns in party mode. With no family active or in GM mode it is just
/// the roster.
class SheetTab extends ConsumerWidget {
  const SheetTab({super.key, required this.family});
  final List<String> family;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeProvider);
    // Bare roster when there's no Ironsworn family OR Moves is mode-hidden.
    if (family.isEmpty || !visibleForMode('moves', mode)) {
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
