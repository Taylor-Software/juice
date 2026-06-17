import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

/// Bespoke Starforged character sheet. Renders for characters whose
/// [Character.starforged] is non-null; edits persist via charactersProvider.
class StarforgedSheetView extends ConsumerWidget {
  const StarforgedSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  StarforgedSheet get _s => character.starforged!;

  void _save(WidgetRef ref, StarforgedSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(starforged: next));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;
    Widget legacy(
            String label, String key, int value, ValueChanged<int> onSet) =>
        Row(children: [
          SizedBox(width: 96, child: Text(label)),
          intStepper(prefix: 'sf', fieldKey: key, value: value, onSet: onSet),
          Text('/ 10', style: theme.textTheme.bodySmall),
        ]);
    return ListView(
      key: const Key('starforged-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(
            key: const Key('sheet-back'),
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(character.name,
                style: theme.textTheme.titleLarge,
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
            onPressed: () async {
              final name = await renameDialog(context,
                  nameKey: 'sf-name', current: character.name);
              if (name != null) {
                await ref
                    .read(charactersProvider.notifier)
                    .replace(character.copyWith(name: name));
              }
            },
          ),
        ]),
        Text('Starforged', style: theme.textTheme.labelSmall),
        sheetSection(context, 'Stats'),
        Row(children: [
          statStepper(
              prefix: 'sf',
              label: 'EDGE',
              value: s.edge,
              onSet: (v) => _save(ref, s.copyWith(edge: v))),
          statStepper(
              prefix: 'sf',
              label: 'HEART',
              value: s.heart,
              onSet: (v) => _save(ref, s.copyWith(heart: v))),
          statStepper(
              prefix: 'sf',
              label: 'IRON',
              value: s.iron,
              onSet: (v) => _save(ref, s.copyWith(iron: v))),
          statStepper(
              prefix: 'sf',
              label: 'SHADOW',
              value: s.shadow,
              onSet: (v) => _save(ref, s.copyWith(shadow: v))),
          statStepper(
              prefix: 'sf',
              label: 'WITS',
              value: s.wits,
              onSet: (v) => _save(ref, s.copyWith(wits: v))),
        ]),
        sheetSection(context, 'Condition Meters'),
        meterStepper(
            prefix: 'sf',
            label: 'Health',
            meterKey: 'health',
            value: s.health,
            onSet: (v) => _save(ref, s.copyWith(health: v))),
        meterStepper(
            prefix: 'sf',
            label: 'Spirit',
            meterKey: 'spirit',
            value: s.spirit,
            onSet: (v) => _save(ref, s.copyWith(spirit: v))),
        meterStepper(
            prefix: 'sf',
            label: 'Supply',
            meterKey: 'supply',
            value: s.supply,
            onSet: (v) => _save(ref, s.copyWith(supply: v))),
        sheetSection(context, 'Momentum'),
        momentumRow(
          context: context,
          prefix: 'sf',
          momentum: s.momentum,
          momentumMax: s.momentumMax,
          momentumReset: s.momentumReset,
          onSet: (v) => _save(ref, s.copyWith(momentum: v)),
        ),
        sheetSection(context, 'Impacts'),
        toggleChips(
          chipPrefix: 'sf-imp',
          labels: kStarforgedImpacts,
          selected: s.impacts,
          onChanged: (i) => _save(ref, s.copyWith(impacts: i)),
        ),
        sheetSection(context, 'Legacy Tracks'),
        legacy('Quests', 'quests', s.questsLegacy,
            (v) => _save(ref, s.copyWith(questsLegacy: v))),
        legacy('Bonds', 'bonds', s.bondsLegacy,
            (v) => _save(ref, s.copyWith(bondsLegacy: v))),
        legacy('Discoveries', 'discoveries', s.discoveriesLegacy,
            (v) => _save(ref, s.copyWith(discoveriesLegacy: v))),
        sheetSection(context, 'Experience'),
        Row(children: [
          const Text('XP earned'),
          intStepper(
              prefix: 'sf',
              fieldKey: 'xpEarned',
              value: s.xpEarned,
              onSet: (v) => _save(ref, s.copyWith(xpEarned: v))),
          const SizedBox(width: 16),
          const Text('spent'),
          intStepper(
              prefix: 'sf',
              fieldKey: 'xpSpent',
              value: s.xpSpent,
              onSet: (v) => _save(ref, s.copyWith(xpSpent: v))),
        ]),
        sheetSection(context, 'Notes'),
        Text(character.note.isEmpty ? '—' : character.note),
      ],
    );
  }
}
