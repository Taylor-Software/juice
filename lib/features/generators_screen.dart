import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/models.dart';
import '../engine/oracle.dart';
import '../shared/result_card.dart';
import '../state/providers.dart';

/// A named generator the user can tap to run.
class _Gen {
  const _Gen(this.label, this.run);
  final String label;
  final GenResult Function(Oracle o) run;
}

class GeneratorsScreen extends ConsumerStatefulWidget {
  const GeneratorsScreen({super.key, required this.oracle});
  final Oracle oracle;

  @override
  ConsumerState<GeneratorsScreen> createState() => _GeneratorsScreenState();
}

class _GeneratorsScreenState extends ConsumerState<GeneratorsScreen> {
  GenResult? _last;

  static final List<_Gen> _gens = [
    _Gen('New Quest', (o) => o.newQuest()),
    _Gen('New Scene', (o) => o.newScene()),
    _Gen('Random Event', (o) => o.randomEvent()),
    _Gen('Challenge', (o) => o.challenge()),
    _Gen('Pay the Price', (o) => o.payThePrice()),
    _Gen('Major Plot Twist', (o) => o.payThePrice(critical: true)),
    _Gen('NPC', (o) => o.npc()),
    _Gen('NPC Behavior', (o) => o.npcBehavior()),
    _Gen('NPC Behavior (Active)', (o) => o.npcBehavior(skew: 1)),
    _Gen('NPC Behavior (Passive)', (o) => o.npcBehavior(skew: -1)),
    _Gen('NPC Combat', (o) => o.npcCombat()),
    _Gen('Settlement', (o) => o.settlement()),
    _Gen('Natural Hazard', (o) => o.naturalHazard()),
    _Gen('Monster Encounter', (o) => o.monsterEncounter()),
    _Gen('Creature Tracks', (o) => o.creatureTracks()),
    _Gen('Dungeon Name', (o) => o.dungeonName()),
    _Gen('Dungeon Room', (o) => o.dungeonRoom()),
    _Gen('Treasure', (o) => o.treasure()),
    _Gen('Name', (o) => o.generateName()),
    _Gen('Discover Meaning', (o) => o.discoverMeaning()),
    _Gen('Immersion', (o) => o.immersion()),
    _Gen('Plot Point', (o) => o.plotPoint()),
    _Gen('Random Idea', (o) => o.randomIdea()),
    _Gen('Detail', (o) => o.detail()),
    _Gen('Property', (o) => o.property()),
    _Gen('NPC Plot Knowledge', (o) => o.extendedInfo()),
    _Gen('Companion Response', (o) => o.companionResponse()),
    _Gen('NPC Dialog Topic', (o) => o.dialogTopic()),
  ];

  ({String asset, int d10, int d6})? _lastIcon;

  void _run(_Gen g) => setState(() {
        _last = g.run(widget.oracle);
        _lastIcon = null;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _last;
    final crawl = ref.watch(crawlProvider).valueOrNull ?? const CrawlState();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Generators', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        if (last != null) ...[
          ResultCard(
            result: last,
            onLog: () {
              ref.read(journalProvider.notifier).add(last.title, last.asText);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Added to journal')),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
        if (_lastIcon != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Image.asset(_lastIcon!.asset, width: 160, height: 160),
                  const SizedBox(height: 8),
                  Text(
                    'Abstract Icon (d10 ${d10Label(_lastIcon!.d10)}, d6 ${_lastIcon!.d6})',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text('Crawl', style: theme.textTheme.titleMedium),
        if (crawl.envRow != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${widget.oracle.data.table('wilderness_environment')[crawl.envRow! - 1]}'
              '${crawl.lost ? ' — LOST (d6 encounters)' : ''}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: const Text('Wilderness Travel'),
              onPressed: () {
                final s = ref.read(crawlProvider).valueOrNull ?? const CrawlState();
                final r = widget.oracle.wildernessTravel(s);
                ref.read(crawlProvider.notifier).save(r.state);
                setState(() => _last = r.result);
              },
            ),
            ActionChip(
              label: const Text('Dungeon Linger'),
              onPressed: () =>
                  setState(() => _last = widget.oracle.dungeonLinger()),
            ),
            ActionChip(
              label: const Text('NPC Dialog'),
              onPressed: () {
                final s = ref.read(crawlProvider).valueOrNull ?? const CrawlState();
                widget.oracle.restoreDialogPos(s.dialogRow, s.dialogCol);
                final r = widget.oracle.npcDialog();
                final pos = widget.oracle.dialogPos;
                ref.read(crawlProvider.notifier).save(
                    s.copyWith(dialogRow: pos.row, dialogCol: pos.col));
                setState(() => _last = r);
              },
            ),
            ActionChip(
              label: const Text('Reset Crawl'),
              onPressed: () => ref.read(crawlProvider.notifier).reset(),
            ),
            ActionChip(
              label: const Text('Abstract Icon'),
              onPressed: () => setState(() {
                _lastIcon = widget.oracle.abstractIcon();
                _last = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in _gens)
              ActionChip(
                label: Text(g.label),
                onPressed: () => _run(g),
              ),
          ],
        ),
      ],
    );
  }
}
