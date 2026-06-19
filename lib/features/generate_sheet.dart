import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/generator_registry.dart';
import '../engine/models.dart';
import '../engine/oracle.dart';
import '../engine/oracle_data.dart';
import '../shared/result_card.dart';
import '../state/providers.dart';

/// Opens the flavor-generator sheet from the journal composer.
Future<void> showGenerateSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const GenerateSheet(),
    );

/// The "inspire" sheet. Flavor generators (grouped by section) roll and append
/// straight to the journal, closing the sheet. The three visual/stateful
/// generators — Location grid, NPC Dialog walk, Abstract Icon — render their
/// bespoke result inline and keep the sheet open.
class GenerateSheet extends ConsumerStatefulWidget {
  const GenerateSheet({super.key});

  @override
  ConsumerState<GenerateSheet> createState() => _GenerateSheetState();
}

class _GenerateSheetState extends ConsumerState<GenerateSheet> {
  LocationResult? _lastLocation;
  ({String asset, int d10, int d6})? _lastIcon;
  GenResult? _lastDialog;

  void _clearPreviews() {
    _lastLocation = null;
    _lastIcon = null;
    _lastDialog = null;
  }

  void _rollLocation(Oracle oracle) => setState(() {
        _clearPreviews();
        _lastLocation = oracle.rollLocation();
      });

  void _rollAbstractIcon(Oracle oracle) => setState(() {
        _clearPreviews();
        _lastIcon = oracle.abstractIcon();
      });

  Future<void> _rollNpcDialog(Oracle oracle) async {
    final s = await ref.read(crawlProvider.future);
    oracle.restoreDialogPos(s.dialogRow, s.dialogCol);
    final r = oracle.npcDialog();
    final pos = oracle.dialogPos;
    await ref
        .read(crawlProvider.notifier)
        .save(s.copyWith(dialogRow: pos.row, dialogCol: pos.col));
    setState(() {
      _clearPreviews();
      _lastDialog = r;
    });
  }

  void _logResult(GenResult g, GenSection section) {
    ref.read(journalProvider.notifier).addResult(g.title, g.asText,
        sourceTool: sourceToolFor(section), payload: g.toPayload());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added to journal')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final oracle = ref.watch(oracleProvider).valueOrNull;
    if (oracle == null) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('Generators still loading…')),
      );
    }
    final theme = Theme.of(context);
    final bySection = <GenSection, List<GeneratorDef>>{};
    for (final g in flavorGenerators) {
      bySection.putIfAbsent(g.section, () => []).add(g);
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_lastLocation != null) ...[
              _LocationCard(
                result: _lastLocation!,
                data: oracle.data,
                onLog: () {
                  final loc = _lastLocation!;
                  _logResult(
                    GenResult(title: 'Location', rolls: [
                      Roll(
                          label: 'Location',
                          value: loc.label,
                          detail: '${loc.roll}'),
                    ]),
                    GenSection.exploration,
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
            if (_lastDialog != null) ...[
              ResultCard(
                result: _lastDialog!,
                onLog: () => _logResult(_lastDialog!, GenSection.npcs),
              ),
              const SizedBox(height: 12),
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
                        'Abstract Icon (d10 ${d10Label(_lastIcon!.d10)}, '
                        'd6 ${_lastIcon!.d6})',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child:
                  Text('Visual & Stateful', style: theme.textTheme.labelMedium),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  key: const Key('gen-location'),
                  label: const Text('Location'),
                  onPressed: () => _rollLocation(oracle),
                ),
                ActionChip(
                  key: const Key('gen-npc-dialog'),
                  label: const Text('NPC Dialog'),
                  onPressed: () => _rollNpcDialog(oracle),
                ),
                ActionChip(
                  key: const Key('gen-abstract-icon'),
                  label: const Text('Abstract Icon'),
                  onPressed: () => _rollAbstractIcon(oracle),
                ),
              ],
            ),
            for (final section in GenSection.values)
              if (bySection[section]?.isNotEmpty ?? false) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child:
                      Text(section.label, style: theme.textTheme.labelMedium),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in bySection[section]!)
                      ActionChip(
                        key: Key('gen-${g.label}'),
                        label: Text(g.label),
                        onPressed: () {
                          final r = g.run(oracle);
                          ref.read(journalProvider.notifier).addResult(
                              r.title, r.asText,
                              sourceTool: sourceToolFor(g.section),
                              payload: r.toPayload());
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              ],
          ],
        ),
      ),
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
