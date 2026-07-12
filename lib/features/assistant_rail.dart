import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle_interpreter.dart';
import '../engine/suggestions.dart';
import '../shared/ai_badge.dart';
import '../shared/design_tokens.dart';
import '../shared/destination.dart';
import '../shared/shell_route.dart';
import '../state/interpreter.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import '../state/suggestions_provider.dart';
import 'gm_chat_screen.dart';

/// The assistant strip atop the Journal verb: rule-based suggestion chips
/// plus a budget-safe ask-the-GM box.
class AssistantRail extends ConsumerStatefulWidget {
  const AssistantRail({super.key});

  @override
  ConsumerState<AssistantRail> createState() => _AssistantRailState();
}

class _AssistantRailState extends ConsumerState<AssistantRail> {
  final TextEditingController _controller = TextEditingController();

  // LLM ranking, cached by a play-state signature so we call the model only
  // when the state actually changes. Empty cached result = keep rule order.
  final Map<String, RankResult> _rankCache = {};
  String? _rankingSig; // signature currently in flight

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _signature(List<JournalEntry> journal, List<Suggestion> candidates,
      String? activeSceneId) {
    // Coarsen rank-invalidation: only the newest semantically-meaningful entry
    // (a scene or an oracle result) re-queues the LLM, not every capture note.
    final top = journal
            .where((e) =>
                e.kind == JournalKind.scene || e.kind == JournalKind.result)
            .firstOrNull
            ?.id ??
        '';
    final scene = activeSceneEntry(journal, activeSceneId)?.id ?? '';
    return '$top|$scene|${candidates.map((s) => s.id).join(',')}';
  }

  Future<void> _maybeRank(String sig, List<JournalEntry> journal,
      List<Suggestion> candidates, String? activeSceneId) async {
    if (_rankCache.containsKey(sig) || _rankingSig == sig) return;
    _rankingSig = sig;
    final scene =
        activeSceneEntry(journal, activeSceneId) ?? journal.firstOrNull;
    final settings =
        ref.read(settingsProvider).valueOrNull ?? const CampaignSettings();
    final seed = RankSuggestionsSeed(
      candidates: [for (final s in candidates) (id: s.id, label: s.label)],
      genre: settings.genre,
      tone: settings.tone,
      systemPrimer: ref.read(systemPrimerProvider),
      sceneTitle: scene == null
          ? null
          : (scene.title.isEmpty ? scene.body : scene.title),
      activeCharacter: ref.read(activeCharacterLineProvider),
      journalContext: scene == null ? const [] : recallLines(journal, scene),
    );
    RankResult result;
    try {
      result = await ref.read(interpreterServiceProvider).rankSuggestions(seed);
    } catch (_) {
      result = const RankResult(); // fall back to rule order; don't retry-loop
    }
    if (!mounted) return;
    setState(() {
      _rankCache[sig] = result;
      if (_rankingSig == sig) _rankingSig = null;
      // Bound the cache — the signature changes on every new journal entry, so
      // keep only the most-recent few (insertion-ordered; drop the oldest).
      while (_rankCache.length > 8) {
        _rankCache.remove(_rankCache.keys.first);
      }
    });
  }

  Future<void> _ask() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    _controller.clear();
    // The box now opens the persisted multi-turn GM chat (manual save, no
    // auto-log), seeded with this first message.
    await showGmChat(context, initialMessage: q);
  }

  void _onTap(Suggestion s) {
    final route = ref.read(shellRouteProvider.notifier);
    switch (s.id) {
      // Inline rolls (roll-oracle / scene-event) now live in the journal's
      // always-visible InlineRollDock; the rail renders only navigate chips.
      // These arms are kept as a defensive delegate to the shared dispatch so
      // nothing breaks if an inline chip ever surfaces here again.
      case 'roll-oracle':
      case 'scene-event':
        final oracle = ref.read(oracleProvider).valueOrNull;
        if (oracle == null) return; // oracle data still loading: skip safely
        rollInlineSuggestion(ref, oracle, s);
      case 'start-scene':
        route.goTo(Destination.track, subtab: 'scenes');
      case 'advance-thread':
        route.goTo(Destination.track, subtab: 'threads');
      case 'roll-tally':
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
    // The Ask-the-GM box is AI; hidden until the model is downloaded AND
    // enabled in Settings. Rule-based suggestion chips stay regardless.
    final aiReady = ref.watch(aiReadyProvider);
    final theme = Theme.of(context);
    final journal =
        ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final activeSceneId =
        ref.watch(playContextProvider).valueOrNull?.activeSceneId;
    final compact = MediaQuery.sizeOf(context).width < kCompactWidth;
    // Sticky user choice wins; unset defaults open on wide screens (chips are
    // the new-user on-ramp) and collapsed on phones (the journal needs the
    // space). While the composer has focus on a phone, render collapsed
    // regardless — the keyboard is already eating half the viewport.
    final stored = ref.watch(assistantRailExpandedProvider).valueOrNull;
    final typing = compact && ref.watch(journalComposerFocusProvider);
    final expanded = (stored ?? !compact) && !typing;
    final sig = _signature(journal, suggestions, activeSceneId);
    if (expanded &&
        aiReady &&
        !_rankCache.containsKey(sig) &&
        _rankingSig != sig) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeRank(sig, journal, suggestions, activeSceneId);
      });
    }
    final ranked = (aiReady && _rankCache[sig] != null)
        ? applyRanking(suggestions, _rankCache[sig]!)
        : (chips: suggestions, why: null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thin always-present header: tap to expand/collapse the assistant.
        Semantics(
          button: true,
          label: expanded ? 'Collapse assistant' : 'Expand assistant',
          child: InkWell(
            key: const Key('assistant-expand'),
            onTap: () {
              ref
                  .read(assistantRailExpandedProvider.notifier)
                  .setExpanded(!expanded);
              // On a phone the rail and the loop bar never stack expanded —
              // opening one closes the other (both sit above the same
              // already-short journal).
              if (!expanded && compact) {
                ref.read(loopBarExpandedProvider.notifier).setExpanded(false);
              }
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  const Text('Assistant'),
                  const Spacer(),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Inline rolls (roll-oracle / scene-event) moved to the
                    // journal's always-visible dock; the rail keeps navigate
                    // chips only.
                    for (final s in ranked.chips
                        .where((s) => s.action == SuggestionAction.navigate))
                      ActionChip(
                        key: Key('suggest-${s.id}'),
                        label: Text(s.label),
                        onPressed: () => _onTap(s),
                      ),
                  ],
                ),
                if (ranked.why != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('💡 ${ranked.why}',
                        key: const Key('suggest-why'),
                        style: theme.textTheme.bodySmall),
                  ),
                if (aiReady) ...[
                  const SizedBox(height: 8),
                  const AiBadge(label: 'Ask the Oracle'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('ask-gm-field'),
                          controller: _controller,
                          decoration: const InputDecoration(
                            hintText: 'Ask the Oracle…',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _ask(),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        key: const Key('ask-gm-send'),
                        icon: const Icon(Icons.send),
                        tooltip: 'Ask the Oracle',
                        onPressed: _ask,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
