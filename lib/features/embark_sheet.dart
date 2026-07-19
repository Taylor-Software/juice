import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

/// Facts-only Embark 2E sheet. Attributes are the raw number added to a d12
/// (range -1..4); a Check succeeds at 8+ (minus the Injury penalty). Injuries
/// are the 3-step death track. The class's resource pool (Grit / Spell Dice /
/// Flair) is one generic RESOURCE box.
class EmbarkSheetView extends ConsumerWidget {
  const EmbarkSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  EmbarkSheet get _s => character.embark!;

  void _save(WidgetRef ref, EmbarkSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(embark: next));

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

  void _rollCheck(BuildContext context, String statKey) {
    final score = _s.stats[statKey] ?? 0;
    final roll = Random().nextInt(12) + 1;
    final total = roll + score - _s.injuries;
    final result = total >= 8 ? 'Success' : 'Failure';
    final label = kEmbarkStatLabels[statKey] ?? statKey.toUpperCase();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label: $total — $result'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _statBlock(BuildContext context, String key, String label, int value,
      ValueChanged<int> onSet) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: Key('embark-stat-$key-minus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove),
          onPressed: value > -1 ? () => onSet(value - 1) : null,
        ),
        Text('$value'),
        IconButton(
          key: Key('embark-stat-$key-plus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add),
          onPressed: value < 4 ? () => onSet(value + 1) : null,
        ),
      ]),
      IconButton(
        key: Key('embark-check-$key'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.casino_outlined, size: 18),
        tooltip: '$label check (d12 + $value >= 8)',
        onPressed: () => _rollCheck(context, key),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;

    return ListView(
      key: const Key('embark-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        sheetNameHeader(context, ref, character,
            onBack: onBack, nameKey: 'embark-name'),
        Text('Embark 2E', style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),
        Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Class '),
                DropdownButton<String>(
                  key: const Key('embark-class'),
                  value: kEmbarkClasses.contains(s.className)
                      ? s.className
                      : kEmbarkClasses.first,
                  items: [
                    for (final c in kEmbarkClasses)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) =>
                      _save(ref, s.copyWith(className: v ?? s.className)),
                ),
              ]),
              _stepper('embark-level', 'Level', s.level,
                  min: 1,
                  max: 6,
                  onSet: (v) => _save(ref, s.copyWith(level: v))),
            ]),
        const SizedBox(height: 12),
        Text('Attributes', style: theme.textTheme.titleMedium),
        const Text(
          'Check: d12 + attribute >= 8 to succeed (each Injury is -1). Range -1..4.',
          style: TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in kEmbarkStats)
            _statBlock(
              context,
              k,
              kEmbarkStatLabels[k]!,
              s.stats[k] ?? 0,
              (v) => _save(ref, s.copyWith(stats: {...s.stats, k: v})),
            ),
        ]),
        const SizedBox(height: 12),
        Text('Health', style: theme.textTheme.titleMedium),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stepper('embark-hp', 'HP', s.currentHp,
              max: s.maxHp, onSet: (v) => _save(ref, s.copyWith(currentHp: v))),
          _stepper('embark-maxhp', 'Max', s.maxHp,
              onSet: (v) => _save(ref, s.copyWith(maxHp: v))),
        ]),
        const SizedBox(height: 4),
        _stepper('embark-injuries', 'Injuries', s.injuries,
            max: 3, onSet: (v) => _save(ref, s.copyWith(injuries: v))),
        const Text(
          '3rd Injury = death; each Injury is -1 to Checks.',
          style: TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stepper('embark-av', 'AV', s.av,
              max: 4, onSet: (v) => _save(ref, s.copyWith(av: v))),
        ]),
        const SizedBox(height: 12),
        Text(embarkResourceLabel(s.className),
            style: theme.textTheme.titleMedium),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stepper('embark-resource', 'Current', s.resource,
              max: s.resourceMax,
              onSet: (v) => _save(ref, s.copyWith(resource: v))),
          _stepper('embark-resourcemax', 'Max', s.resourceMax,
              onSet: (v) => _save(ref, s.copyWith(resourceMax: v))),
        ]),
        const SizedBox(height: 12),
        DebouncedTextField(
          key: const Key('embark-sp'),
          initialValue: s.sp,
          label: 'Silver (SP)',
          onSave: (v) => _save(ref, s.copyWith(sp: v)),
        ),
        const SizedBox(height: 12),
        DebouncedTextField(
          key: const Key('embark-skills'),
          initialValue: s.skills,
          maxLines: 3,
          label: 'Skills (freeform, 3 to start)',
          onSave: (v) => _save(ref, s.copyWith(skills: v)),
        ),
        const SizedBox(height: 8),
        DebouncedTextField(
          key: const Key('embark-languages'),
          initialValue: s.languages,
          maxLines: 2,
          label: 'Languages',
          onSave: (v) => _save(ref, s.copyWith(languages: v)),
        ),
        const SizedBox(height: 12),
        conditionsSection(context, ref, character, 'embark'),
        const SizedBox(height: 12),
        DebouncedTextField(
          key: const Key('embark-notes'),
          initialValue: s.notes,
          maxLines: 4,
          label: 'Notes / Inventory (12 slots: 6 body, 6 pack)',
          onSave: (v) => _save(ref, s.copyWith(notes: v)),
        ),
      ],
    );
  }
}
