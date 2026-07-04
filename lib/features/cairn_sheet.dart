import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

class CairnSheetView extends ConsumerWidget {
  const CairnSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  CairnSheet get _s => character.cairn!;

  void _save(WidgetRef ref, CairnSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(cairn: next));

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
    final score = statKey == 'str'
        ? _s.str
        : statKey == 'dex'
            ? _s.dex
            : _s.wil;
    final roll = Random().nextInt(20) + 1;
    final result = roll <= score ? 'Pass' : 'Fail';
    final label = kCairnStatLabels[statKey] ?? statKey.toUpperCase();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label save: $roll — $result'),
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
          key: Key('cairn-stat-$key-minus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove),
          onPressed: value > 3 ? () => onSet(value - 1) : null,
        ),
        Text('$value'),
        IconButton(
          key: Key('cairn-stat-$key-plus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add),
          onPressed: value < 18 ? () => onSet(value + 1) : null,
        ),
      ]),
      IconButton(
        key: Key('cairn-save-$key'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.casino_outlined, size: 18),
        tooltip: '$label save (d20 ≤ $value)',
        onPressed: () => _rollSave(context, key),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;

    return ListView(
      key: const Key('cairn-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        sheetNameHeader(context, ref, character,
            onBack: onBack, nameKey: 'cairn-name'),
        Text('Cairn', style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),
        DropdownButton<String>(
          key: const Key('cairn-background'),
          isExpanded: true,
          value: kCairnBackgrounds.contains(s.background)
              ? s.background
              : kCairnBackgrounds.first,
          items: [
            for (final b in kCairnBackgrounds)
              DropdownMenuItem(value: b, child: Text(b)),
          ],
          onChanged: (v) =>
              v == null ? null : _save(ref, s.copyWith(background: v)),
        ),
        const SizedBox(height: 12),
        Text('Ability Scores', style: theme.textTheme.titleMedium),
        const Text(
          'Save: roll d20 equal or under stat to pass.',
          style: TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 4),
        Row(children: [
          _statBlock(context, ref, 'str', 'STR', s.str,
              (v) => _save(ref, s.copyWith(str: v))),
          const SizedBox(width: 8),
          _statBlock(context, ref, 'dex', 'DEX', s.dex,
              (v) => _save(ref, s.copyWith(dex: v))),
          const SizedBox(width: 8),
          _statBlock(context, ref, 'wil', 'WIL', s.wil,
              (v) => _save(ref, s.copyWith(wil: v))),
        ]),
        const SizedBox(height: 12),
        Text('Hit Protection', style: theme.textTheme.titleMedium),
        const Text(
          'Avoidance and luck; not physical health. At 0 HP, excess damage reduces STR.',
          style: TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stepper('cairn-hp', 'HP', s.currentHp,
              max: s.maxHp, onSet: (v) => _save(ref, s.copyWith(currentHp: v))),
          _stepper('cairn-maxhp', 'Max', s.maxHp,
              onSet: (v) => _save(ref, s.copyWith(maxHp: v))),
          _stepper('cairn-armor', 'Armor', s.armor,
              min: 0, max: 3, onSet: (v) => _save(ref, s.copyWith(armor: v))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Checkbox(
            key: const Key('cairn-deprived'),
            value: s.deprived,
            onChanged: (v) => _save(ref, s.copyWith(deprived: v ?? false)),
          ),
          const Text('Deprived'),
          const SizedBox(width: 4),
          const Flexible(
              child: Text('(cannot recover HP or ability scores)',
                  style: TextStyle(fontSize: 11))),
        ]),
        _stepper('cairn-fatigue', 'Fatigue slots', s.fatigue,
            max: 10, onSet: (v) => _save(ref, s.copyWith(fatigue: v))),
        const SizedBox(height: 12),
        DebouncedTextField(
          key: const Key('cairn-coins'),
          initialValue: s.coins,
          label: 'Coins (gp/sp/cp)',
          onSave: (v) => _save(ref, s.copyWith(coins: v)),
        ),
        const SizedBox(height: 12),
        conditionsSection(context, ref, character, 'cairn'),
        const SizedBox(height: 12),
        DebouncedTextField(
          key: const Key('cairn-notes'),
          initialValue: s.notes,
          maxLines: 4,
          label: 'Notes / Inventory',
          onSave: (v) => _save(ref, s.copyWith(notes: v)),
        ),
      ],
    );
  }
}
