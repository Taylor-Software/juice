import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle_interpreter.dart';
import '../engine/suggestions.dart';
import '../shared/ai_badge.dart';
import '../shared/destination.dart';
import '../shared/shell_route.dart';
import '../state/interpreter.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import '../state/suggestions_provider.dart';
import 'gm_chat_screen.dart';

/// Assistant state that must survive the host panel collapsing — which
/// unmounts this section and disposes its State. The "Next" panel
/// auto-collapses whenever the journal composer takes focus on a phone, i.e.
/// on every keyboard cycle, so State-held values would be lost constantly: the
/// rank cache would re-rank identical play state (one wasted on-device LLM run
/// each time) and the Ask box would drop a half-typed question on the floor.
///
/// File-private, NOT autoDispose, NOT persisted — app-global lifetime, reset on
/// app restart. Same posture as the loop bar's nav-surviving state above.
final _rankCacheProvider = StateProvider<Map<String, RankResult>>((_) => {});
final _rankingSigProvider = StateProvider<String?>((_) => null);
final _askTextProvider = StateProvider<String>((_) => '');

/// The assistant section of the Play screen's "Next" panel: rule-based
/// suggestion chips plus a budget-safe ask-the-Oracle box.
///
/// Owns no header and no collapse state — it renders only when the "Next"
/// panel that hosts it is expanded (see `PlayScreen`), alongside the Solo-Loop
/// controls. It was previously a self-contained rail with its own header and
/// sticky flag stacked directly above the journal feed.
class AssistantSection extends ConsumerStatefulWidget {
  const AssistantSection({super.key});

  @override
  ConsumerState<AssistantSection> createState() => _AssistantSectionState();
}

class _AssistantSectionState extends ConsumerState<AssistantSection> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Re-seed from the unmount-surviving provider (see above).
    _controller.text = ref.read(_askTextProvider);
    _controller.addListener(
        () => ref.read(_askTextProvider.notifier).state = _controller.text);
  }

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
    // Hold the notifiers across the await: the panel can collapse mid-flight,
    // which unmounts this section and invalidates `ref`. The providers are
    // container-owned and NOT autoDispose, so their notifiers stay valid.
    final cache = ref.read(_rankCacheProvider.notifier);
    final inFlight = ref.read(_rankingSigProvider.notifier);
    if (cache.state.containsKey(sig) || inFlight.state == sig) return;
    inFlight.state = sig;
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
    // Write through even if this section was unmounted meanwhile: the call is
    // already paid for, so the result must land in the cache or the next mount
    // re-ranks it. Watching widgets rebuild off the provider — no setState.
    final next = Map<String, RankResult>.from(cache.state)..[sig] = result;
    // Bound the cache — the signature changes on every new journal entry, so
    // keep only the most-recent few (insertion-ordered; drop the oldest).
    while (next.length > 8) {
      next.remove(next.keys.first);
    }
    cache.state = next;
    if (inFlight.state == sig) inFlight.state = null;
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
    final sig = _signature(journal, suggestions, activeSceneId);
    final rankCache = ref.watch(_rankCacheProvider);
    // Mounting IS being visible: the host panel builds this section only while
    // expanded, so no separate visibility gate is needed before ranking.
    if (aiReady &&
        !rankCache.containsKey(sig) &&
        ref.read(_rankingSigProvider) != sig) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeRank(sig, journal, suggestions, activeSceneId);
      });
    }
    final ranked = (aiReady && rankCache[sig] != null)
        ? applyRanking(suggestions, rankCache[sig]!)
        : (chips: suggestions, why: null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Inline rolls (roll-oracle / scene-event) moved to the
              // journal's always-visible dock; this section keeps navigate
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
    );
  }
}
