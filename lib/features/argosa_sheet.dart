import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

class ArgosaSheetView extends ConsumerWidget {
  const ArgosaSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  ArgosaSheet get _s => character.argosa!;

  void _save(WidgetRef ref, ArgosaSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(argosa: next));

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

  void _roll(BuildContext context, String statKey) {
    final score = _s.stats[statKey] ?? 10;
    final half = score ~/ 2;
    final roll = Random().nextInt(20) + 1;
    final result = roll <= half
        ? 'Great Success'
        : roll <= score
            ? 'Success'
            : 'Failure';
    final label = kArgosaStatLabels[statKey] ?? statKey;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label: $roll — $result'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;
    final isStaggered =
        s.maxHp > 0 && s.currentHp > 0 && s.currentHp * 2 <= s.maxHp;

    return ListView(
      key: const Key('argosa-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        sheetNameHeader(context, ref, character,
            onBack: onBack, nameKey: 'argosa-name'),
        Text('Tales of Argosa', style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),
        DropdownButton<String>(
          key: const Key('argosa-class'),
          isExpanded: true,
          value: kArgosaClasses.contains(s.className)
              ? s.className
              : kArgosaClasses.first,
          items: [
            for (final c in kArgosaClasses)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) =>
              v == null ? null : _save(ref, s.copyWith(className: v)),
        ),
        _stepper('argosa-level', 'Level', s.level,
            min: 1, max: 9, onSet: (v) => _save(ref, s.copyWith(level: v))),
        const SizedBox(height: 12),
        Text('Stats', style: theme.textTheme.titleMedium),
        const Text(
          'Roll d20 under stat = Success; under half = Great Success.',
          style: TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 4),
        for (final k in kArgosaStats)
          Row(children: [
            SizedBox(width: 48, child: Text(k.toUpperCase())),
            _stepper(
              'argosa-stat-$k',
              '',
              s.stats[k] ?? 10,
              min: 3,
              max: 18,
              onSet: (v) => _save(ref, s.copyWith(stats: {...s.stats, k: v})),
            ),
            const Spacer(),
            IconButton(
              key: Key('argosa-roll-$k'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.casino_outlined, size: 18),
              tooltip: 'Roll d20 under ${k.toUpperCase()}',
              onPressed: () => _roll(context, k),
            ),
          ]),
        const SizedBox(height: 12),
        Text('Hit Points', style: theme.textTheme.titleMedium),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stepper('argosa-hp', 'Current', s.currentHp,
              max: s.maxHp, onSet: (v) => _save(ref, s.copyWith(currentHp: v))),
          _stepper('argosa-maxhp', 'Max', s.maxHp,
              onSet: (v) => _save(ref, s.copyWith(maxHp: v))),
          if (isStaggered)
            Chip(
              label: const Text('Staggered'),
              backgroundColor: theme.colorScheme.errorContainer,
              labelStyle: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
        ]),
        const SizedBox(height: 12),
        Text('Luck', style: theme.textTheme.titleMedium),
        Row(children: [
          _stepper('argosa-luck', '', s.luck,
              onSet: (v) => _save(ref, s.copyWith(luck: v))),
          const SizedBox(width: 8),
          TextButton(
            key: const Key('argosa-luck-reset'),
            onPressed: () => _save(ref, s.copyWith(luck: s.resetLuck)),
            child: Text('Reset (${s.resetLuck})'),
          ),
        ]),
        const SizedBox(height: 12),
        _stepper('argosa-rescues', 'Rescues', s.rescues,
            onSet: (v) => _save(ref, s.copyWith(rescues: v))),
        const SizedBox(height: 12),
        conditionsSection(context, ref, character, 'argosa'),
        const SizedBox(height: 12),
        DebouncedTextField(
          key: const Key('argosa-skills'),
          initialValue: s.skills,
          maxLines: 3,
          label: 'Skills & Abilities',
          onSave: (v) => _save(ref, s.copyWith(skills: v)),
        ),
        DebouncedTextField(
          key: const Key('argosa-notes'),
          initialValue: s.notes,
          maxLines: 3,
          label: 'Notes',
          onSave: (v) => _save(ref, s.copyWith(notes: v)),
        ),
      ],
    );
  }
}
