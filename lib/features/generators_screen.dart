import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/models.dart';
import '../engine/oracle.dart';
import '../engine/oracle_data.dart';
import '../shared/result_card.dart';
import '../state/providers.dart';

/// Activity grouping for the launcher; each generator lives in exactly one.
enum GenSection { story, npcs, exploration, encounters, details }

extension GenSectionLabel on GenSection {
  String get label => switch (this) {
        GenSection.story => 'Story & Scenes',
        GenSection.npcs => 'NPCs & Dialog',
        GenSection.exploration => 'Exploration',
        GenSection.encounters => 'Encounters & Combat',
        GenSection.details => 'Names & Details',
      };
}

/// A named generator the user can tap to run.
class _Gen {
  const _Gen(this.label, this.section, this.run);
  final String label;
  final GenSection section;
  final GenResult Function(Oracle o) run;
}

class GeneratorsScreen extends ConsumerStatefulWidget {
  const GeneratorsScreen({super.key, required this.oracle, this.section});
  final Oracle oracle;

  /// When non-null, show only this section's generators; null = everything.
  final GenSection? section;

  static List<String> labelsFor(GenSection s) => _GeneratorsScreenState._gens
      .where((g) => g.section == s)
      .map((g) => g.label)
      .toList();

  @override
  ConsumerState<GeneratorsScreen> createState() => _GeneratorsScreenState();
}

class _GeneratorsScreenState extends ConsumerState<GeneratorsScreen> {
  GenResult? _last;

  /// Registry tool id for entries logged from this screen (open-in-tool).
  String get _sourceTool => switch (widget.section) {
        GenSection.story => 'gen-story',
        GenSection.npcs => 'gen-npcs',
        GenSection.exploration => 'gen-exploration',
        GenSection.encounters => 'gen-encounters',
        GenSection.details || null => 'gen-details',
      };

  static final List<_Gen> _gens = [
    _Gen('New Quest', GenSection.story, (o) => o.newQuest()),
    _Gen('New Scene', GenSection.story, (o) => o.newScene()),
    _Gen('Random Event', GenSection.story, (o) => o.randomEvent()),
    _Gen('Challenge', GenSection.story, (o) => o.challenge()),
    _Gen('Pay the Price', GenSection.story, (o) => o.payThePrice()),
    _Gen('Major Plot Twist', GenSection.story,
        (o) => o.payThePrice(critical: true)),
    _Gen('NPC', GenSection.npcs, (o) => o.npc()),
    _Gen('NPC Behavior', GenSection.npcs, (o) => o.npcBehavior()),
    _Gen('NPC Behavior (Active)', GenSection.npcs,
        (o) => o.npcBehavior(skew: 1)),
    _Gen('NPC Behavior (Passive)', GenSection.npcs,
        (o) => o.npcBehavior(skew: -1)),
    _Gen('NPC Combat', GenSection.npcs, (o) => o.npcCombat()),
    _Gen('Settlement', GenSection.exploration, (o) => o.settlement()),
    _Gen('Natural Hazard', GenSection.exploration, (o) => o.naturalHazard()),
    _Gen('Monster Encounter', GenSection.encounters,
        (o) => o.monsterEncounter()),
    _Gen('Creature Tracks', GenSection.encounters, (o) => o.creatureTracks()),
    _Gen('Dungeon Name', GenSection.exploration, (o) => o.dungeonName()),
    _Gen('Dungeon Room', GenSection.exploration, (o) => o.dungeonRoom()),
    _Gen('Treasure', GenSection.details, (o) => o.treasure()),
    _Gen('Name', GenSection.details, (o) => o.generateName()),
    _Gen('Discover Meaning', GenSection.details, (o) => o.discoverMeaning()),
    _Gen('Immersion', GenSection.details, (o) => o.immersion()),
    _Gen('Plot Point', GenSection.story, (o) => o.plotPoint()),
    _Gen('Random Idea', GenSection.details, (o) => o.randomIdea()),
    _Gen('Detail', GenSection.details, (o) => o.detail()),
    _Gen('Property', GenSection.details, (o) => o.property()),
    _Gen('NPC Plot Knowledge', GenSection.npcs, (o) => o.extendedInfo()),
    _Gen('Companion Response', GenSection.npcs, (o) => o.companionResponse()),
    _Gen('NPC Dialog Topic', GenSection.npcs, (o) => o.dialogTopic()),
  ];

  ({String asset, int d10, int d6})? _lastIcon;
  LocationResult? _lastLocation;

  void _run(_Gen g) => setState(() {
        _last = g.run(widget.oracle);
        _lastIcon = null;
        _lastLocation = null;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _last;
    final crawl = ref.watch(crawlProvider).valueOrNull ?? const CrawlState();
    final section = widget.section;
    final showCrawl = section == null || section == GenSection.exploration;
    final showNpcDialog = section == null || section == GenSection.npcs;
    final showAbstractIcon = section == null || section == GenSection.details;
    final gens =
        section == null ? _gens : _gens.where((g) => g.section == section);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(section?.label ?? 'Generators',
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        if (last != null) ...[
          ResultCard(
            result: last,
            onLog: () {
              ref.read(journalProvider.notifier).addResult(
                  last.title, last.asText,
                  sourceTool: _sourceTool, payload: last.toPayload());
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Added to journal')),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
        if (_lastLocation != null) ...[
          _LocationCard(
            result: _lastLocation!,
            data: widget.oracle.data,
            onLog: () {
              final loc = _lastLocation!;
              final g = GenResult(title: 'Location', rolls: [
                Roll(
                    label: 'Location', value: loc.label, detail: '${loc.roll}'),
              ]);
              ref.read(journalProvider.notifier).addResult(g.title, g.asText,
                  sourceTool: _sourceTool, payload: g.toPayload());
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
        if (showCrawl) ...[
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
        ],
        if (showCrawl || showNpcDialog || showAbstractIcon) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (showCrawl) ...[
                ActionChip(
                  label: const Text('Wilderness Travel'),
                  onPressed: () {
                    final s = ref.read(crawlProvider).valueOrNull ??
                        const CrawlState();
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
                  key: const Key('gen-location'),
                  label: const Text('Location'),
                  onPressed: () => setState(() {
                    _lastLocation = widget.oracle.rollLocation();
                    _last = null;
                    _lastIcon = null;
                  }),
                ),
              ],
              if (showNpcDialog)
                ActionChip(
                  label: const Text('NPC Dialog'),
                  onPressed: () {
                    final s = ref.read(crawlProvider).valueOrNull ??
                        const CrawlState();
                    widget.oracle.restoreDialogPos(s.dialogRow, s.dialogCol);
                    final r = widget.oracle.npcDialog();
                    final pos = widget.oracle.dialogPos;
                    ref.read(crawlProvider.notifier).save(
                        s.copyWith(dialogRow: pos.row, dialogCol: pos.col));
                    setState(() => _last = r);
                  },
                ),
              if (showCrawl)
                ActionChip(
                  label: const Text('Reset Crawl'),
                  onPressed: () => ref.read(crawlProvider.notifier).reset(),
                ),
              if (showAbstractIcon)
                ActionChip(
                  label: const Text('Abstract Icon'),
                  onPressed: () => setState(() {
                    _lastIcon = widget.oracle.abstractIcon();
                    _last = null;
                    _lastLocation = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in gens)
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

/// Result card for the Location grid roll: 5x5 compass grid with the rolled
/// cell highlighted, edge labels, and the standard add-to-journal action.
class _LocationCard extends StatelessWidget {
  const _LocationCard(
      {required this.result, required this.data, required this.onLog});
  final LocationResult result;
  final OracleData data;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final grid = Column(
      key: const Key('location-grid'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < data.locationRows; r++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var c = 0; c < data.locationCols; c++)
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: r == result.row && c == result.col
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                ),
            ],
          ),
      ],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Location', style: theme.textTheme.titleMedium),
                IconButton(
                  key: const Key('location-log'),
                  tooltip: 'Add to journal',
                  icon: const Icon(Icons.bookmark_add_outlined),
                  onPressed: onLog,
                ),
              ],
            ),
            Text('North', style: theme.textTheme.bodySmall),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('West', style: theme.textTheme.bodySmall),
                const SizedBox(width: 8),
                grid,
                const SizedBox(width: 8),
                Text('East', style: theme.textTheme.bodySmall),
              ],
            ),
            Text('South', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Text('${result.label} (${result.roll})',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
