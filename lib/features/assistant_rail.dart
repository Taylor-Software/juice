import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle.dart';
import '../engine/suggestions.dart';
import '../shared/destination.dart';
import '../shared/shell_route.dart';
import '../state/providers.dart';
import '../state/suggestions_provider.dart';

/// The assistant strip atop the Journal verb: rule-based suggestion chips
/// (plus the ask-the-GM box, added in a later task).
class AssistantRail extends ConsumerWidget {
  const AssistantRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions =
        ref.watch(suggestionsProvider); // plain List<Suggestion>
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in suggestions)
            ActionChip(
              key: Key('suggest-${s.id}'),
              label: Text(s.label),
              onPressed: () => _onTap(context, ref, s),
            ),
        ],
      ),
    );
  }

  void _onTap(BuildContext context, WidgetRef ref, Suggestion s) {
    final route = ref.read(shellRouteProvider.notifier);
    switch (s.id) {
      case 'roll-oracle':
        final oracle = ref.read(oracleProvider).requireValue;
        final g = fateCheckGenResult(oracle.fateCheck(Likelihood.normal));
        ref.read(journalProvider.notifier).addResult(g.title, g.asText,
            sourceTool: 'fate-check', payload: g.toPayload());
      case 'scene-event':
        final oracle = ref.read(oracleProvider).requireValue;
        final g = oracle.randomEvent();
        ref.read(journalProvider.notifier).addResult(g.title, g.asText,
            sourceTool: 'mythic', payload: g.toPayload());
      case 'start-scene':
        route.goTo(Destination.track, subtab: 'scenes');
      case 'advance-thread':
        route.goTo(Destination.track, subtab: 'threads');
      case 'combat-turn':
        route.goTo(Destination.track, subtab: 'encounter');
      case 'make-move':
        route.goTo(Destination.sheet, subtab: 'moves');
    }
  }
}
