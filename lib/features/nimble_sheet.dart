import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

/// Facts-only Nimble sheet. Class/stat NAMES are authored; values are editable.
class NimbleSheetView extends ConsumerWidget {
  const NimbleSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  NimbleSheet get _s => character.nimble!;
  void _save(WidgetRef ref, NimbleSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(nimble: next));

  Widget _stepper(
    String key,
    String label,
    int value, {
    required ValueChanged<int> onSet,
    int min = -9,
    int max = 999,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;
    return ListView(
      key: const Key('nimble-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        sheetNameHeader(context, ref, character,
            onBack: onBack, nameKey: 'nimble-name'),
        Text('Nimble', style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),
        DropdownButton<String>(
          key: const Key('nimble-class'),
          isExpanded: true,
          value: kNimbleClasses.contains(s.className)
              ? s.className
              : kNimbleClasses.first,
          items: [
            for (final c in kNimbleClasses)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) =>
              v == null ? null : _save(ref, s.copyWith(className: v)),
        ),
        DebouncedTextField(
          key: const Key('nimble-ancestry'),
          initialValue: s.ancestry,
          label: 'Ancestry',
          onSave: (v) => _save(ref, s.copyWith(ancestry: v)),
        ),
        const SizedBox(height: 12),
        Text('Stats (modifiers) + saves', style: theme.textTheme.titleMedium),
        for (final k in kNimbleStats)
          Row(children: [
            SizedBox(width: 48, child: Text(k.toUpperCase())),
            _stepper('nimble-stat-$k', '', s.stats[k] ?? 0,
                min: -9,
                max: 9,
                onSet: (v) =>
                    _save(ref, s.copyWith(stats: {...s.stats, k: v}))),
            const Spacer(),
            TextButton(
              key: Key('nimble-save-$k'),
              onPressed: () {
                final cur = s.saveAdv[k] ?? 0;
                final next = cur == 0 ? 1 : (cur == 1 ? -1 : 0);
                _save(ref, s.copyWith(saveAdv: {...s.saveAdv, k: next}));
              },
              child: Text((s.saveAdv[k] ?? 0) == 0
                  ? 'save —'
                  : ((s.saveAdv[k] ?? 0) > 0 ? 'save +' : 'save –')),
            ),
          ]),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stepper('nimble-hp', 'HP', s.currentHp,
              min: 0,
              max: s.maxHp,
              onSet: (v) => _save(ref, s.copyWith(currentHp: v))),
          _stepper('nimble-maxhp', 'Max HP', s.maxHp,
              min: 0, onSet: (v) => _save(ref, s.copyWith(maxHp: v))),
          _stepper('nimble-wounds', 'Wounds', s.wounds,
              min: 0,
              max: s.maxWounds,
              onSet: (v) => _save(ref, s.copyWith(wounds: v))),
          _stepper('nimble-level', 'Level', s.level,
              min: 1, max: 10, onSet: (v) => _save(ref, s.copyWith(level: v))),
          _stepper('nimble-speed', 'Speed', s.speed,
              min: 0, onSet: (v) => _save(ref, s.copyWith(speed: v))),
          _stepper('nimble-hitdie', 'Hit Die d', s.hitDieSize,
              min: 1, onSet: (v) => _save(ref, s.copyWith(hitDieSize: v))),
        ]),
        const SizedBox(height: 8),
        _stepper(
            'nimble-slots', 'Slots used (cap ${s.slotCap})', s.gearSlotsUsed,
            min: 0, onSet: (v) => _save(ref, s.copyWith(gearSlotsUsed: v))),
        const SizedBox(height: 12),
        conditionsSection(context, ref, character, 'nimble'),
        const SizedBox(height: 12),
        DebouncedTextField(
          key: const Key('nimble-talents'),
          initialValue: s.talents,
          maxLines: 3,
          label: 'Talents',
          onSave: (v) => _save(ref, s.copyWith(talents: v)),
        ),
        DebouncedTextField(
          key: const Key('nimble-notes'),
          initialValue: s.notes,
          maxLines: 3,
          label: 'Notes',
          onSave: (v) => _save(ref, s.copyWith(notes: v)),
        ),
      ],
    );
  }
}
