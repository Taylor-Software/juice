import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle.dart';
import '../features/generate_sheet.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import 'destination.dart';
import 'shell_route.dart';

/// A thin, always-visible play-context bar mounted at the shell level (above
/// the verb body), so the current scene, Chaos factor, default oracle, pinned
/// threads and starred characters stay reachable on every verb — not just the
/// Journal. Reads the [PlayContext] spine: the scene line follows
/// `activeSceneId` when set (falling back to the latest scene entry).
///
/// Was `_CampaignHeader` inside `JournalScreen`; lifted to the shell so it no
/// longer vanishes when switching verbs or when the journal is empty.
class CampaignHeader extends ConsumerWidget {
  const CampaignHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const CampaignSettings();
    final entries = ref.watch(journalProvider).valueOrNull ?? const [];
    final threads = (ref.watch(threadsProvider).valueOrNull ?? const <Thread>[])
        .where((t) => t.open && t.pinned)
        .toList();
    final stars =
        (ref.watch(charactersProvider).valueOrNull ?? const <Character>[])
            .where((c) => c.starred)
            .toList();
    final crawl = ref.watch(crawlProvider).valueOrNull;
    final oracle = ref.watch(oracleProvider).valueOrNull;
    // Current scene: prefer the spine's active pointer, fall back to the latest
    // scene entry (storage newest-first).
    final scene = activeSceneEntry(
        entries, ref.watch(playContextProvider).valueOrNull?.activeSceneId);
    // Chaos belongs to Mythic — show it only when the campaign's profile
    // enables that system.
    final systems =
        ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
            kAllSystems;
    final usesMythic = systems.contains('mythic');
    final theme = Theme.of(context);
    final collapsed = settings.headerCollapsed;
    return Container(
      key: const Key('campaign-header'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.local_fire_department_outlined,
                size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                scene?.title ?? 'No scene yet',
                style: theme.textTheme.labelLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // One-tap roll of the default oracle from any verb — the loop's
            // most frequent action, always reachable (even when collapsed).
            IconButton(
              key: const Key('hdr-quick-roll'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.casino_outlined),
              tooltip: 'Quick roll (${_oracleLabel(settings.defaultOracle)})',
              onPressed: oracle == null
                  ? null
                  : () => _quickRoll(context, ref, oracle,
                      crawl?.chaosFactor ?? 5, settings.defaultOracle),
            ),
            // One-tap tarot draw (art + meaning, logged) when the cards system
            // is on — the rich card oracle reachable from any verb.
            if (systems.contains('cards'))
              IconButton(
                key: const Key('hdr-quick-draw'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.style_outlined),
                tooltip: 'Draw tarot',
                onPressed: oracle == null
                    ? null
                    : () => _quickDraw(context, ref, oracle),
              ),
            IconButton(
              key: const Key('hdr-collapse'),
              visualDensity: VisualDensity.compact,
              icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
              tooltip: collapsed ? 'Expand' : 'Collapse',
              onPressed: () => ref
                  .read(settingsProvider.notifier)
                  .setHeaderCollapsed(!collapsed),
            ),
          ]),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (usesMythic && crawl != null) ...[
                    InputChip(
                      label: Text('Chaos ${crawl.chaosFactor}'),
                      onPressed: null,
                    ),
                    IconButton(
                      key: const Key('hdr-chaos-dec'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: crawl.chaosFactor > 1
                          ? () => ref
                              .read(crawlProvider.notifier)
                              .setChaos(crawl.chaosFactor - 1)
                          : null,
                    ),
                    IconButton(
                      key: const Key('hdr-chaos-inc'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: crawl.chaosFactor < 9
                          ? () => ref
                              .read(crawlProvider.notifier)
                              .setChaos(crawl.chaosFactor + 1)
                          : null,
                    ),
                  ],
                  ActionChip(
                    key: const Key('hdr-oracle'),
                    avatar: const Icon(Icons.casino_outlined, size: 16),
                    label: Text(_oracleLabel(settings.defaultOracle)),
                    onPressed: () => _pickOracle(context, ref, settings),
                  ),
                  for (final t in threads)
                    ActionChip(
                      key: Key('hdr-thread-${t.id}'),
                      avatar: const Icon(Icons.push_pin, size: 14),
                      label: Text(t.title),
                      onPressed: () => ref
                          .read(shellRouteProvider.notifier)
                          .goTo(Destination.track, subtab: 'threads'),
                    ),
                  for (final c in stars)
                    ActionChip(
                      key: Key('hdr-char-${c.id}'),
                      avatar: const Icon(Icons.star, size: 14),
                      label: Text(c.name),
                      onPressed: () => ref
                          .read(shellRouteProvider.notifier)
                          .goTo(Destination.sheet, subtab: 'characters'),
                    ),
                  if (crawl != null && crawl.envRow != null)
                    ActionChip(
                      key: const Key('hdr-crawl'),
                      avatar: const Icon(Icons.explore, size: 14),
                      label:
                          Text(crawl.lost ? 'Wilderness (lost)' : 'Wilderness'),
                      onPressed: () => showGenerateSheet(context),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _oracleLabel(String id) => switch (id) {
        'mythic' => 'Mythic',
        'roll-high' => 'Roll High',
        _ => 'Juice',
      };

  /// Rolls the campaign's default oracle with sensible neutral odds (50/50 /
  /// Unknown) and logs it — a quick yes/no without opening the Ask verb.
  Future<void> _quickDraw(
      BuildContext context, WidgetRef ref, Oracle oracle) async {
    final g =
        await ref.read(decksProvider.notifier).drawAndLog(oracle, tarot: true);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Drew ${g.summary}')));
    }
  }

  void _quickRoll(BuildContext context, WidgetRef ref, Oracle oracle, int chaos,
      String defaultOracle) {
    final GenResult g;
    final String tool;
    switch (defaultOracle) {
      case 'mythic':
        g = oracle.mythicFate(4, chaos); // 50/50 odds
        tool = 'mythic';
      case 'roll-high':
        g = oracle.rollHigh('d100', 3); // Unknown odds
        tool = 'roll-high';
      default:
        g = fateCheckGenResult(oracle.fateCheck(Likelihood.normal));
        tool = 'fate-check';
    }
    ref
        .read(journalProvider.notifier)
        .addResult(g.title, g.asText, sourceTool: tool, payload: g.toPayload());
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(g.summary ?? g.rolls.first.value)));
  }

  Future<void> _pickOracle(
      BuildContext context, WidgetRef ref, CampaignSettings s) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Default oracle'),
        children: [
          for (final o in const ['juice', 'mythic', 'roll-high'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, o),
              child: Text(_oracleLabel(o)),
            ),
        ],
      ),
    );
    if (picked != null) {
      await ref.read(settingsProvider.notifier).setDefaultOracle(picked);
    }
  }
}
