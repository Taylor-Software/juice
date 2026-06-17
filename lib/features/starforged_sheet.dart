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
        sheetSection(context, 'Vows'),
        for (var i = 0; i < s.vows.length; i++)
          progressTrackRow(
            context: context,
            prefix: 'sf-vow',
            index: i,
            track: s.vows[i],
            onChanged: (t) =>
                _save(ref, s.copyWith(vows: [...s.vows]..[i] = t)),
            onDelete: () =>
                _save(ref, s.copyWith(vows: [...s.vows]..removeAt(i))),
          ),
        OutlinedButton.icon(
          key: const Key('sf-add-vow'),
          icon: const Icon(Icons.add),
          label: const Text('Add vow'),
          onPressed: () async {
            final t = await addProgressTrackDialog(context,
                nameKey: 'vow-name', label: 'Vow');
            if (t != null) _save(ref, _s.copyWith(vows: [..._s.vows, t]));
          },
        ),
        sheetSection(context, 'Connections'),
        for (var i = 0; i < s.connections.length; i++)
          progressTrackRow(
            context: context,
            prefix: 'sf-conn',
            index: i,
            track: s.connections[i],
            onChanged: (t) => _save(
                ref, s.copyWith(connections: [...s.connections]..[i] = t)),
            onDelete: () => _save(
                ref, s.copyWith(connections: [...s.connections]..removeAt(i))),
          ),
        OutlinedButton.icon(
          key: const Key('sf-add-conn'),
          icon: const Icon(Icons.add),
          label: const Text('Add connection'),
          onPressed: () async {
            final t = await addProgressTrackDialog(context,
                nameKey: 'conn-name', label: 'Connection');
            if (t != null) {
              _save(ref, _s.copyWith(connections: [..._s.connections, t]));
            }
          },
        ),
        sheetSection(context, 'Assets'),
        for (var i = 0; i < s.assets.length; i++)
          assetCard(
            prefix: 'sf',
            index: i,
            asset: s.assets[i],
            onAbilitiesChanged: (flags) => _save(
                ref,
                s.copyWith(
                    assets: [...s.assets]..[i] =
                        s.assets[i].copyWith(enabledAbilities: flags))),
            onDelete: () =>
                _save(ref, s.copyWith(assets: [...s.assets]..removeAt(i))),
          ),
        OutlinedButton.icon(
          key: const Key('sf-add-asset'),
          icon: const Icon(Icons.add),
          label: const Text('Add asset'),
          onPressed: () async {
            final def = await addAssetDialog(context, ref, 'starforged');
            if (def != null) {
              _save(ref, _s.copyWith(assets: [..._s.assets, def.toState()]));
            }
          },
        ),
        sheetSection(context, 'Notes'),
        Text(character.note.isEmpty ? '—' : character.note),
      ],
    );
  }
}
