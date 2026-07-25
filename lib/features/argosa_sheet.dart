import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/sheet_rolls.dart';
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

  void _roll(BuildContext context, WidgetRef ref, String statKey) {
    final r =
        argosaRollUnder(ref.read(diceProvider).dN(20), _s.stats[statKey] ?? 10);
    final label = kArgosaStatLabels[statKey] ?? statKey;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label: ${r.total} — ${r.outcome}'),
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
        sheetStepper('argosa-level', 'Level', s.level,
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
            sheetStepper(
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
              onPressed: () => _roll(context, ref, k),
            ),
          ]),
        const SizedBox(height: 12),
        Text('Hit Points', style: theme.textTheme.titleMedium),
        Wrap(spacing: 16, runSpacing: 8, children: [
          sheetStepper('argosa-hp', 'Current', s.currentHp,
              max: s.maxHp, onSet: (v) => _save(ref, s.copyWith(currentHp: v))),
          sheetStepper('argosa-maxhp', 'Max', s.maxHp,
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
          sheetStepper('argosa-luck', '', s.luck,
              onSet: (v) => _save(ref, s.copyWith(luck: v))),
          const SizedBox(width: 8),
          TextButton(
            key: const Key('argosa-luck-reset'),
            onPressed: () => _save(ref, s.copyWith(luck: s.resetLuck)),
            child: Text('Reset (${s.resetLuck})'),
          ),
        ]),
        const SizedBox(height: 12),
        sheetStepper('argosa-rescues', 'Rescues', s.rescues,
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
