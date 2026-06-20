import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle.dart';
import '../engine/oracle_interpreter.dart';
import '../engine/suggestions.dart';
import '../shared/destination.dart';
import '../shared/shell_route.dart';
import '../state/interpreter.dart';
import '../state/providers.dart';
import '../state/suggestions_provider.dart';

/// The assistant strip atop the Journal verb: rule-based suggestion chips
/// plus a budget-safe ask-the-GM box.
class AssistantRail extends ConsumerStatefulWidget {
  const AssistantRail({super.key});

  @override
  ConsumerState<AssistantRail> createState() => _AssistantRailState();
}

class _AssistantRailState extends ConsumerState<AssistantRail> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;
  // Collapsed by default: a thin header keeps the journal primary; one tap
  // reveals the suggestion chips + ask-the-GM box.
  bool _expanded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    final service = ref.read(interpreterServiceProvider);
    if (service.status.value.phase != InterpreterPhase.ready) {
      setState(() => _error = 'Assistant not ready.');
      return;
    }
    final entries = ref.read(journalProvider).valueOrNull ?? const [];
    final scene = entries
        .where((e) => e.kind == JournalKind.scene)
        .map((e) => e.title)
        .firstOrNull;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final answer =
          await service.askGm(AskGmSeed(question: q, sceneTitle: scene));
      await ref
          .read(journalProvider.notifier)
          .addResult('Ask the GM', 'Q: $q\n\n$answer', sourceTool: 'ask-gm');
      if (mounted) _controller.clear();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the assistant.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onTap(Suggestion s) {
    final route = ref.read(shellRouteProvider.notifier);
    switch (s.id) {
      case 'roll-oracle':
        final oracle = ref.read(oracleProvider).valueOrNull;
        if (oracle == null) return; // oracle data still loading: skip safely
        final g = fateCheckGenResult(oracle.fateCheck(Likelihood.normal));
        ref.read(journalProvider.notifier).addResult(g.title, g.asText,
            sourceTool: 'fate-check', payload: g.toPayload());
      case 'scene-event':
        final oracle = ref.read(oracleProvider).valueOrNull;
        if (oracle == null) return; // oracle data still loading: skip safely
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
      case 'develop-rumor':
        route.goTo(Destination.track, subtab: 'rumors');
      case 'seed-npc':
        route.goTo(Destination.sheet);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggestions =
        ref.watch(suggestionsProvider); // plain List<Suggestion>
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thin always-present header: tap to expand/collapse the assistant.
        Semantics(
          button: true,
          label: _expanded ? 'Collapse assistant' : 'Expand assistant',
          child: InkWell(
            key: const Key('assistant-expand'),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  const Text('Assistant'),
                  const Spacer(),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18),
                ],
              ),
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in suggestions)
                      ActionChip(
                        key: Key('suggest-${s.id}'),
                        label: Text(s.label),
                        onPressed: () => _onTap(s),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('ask-gm-field'),
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'Ask the GM…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _busy ? null : _ask(),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      key: const Key('ask-gm-send'),
                      icon: const Icon(Icons.send),
                      tooltip: 'Ask the GM',
                      onPressed: _busy ? null : _ask,
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _error!,
                      style: TextStyle(
                          color: theme.colorScheme.error, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
