import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

/// Bespoke Classic Ironsworn character sheet. Renders for characters whose
/// [Character.ironsworn] is non-null; edits persist via charactersProvider.
class IronswornSheetView extends ConsumerWidget {
  const IronswornSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  IronswornSheet get _s => character.ironsworn!;

  void _save(WidgetRef ref, IronswornSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(ironsworn: next));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;
    return ListView(
      key: const Key('ironsworn-sheet'),
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
                  nameKey: 'iw-name', current: character.name);
              if (name != null) {
                await ref
                    .read(charactersProvider.notifier)
                    .replace(character.copyWith(name: name));
              }
            },
          ),
        ]),
        Text('Ironsworn · Classic', style: theme.textTheme.labelSmall),
        sheetSection(context, 'Stats'),
        Row(children: [
          statStepper(
              prefix: 'iw',
              label: 'EDGE',
              value: s.edge,
              onSet: (v) => _save(ref, s.copyWith(edge: v))),
          statStepper(
              prefix: 'iw',
              label: 'HEART',
              value: s.heart,
              onSet: (v) => _save(ref, s.copyWith(heart: v))),
          statStepper(
              prefix: 'iw',
              label: 'IRON',
              value: s.iron,
              onSet: (v) => _save(ref, s.copyWith(iron: v))),
          statStepper(
              prefix: 'iw',
              label: 'SHADOW',
              value: s.shadow,
              onSet: (v) => _save(ref, s.copyWith(shadow: v))),
          statStepper(
              prefix: 'iw',
              label: 'WITS',
              value: s.wits,
              onSet: (v) => _save(ref, s.copyWith(wits: v))),
        ]),
        sheetSection(context, 'Condition Meters'),
        meterStepper(
            prefix: 'iw',
            label: 'Health',
            meterKey: 'health',
            value: s.health,
            onSet: (v) => _save(ref, s.copyWith(health: v))),
        meterStepper(
            prefix: 'iw',
            label: 'Spirit',
            meterKey: 'spirit',
            value: s.spirit,
            onSet: (v) => _save(ref, s.copyWith(spirit: v))),
        meterStepper(
            prefix: 'iw',
            label: 'Supply',
            meterKey: 'supply',
            value: s.supply,
            onSet: (v) => _save(ref, s.copyWith(supply: v))),
        sheetSection(context, 'Momentum'),
        momentumRow(
          context: context,
          prefix: 'iw',
          momentum: s.momentum,
          momentumMax: s.momentumMax,
          momentumReset: s.momentumReset,
          onSet: (v) => _save(ref, s.copyWith(momentum: v)),
        ),
        sheetSection(context, 'Debilities'),
        toggleChips(
          chipPrefix: 'iw-deb',
          labels: kIronswornDebilities,
          selected: s.debilities,
          onChanged: (d) => _save(ref, s.copyWith(debilities: d)),
        ),
        sheetSection(context, 'Experience & Bonds'),
        // Wrap (not Row): the two XP steppers reflow to a second line on a
        // narrow phone instead of throwing a RenderFlex overflow.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('XP earned'),
            intStepper(
                prefix: 'iw',
                fieldKey: 'xpEarned',
                value: s.xpEarned,
                onSet: (v) => _save(ref, s.copyWith(xpEarned: v))),
            const SizedBox(width: 16),
            const Text('spent'),
            intStepper(
                prefix: 'iw',
                fieldKey: 'xpSpent',
                value: s.xpSpent,
                onSet: (v) => _save(ref, s.copyWith(xpSpent: v))),
          ],
        ),
        Row(children: [
          const Text('Bonds'),
          intStepper(
              prefix: 'iw',
              fieldKey: 'bonds',
              value: s.bonds,
              onSet: (v) => _save(ref, s.copyWith(bonds: v))),
          Text('/ 10', style: theme.textTheme.bodySmall),
        ]),
        sheetSection(context, 'Vows'),
        for (var i = 0; i < s.vows.length; i++)
          progressTrackRow(
            context: context,
            prefix: 'iw-vow',
            index: i,
            track: s.vows[i],
            onChanged: (t) =>
                _save(ref, s.copyWith(vows: [...s.vows]..[i] = t)),
            onDelete: () =>
                _save(ref, s.copyWith(vows: [...s.vows]..removeAt(i))),
          ),
        OutlinedButton.icon(
          key: const Key('iw-add-vow'),
          icon: const Icon(Icons.add),
          label: const Text('Add vow'),
          onPressed: () async {
            final t = await addProgressTrackDialog(context,
                nameKey: 'vow-name', label: 'Vow');
            if (t != null) _save(ref, _s.copyWith(vows: [..._s.vows, t]));
          },
        ),
        sheetSection(context, 'Assets'),
        for (var i = 0; i < s.assets.length; i++)
          assetCard(
            prefix: 'iw',
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
          key: const Key('iw-add-asset'),
          icon: const Icon(Icons.add),
          label: const Text('Add asset'),
          onPressed: () async {
            final def = await addAssetDialog(context, ref, 'classic');
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
