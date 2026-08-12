import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/sheet_rolls.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

class OseSheetView extends ConsumerWidget {
  const OseSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  OseSheet get _s => character.ose!;

  void _save(WidgetRef ref, OseSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(ose: next));

  void _rollSave(BuildContext context, WidgetRef ref, String saveKey) {
    final r = oseSave(ref.read(diceProvider).dN(20), _s.saves[saveKey] ?? 12);
    final label = kOseSaveLabels[saveKey] ?? saveKey;
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

    return ListView(
      key: const Key('ose-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        sheetNameHeader(context, ref, character,
            onBack: onBack, nameKey: 'ose-name'),
        Text('OSE / B/X', style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButton<String>(
              key: const Key('ose-class'),
              value: kOseClasses.contains(s.className) ? s.className : null,
              isExpanded: true,
              items: kOseClasses
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) {
                if (v != null) _save(ref, s.copyWith(className: v));
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              key: const Key('ose-alignment'),
              value: kOseAlignments.contains(s.alignment) ? s.alignment : null,
              isExpanded: true,
              items: kOseAlignments
                  .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                  .toList(),
              onChanged: (v) {
                if (v != null) _save(ref, s.copyWith(alignment: v));
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          sheetStepper('ose-level', 'Level', s.level,
              min: 1, max: 20, onSet: (v) => _save(ref, s.copyWith(level: v))),
          const SizedBox(width: 16),
          Expanded(
            child: DebouncedTextField(
              key: const Key('ose-xp'),
              initialValue: s.xp,
              label: 'XP',
              onSave: (v) => _save(ref, s.copyWith(xp: v)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text('Ability Scores', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final k in kOseStats)
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(kOseStatLabels[k]!,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              sheetStepper(
                'ose-stat-$k',
                '',
                s.stats[k] ?? 10,
                min: 3,
                max: 18,
                onSet: (v) => _save(ref, s.copyWith(stats: {...s.stats, k: v})),
              ),
            ]),
        ]),
        const SizedBox(height: 12),
        Text('Saving Throws', style: theme.textTheme.titleMedium),
        const Text(
          'Roll d20 >= target to pass.',
          style: TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 4),
        for (final k in kOseSaveKeys)
          Row(children: [
            Expanded(child: Text(kOseSaveLabels[k]!)),
            sheetStepper(
              'ose-save-$k',
              '',
              s.saves[k] ?? 12,
              min: 2,
              max: 20,
              onSet: (v) => _save(ref, s.copyWith(saves: {...s.saves, k: v})),
            ),
            IconButton(
              key: Key('ose-save-roll-$k'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.casino_outlined, size: 18),
              tooltip: 'Roll vs ${s.saves[k] ?? 12}',
              onPressed: () => _rollSave(context, ref, k),
            ),
          ]),
        const SizedBox(height: 12),
        Text('Hit Points', style: theme.textTheme.titleMedium),
        Wrap(spacing: 16, runSpacing: 8, children: [
          sheetStepper('ose-hp', 'HP', s.currentHp,
              max: s.maxHp, onSet: (v) => _save(ref, s.copyWith(currentHp: v))),
          sheetStepper('ose-maxhp', 'Max', s.maxHp,
              onSet: (v) => _save(ref, s.copyWith(maxHp: v))),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 8, children: [
          sheetStepper('ose-ac', 'AC', s.ac,
              min: -10, max: 20, onSet: (v) => _save(ref, s.copyWith(ac: v))),
          SizedBox(
            width: 100,
            child: DebouncedTextField(
              key: const Key('ose-thac0'),
              initialValue: '${s.thac0}',
              label: 'THAC0',
              isDense: true,
              keyboardType: TextInputType.number,
              onSave: (v) {
                final n = int.tryParse(v);
                if (n != null) _save(ref, s.copyWith(thac0: n));
              },
            ),
          ),
        ]),
        const SizedBox(height: 12),
        DebouncedTextField(
          key: const Key('ose-coins'),
          initialValue: s.coins,
          label: 'Coins (cp/sp/gp/pp)',
          onSave: (v) => _save(ref, s.copyWith(coins: v)),
        ),
        const SizedBox(height: 12),
        conditionsSection(context, ref, character, 'ose'),
        magicSection(context, ref, character),
        const SizedBox(height: 12),
        DebouncedTextField(
          key: const Key('ose-notes'),
          initialValue: s.notes,
          maxLines: 4,
          label: 'Notes / Equipment',
          onSave: (v) => _save(ref, s.copyWith(notes: v)),
        ),
      ],
    );
  }
}
