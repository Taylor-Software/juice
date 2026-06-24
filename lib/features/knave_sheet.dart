import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

class KnaveSheetView extends ConsumerWidget {
  const KnaveSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  KnaveSheet get _s => character.knave!;

  void _save(WidgetRef ref, KnaveSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(knave: next));

  Widget _stepper(
    String key,
    String label,
    int value, {
    required ValueChanged<int> onSet,
    int min = 0,
    int max = 9999,
  }) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (label.isNotEmpty) Text('$label '),
        IconButton(
          key: Key('$key-minus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove),
          onPressed: value > min ? () => onSet(value - 1) : null,
        ),
        Text('$value'),
        IconButton(
          key: Key('$key-plus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add),
          onPressed: value < max ? () => onSet(value + 1) : null,
        ),
      ]);

  void _rollSave(BuildContext context, String statKey) {
    final score = _s.stats[statKey] ?? 0;
    final roll = Random().nextInt(20) + 1;
    final total = roll + score;
    final result = total >= 11 ? 'Pass' : 'Fail';
    final label = kKnaveStatLabels[statKey] ?? statKey.toUpperCase();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label: $total — $result'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _statBlock(BuildContext context, WidgetRef ref, String key,
      String label, int value, ValueChanged<int> onSet) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: Key('knave-stat-$key-minus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove),
          onPressed: value > 0 ? () => onSet(value - 1) : null,
        ),
        Text('$value'),
        IconButton(
          key: Key('knave-stat-$key-plus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add),
          onPressed: value < 10 ? () => onSet(value + 1) : null,
        ),
      ]),
      IconButton(
        key: Key('knave-save-$key'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.casino_outlined, size: 18),
        tooltip: '$label save (d20+$value >= 11)',
        onPressed: () => _rollSave(context, key),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;

    return ListView(
      key: const Key('knave-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(
              key: const Key('sheet-back'),
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack),
          Expanded(
              child: Text(character.name,
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis)),
        ]),
        Text('Knave', style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('knave-career'),
          initialValue: s.career,
          decoration: const InputDecoration(labelText: 'Career / Background'),
          onChanged: (v) => _save(ref, s.copyWith(career: v)),
        ),
        const SizedBox(height: 8),
        _stepper('knave-level', 'Level', s.level,
            min: 1, max: 20, onSet: (v) => _save(ref, s.copyWith(level: v))),
        const SizedBox(height: 12),
        Text('Ability Scores', style: theme.textTheme.titleMedium),
        const Text(
          'Save: d20 + score >= 11 to pass. Scores are modifiers.',
          style: TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in kKnaveStats)
            _statBlock(
              context,
              ref,
              k,
              kKnaveStatLabels[k]!,
              s.stats[k] ?? 0,
              (v) => _save(ref, s.copyWith(stats: {...s.stats, k: v})),
            ),
        ]),
        const SizedBox(height: 12),
        Text('Hit Points', style: theme.textTheme.titleMedium),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stepper('knave-hp', 'HP', s.currentHp,
              max: s.maxHp, onSet: (v) => _save(ref, s.copyWith(currentHp: v))),
          _stepper('knave-maxhp', 'Max', s.maxHp,
              onSet: (v) => _save(ref, s.copyWith(maxHp: v))),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stepper('knave-ac', 'AC', s.ac,
              onSet: (v) => _save(ref, s.copyWith(ac: v))),
          _stepper('knave-wounds', 'Wounds', s.wounds,
              onSet: (v) => _save(ref, s.copyWith(wounds: v))),
          Text('${s.inventorySlots} slots',
              style: const TextStyle(fontSize: 14)),
        ]),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('knave-coins'),
          initialValue: s.coins,
          decoration: const InputDecoration(labelText: 'Coins (cp/sp/gp)'),
          onChanged: (v) => _save(ref, s.copyWith(coins: v)),
        ),
        const SizedBox(height: 12),
        conditionsSection(context, ref, character, 'knave'),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('knave-notes'),
          initialValue: s.notes,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Notes / Inventory'),
          onChanged: (v) => _save(ref, s.copyWith(notes: v)),
        ),
      ],
    );
  }
}
