import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/emulator_data.dart';
import '../engine/party_emulator.dart';
import '../state/providers.dart';

/// Behavior Tables — all 13 Triple-O spark + specific d66 tables and the
/// zine's spark combos, rollable as chips (party emulator phase 1).
class BehaviorTablesScreen extends ConsumerStatefulWidget {
  const BehaviorTablesScreen({super.key});

  @override
  ConsumerState<BehaviorTablesScreen> createState() =>
      _BehaviorTablesScreenState();
}

class _BehaviorTablesScreenState extends ConsumerState<BehaviorTablesScreen> {
  final Dice _dice = Dice();
  List<TableRollResult>? _last;

  static const _labels = {
    'action': 'Action',
    'focus': 'Focus',
    'method': 'Method',
    'disposition': 'Disposition',
    'motivation': 'Motivation',
    'dynamics': 'Dynamics',
    'combat': 'Combat',
    'social': 'Social',
    'exploration': 'Exploration',
    'delving': 'Delving',
    'interpretation': 'Interpretation',
    'downtime': 'Downtime',
    'planning': 'Planning',
  };

  /// The zine's suggested spark pairings (Triple-O p33).
  static const _combos = [
    ['action', 'focus'],
    ['action', 'method'],
    ['disposition', 'motivation'],
  ];

  String _title(List<TableRollResult> rolls) =>
      'Behavior: ${rolls.map((r) => _labels[r.table]).join(' + ')}';

  void _roll(EmulatorData data, List<String> tables) =>
      setState(() => _last = rollCombo(data, tables, _dice));

  @override
  Widget build(BuildContext context) {
    final emulator = ref.watch(emulatorDataProvider);
    return emulator.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load emulator data:\n$e')),
      data: (data) => _body(context, data),
    );
  }

  Widget _body(BuildContext context, EmulatorData data) {
    final theme = Theme.of(context);
    final last = _last;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Behavior Tables', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        if (last != null) ...[
          _resultCard(theme, last),
          const SizedBox(height: 16),
        ],
        Text('Spark', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _chips(data, data.sparkNames),
        const SizedBox(height: 16),
        Text('Specific', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _chips(data, data.specificNames),
        const SizedBox(height: 16),
        Text('Combos', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final combo in _combos)
              ActionChip(
                key: Key('bt-combo-${combo.join('-')}'),
                label: Text(combo.map((t) => _labels[t]).join(' + ')),
                onPressed: () => _roll(data, combo),
              ),
          ],
        ),
        const SizedBox(height: 24),
        for (final line in data.attribution)
          Text(
            line,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _chips(EmulatorData data, List<String> names) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final name in names)
            ActionChip(
              key: Key('bt-$name'),
              label: Text(_labels[name]!),
              onPressed: () => _roll(data, [name]),
            ),
        ],
      );

  Widget _resultCard(ThemeData theme, List<TableRollResult> rolls) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child:
                        Text(_title(rolls), style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    key: const Key('bt-log'),
                    tooltip: 'Add to journal',
                    icon: const Icon(Icons.bookmark_add_outlined),
                    onPressed: () => _log(rolls),
                  ),
                ],
              ),
              for (final r in rolls)
                Padding(
                  key: Key('bt-roll-${r.table}'),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 132,
                        child: Text(
                          '${_labels[r.table]} (${r.key})',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(
                        child: Text(r.text, style: theme.textTheme.bodyLarge),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

  void _log(List<TableRollResult> rolls) {
    final body = rolls
        .map((r) => '${_labels[r.table]} (${r.key}): ${r.text}')
        .join('\n');
    ref.read(journalProvider.notifier).add(_title(rolls), body);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added to journal')),
    );
  }
}
