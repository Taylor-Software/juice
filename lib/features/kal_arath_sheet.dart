import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

class KalArathSheetView extends ConsumerWidget {
  const KalArathSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  KalArathSheet get _s => character.kalArath!;

  void _save(WidgetRef ref, KalArathSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(kalArath: next));

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
    final score = _s.stats[statKey] ?? 0;
    final d1 = Random().nextInt(6) + 1;
    final d2 = Random().nextInt(6) + 1;
    final total = d1 + d2 + score;
    final String result;
    if (d1 == 6 && d2 == 6) {
      result = 'Critical Success';
    } else if (d1 == 1 && d2 == 1) {
      result = 'Critical Failure';
    } else {
      result = total >= 8 ? 'Success' : 'Failure';
    }
    final label = kKalArathStatLabels[statKey] ?? statKey.toUpperCase();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label: $total — $result'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;

    return ListView(
      key: const Key('kal-arath-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        sheetNameHeader(context, ref, character,
            onBack: onBack, nameKey: 'kal-arath-name'),
        Text('Kal-Arath', style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: const Key('kal-arath-archetype'),
              initialValue: kKalArathArchetypes.contains(s.archetype)
                  ? s.archetype
                  : kKalArathArchetypes.first,
              decoration: const InputDecoration(labelText: 'Archetype'),
              items: kKalArathArchetypes
                  .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                  .toList(),
              onChanged: (v) {
                if (v != null) _save(ref, s.copyWith(archetype: v));
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              key: const Key('kal-arath-pact'),
              initialValue: kKalArathPacts.contains(s.pact) ? s.pact : '',
              decoration: const InputDecoration(labelText: 'Demonic pact'),
              items: [
                const DropdownMenuItem(value: '', child: Text('None')),
                for (final p in kKalArathPacts)
                  DropdownMenuItem(value: p, child: Text(p)),
              ],
              onChanged: (v) => _save(ref, s.copyWith(pact: v ?? '')),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _stepper('kal-arath-level', 'Level', s.level,
              min: 1, max: 9, onSet: (v) => _save(ref, s.copyWith(level: v))),
          const SizedBox(width: 16),
          Expanded(
            child: DebouncedTextField(
              key: const Key('kal-arath-xp'),
              initialValue: s.xp,
              label: 'XP',
              onSave: (v) => _save(ref, s.copyWith(xp: v)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text('Stats', style: theme.textTheme.titleMedium),
        const Text(
          'Roll 2d6 + stat. 8+ to succeed.',
          style: TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final k in kKalArathStats)
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(kKalArathStatLabels[k]!,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              _stepper(
                'kal-arath-stat-$k',
                '',
                s.stats[k] ?? 0,
                min: -1,
                max: 5,
                onSet: (v) => _save(ref, s.copyWith(stats: {...s.stats, k: v})),
              ),
              IconButton(
                key: Key('kal-arath-roll-$k'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.casino_outlined, size: 18),
                tooltip: 'Roll 2d6 + ${kKalArathStatLabels[k]}',
                onPressed: () => _roll(context, k),
              ),
            ]),
        ]),
        const SizedBox(height: 12),
        Text('Hit Points', style: theme.textTheme.titleMedium),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stepper('kal-arath-hp', 'HP', s.currentHp,
              max: s.maxHp, onSet: (v) => _save(ref, s.copyWith(currentHp: v))),
          _stepper('kal-arath-maxhp', 'Max', s.maxHp,
              onSet: (v) => _save(ref, s.copyWith(maxHp: v))),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stepper('kal-arath-fate', 'Fate Points', s.fatePoints,
              max: 99, onSet: (v) => _save(ref, s.copyWith(fatePoints: v))),
          _stepper('kal-arath-dr', 'Damage Reduction', s.damageReduction,
              max: 99,
              onSet: (v) => _save(ref, s.copyWith(damageReduction: v))),
        ]),
        const SizedBox(height: 12),
        DebouncedTextField(
          key: const Key('kal-arath-doom'),
          initialValue: s.doom,
          label: 'Doom',
          onSave: (v) => _save(ref, s.copyWith(doom: v)),
        ),
        const SizedBox(height: 12),
        DebouncedTextField(
          key: const Key('kal-arath-skills'),
          initialValue: s.skills,
          label: 'Skills',
          onSave: (v) => _save(ref, s.copyWith(skills: v)),
        ),
        const SizedBox(height: 12),
        conditionsSection(context, ref, character, 'kal-arath'),
        const SizedBox(height: 12),
        DebouncedTextField(
          key: const Key('kal-arath-notes'),
          initialValue: s.notes,
          maxLines: 4,
          label: 'Notes',
          onSave: (v) => _save(ref, s.copyWith(notes: v)),
        ),
      ],
    );
  }
}
