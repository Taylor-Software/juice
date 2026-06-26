import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';

/// Shared building blocks for the bespoke system sheets (Ironsworn, Starforged).
/// Each widget takes a [prefix] so the two sheets get distinct, stable widget
/// keys (e.g. 'iw' -> 'iw-mom-minus', 'sf' -> 'sf-mom-minus').

Widget sheetSection(BuildContext context, String title) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );

/// Formats a signed number for a modifier display: `+3`, `0`, `-1`.
String fmtSigned(int n) => n >= 0 ? '+$n' : '$n';

/// Ability score box (D&D / Shadowdark): label, derived modifier, and a
/// −/score/+ stepper. [prefix] keys the buttons, e.g. 'dnd' ->
/// 'dnd-ability-str-plus', 'sd' -> 'sd-ability-str-plus'.
Widget abilityBox({
  required String prefix,
  required String abilityKey,
  required String label,
  required String modText,
  required int score,
  required VoidCallback onMinus,
  required VoidCallback onPlus,
}) =>
    SizedBox(
      width: 110,
      child: Column(children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        Text(modText,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            key: Key('$prefix-ability-$abilityKey-minus'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove, size: 16),
            onPressed: onMinus,
          ),
          Text('$score'),
          IconButton(
            key: Key('$prefix-ability-$abilityKey-plus'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 16),
            onPressed: onPlus,
          ),
        ]),
      ]),
    );

Widget statStepper({
  required String prefix,
  required String label,
  required int value,
  required ValueChanged<int> onSet,
}) =>
    Expanded(
      child: Column(children: [
        Text('$value',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 10)),
        // Minimum density + zero padding + tight constraints shrink the tap
        // target (the 48px Material default, not the icon) so the two buttons
        // fit a ~1/5-width stat column on a ~360px phone instead of overflowing.
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            key: Key('$prefix-stat-${label.toLowerCase()}-minus'),
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.remove, size: 16),
            onPressed: () => onSet(value - 1),
          ),
          IconButton(
            key: Key('$prefix-stat-${label.toLowerCase()}-plus'),
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.add, size: 16),
            onPressed: () => onSet(value + 1),
          ),
        ]),
      ]),
    );

Widget meterStepper({
  required String prefix,
  required String label,
  required String meterKey,
  required int value,
  required ValueChanged<int> onSet,
}) =>
    Row(children: [
      SizedBox(width: 64, child: Text(label)),
      IconButton(
        key: Key('$prefix-$meterKey-minus'),
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: () => onSet(value - 1),
      ),
      Text('$value / 5'),
      IconButton(
        key: Key('$prefix-$meterKey-plus'),
        icon: const Icon(Icons.add_circle_outline),
        onPressed: () => onSet(value + 1),
      ),
    ]);

Widget intStepper({
  required String prefix,
  required String fieldKey,
  required int value,
  required ValueChanged<int> onSet,
}) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        key: Key('$prefix-$fieldKey-minus'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: () => onSet(value - 1),
      ),
      Text('$value'),
      IconButton(
        key: Key('$prefix-$fieldKey-plus'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.add_circle_outline),
        onPressed: () => onSet(value + 1),
      ),
    ]);

Widget momentumRow({
  required BuildContext context,
  required String prefix,
  required int momentum,
  required int momentumMax,
  required int momentumReset,
  required ValueChanged<int> onSet,
}) {
  final theme = Theme.of(context);
  return Row(children: [
    IconButton(
      key: Key('$prefix-mom-minus'),
      icon: const Icon(Icons.remove_circle_outline),
      onPressed: () => onSet(momentum - 1),
    ),
    Text(momentum >= 0 ? '+$momentum' : '$momentum',
        style: theme.textTheme.titleLarge),
    IconButton(
      key: Key('$prefix-mom-plus'),
      icon: const Icon(Icons.add_circle_outline),
      onPressed: () => onSet(momentum + 1),
    ),
    const Spacer(),
    Flexible(
      child: Text('max +$momentumMax · reset +$momentumReset',
          style: theme.textTheme.bodySmall),
    ),
    const SizedBox(width: 8),
    SizedBox(
      width: 72,
      child: FilledButton(
        key: Key('$prefix-burn'),
        onPressed: () => onSet(momentumReset),
        child: const Text('Burn'),
      ),
    ),
  ]);
}

/// Flat chip Wrap for debilities/impacts. [chipPrefix] is the full key stem,
/// e.g. 'iw-deb' -> 'iw-deb-shaken', 'sf-imp' -> 'sf-imp-shaken'.
Widget toggleChips({
  required String chipPrefix,
  required Map<String, String> labels,
  required Set<String> selected,
  required ValueChanged<Set<String>> onChanged,
}) =>
    Wrap(spacing: 6, runSpacing: 4, children: [
      for (final e in labels.entries)
        FilterChip(
          key: Key('$chipPrefix-${e.key}'),
          label: Text(e.value),
          selected: selected.contains(e.key),
          onSelected: (on) {
            final next = {...selected};
            if (on) {
              next.add(e.key);
            } else {
              next.remove(e.key);
            }
            onChanged(next);
          },
        ),
    ]);

/// A vow/connection row (a [ProgressTrack]). [prefix] e.g. 'iw-vow', 'sf-conn'.
Widget progressTrackRow({
  required BuildContext context,
  required String prefix,
  required int index,
  required ProgressTrack track,
  required ValueChanged<ProgressTrack> onChanged,
  required VoidCallback onDelete,
}) =>
    Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(track.name,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            DropdownButton<ProgressRank>(
              key: Key('$prefix-$index-rank'),
              value: track.rank,
              underline: const SizedBox.shrink(),
              items: [
                for (final r in ProgressRank.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (r) => onChanged(track.copyWith(rank: r)),
            ),
            IconButton(
              key: Key('$prefix-$index-unmark'),
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Un-mark',
              onPressed: () => onChanged(track.marked(-1)),
            ),
            IconButton(
              key: Key('$prefix-$index-mark'),
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Mark progress',
              onPressed: () => onChanged(track.marked(1)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ]),
          Text('${track.boxes}/10 boxes · ${track.rank.label}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );

/// "Add progress track" dialog; returns the new track or null if cancelled.
/// [nameKey] keys the name field (e.g. 'vow-name', 'conn-name').
Future<ProgressTrack?> addProgressTrackDialog(
  BuildContext context, {
  required String nameKey,
  required String label,
}) async {
  final ctrl = TextEditingController();
  var rank = ProgressRank.dangerous;
  final name = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text('Add $label'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: Key(nameKey),
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(labelText: label),
          ),
          const SizedBox(height: 12),
          DropdownButton<ProgressRank>(
            value: rank,
            isExpanded: true,
            items: [
              for (final r in ProgressRank.values)
                DropdownMenuItem(value: r, child: Text(r.label)),
            ],
            onChanged: (r) => setLocal(() => rank = r ?? rank),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Add')),
        ],
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  if (name == null || name.trim().isEmpty) return null;
  return ProgressTrack(name: name.trim(), rank: rank);
}

Widget assetCard({
  required String prefix,
  required int index,
  required AssetState asset,
  required ValueChanged<List<bool>> onAbilitiesChanged,
  required VoidCallback onDelete,
  void Function(String key, int value)? onMeterChanged,
}) =>
    Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${asset.name}  ·  ${asset.category}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ]),
          for (var k = 0; k < asset.enabledAbilities.length; k++)
            CheckboxListTile(
              key: Key('$prefix-asset-$index-ability-$k'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: asset.enabledAbilities[k],
              title: Text('Ability ${k + 1}'),
              onChanged: (on) {
                final flags = [...asset.enabledAbilities]..[k] = on ?? false;
                onAbilitiesChanged(flags);
              },
            ),
          for (final m in asset.meters)
            Row(children: [
              SizedBox(
                width: 80,
                child: Text(_titleCase(m.label),
                    style: const TextStyle(fontSize: 12)),
              ),
              IconButton(
                key: Key('$prefix-asset-$index-meter-${m.key}-minus'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: onMeterChanged == null
                    ? null
                    : () => onMeterChanged(m.key, m.value - 1),
              ),
              Text('${m.value} / ${m.max}'),
              IconButton(
                key: Key('$prefix-asset-$index-meter-${m.key}-plus'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline),
                onPressed: onMeterChanged == null
                    ? null
                    : () => onMeterChanged(m.key, m.value + 1),
              ),
            ]),
        ]),
      ),
    );

/// Datasworn control labels are lowercase ("integrity"); title-case for display.
String _titleCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Loads [rulesetId] assets and shows the picker; returns the chosen def or null.
Future<IronswornAssetDef?> addAssetDialog(
    BuildContext context, WidgetRef ref, String rulesetId) async {
  final data = await ref.read(rulesetDataProvider(rulesetId).future);
  final defs = IronswornAssetDef.listFromRuleset(data);
  if (!context.mounted) return null;
  return showDialog<IronswornAssetDef>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Add asset'),
      children: [
        SizedBox(
          width: 320,
          height: 420,
          child: ListView(children: [
            for (final d in defs)
              ListTile(
                key: Key('pick-asset-${d.id}'),
                title: Text(d.name),
                subtitle: Text(d.category),
                onTap: () => Navigator.pop(context, d),
              ),
          ]),
        ),
      ],
    ),
  );
}

/// Rename dialog; returns the trimmed new name or null. [nameKey] keys the field.
Future<String?> renameDialog(BuildContext context,
    {required String nameKey, required String current}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(nameKey: nameKey, current: current),
  );
  if (name == null || name.trim().isEmpty) return null;
  return name.trim();
}

/// Owns the rename field's controller so it is disposed only after the dialog
/// route fully unmounts (disposing synchronously after `showDialog` returns
/// throws "controller used after dispose" during the dismiss animation).
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.nameKey, required this.current});
  final String nameKey;
  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.current);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          key: Key(widget.nameKey),
          controller: _ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _ctrl.text),
              child: const Text('Save')),
        ],
      );
}

/// Shared sheet header: back button, the character name, and an edit pencil
/// that opens [renameDialog] to rename. Used by the bespoke system sheets so
/// every sheet can rename its character. [nameKey] keys the rename field.
Widget sheetNameHeader(
  BuildContext context,
  WidgetRef ref,
  Character character, {
  required VoidCallback onBack,
  required String nameKey,
}) {
  final theme = Theme.of(context);
  return Row(children: [
    IconButton(
      key: const Key('sheet-back'),
      icon: const Icon(Icons.arrow_back),
      onPressed: onBack,
    ),
    Expanded(
      child: Text(character.name,
          style: theme.textTheme.titleLarge, overflow: TextOverflow.ellipsis),
    ),
    IconButton(
      key: Key('$nameKey-edit'),
      icon: const Icon(Icons.edit_outlined),
      tooltip: 'Rename',
      onPressed: () async {
        final name = await renameDialog(context,
            nameKey: nameKey, current: character.name);
        if (name != null) {
          await ref
              .read(charactersProvider.notifier)
              .replace(character.copyWith(name: name));
        }
      },
    ),
  ]);
}

/// Conditions editor shared by the roster row and the open sheets. Presents the
/// preset + existing conditions as toggle chips plus a free-text add, and
/// persists the selection through [charactersProvider].
Future<void> showConditionsEditor(
    BuildContext context, WidgetRef ref, Character c) async {
  final selected = {...c.conditions};
  final customCtrl = TextEditingController();
  try {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('${c.name} — conditions'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final cond in {...kConditions, ...c.conditions})
                      FilterChip(
                        label: Text(cond),
                        selected: selected.contains(cond),
                        onSelected: (on) => setLocal(() =>
                            on ? selected.add(cond) : selected.remove(cond)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: customCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Add custom condition'),
                  onSubmitted: (v) {
                    final t = v.trim();
                    if (t.isNotEmpty) setLocal(() => selected.add(t));
                    customCtrl.clear();
                  },
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  } finally {
    customCtrl.dispose();
  }
  await ref
      .read(charactersProvider.notifier)
      .setConditions(c.id, selected.toList());
}

/// A spend-down-from-a-ceiling token pool with a restore action. DCC LCK uses
/// this; the generic shape also seeds the future custom-sheet builder.
Widget luckTokensSection({
  required String keyPrefix,
  required String label,
  required int current,
  required int max,
  required ValueChanged<int> onSet,
  required VoidCallback onReset,
}) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label  '),
      IconButton(
        key: Key('$keyPrefix-spend'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.remove),
        tooltip: 'Spend 1',
        onPressed: current > 0 ? () => onSet(current - 1) : null,
      ),
      Text('$current / $max'),
      IconButton(
        key: Key('$keyPrefix-gain'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.add),
        tooltip: 'Gain 1',
        onPressed: current < max ? () => onSet(current + 1) : null,
      ),
      TextButton(
        key: Key('$keyPrefix-restore'),
        onPressed: onReset,
        child: const Text('Restore'),
      ),
    ]);

/// A "Status" section for the open sheets: the character's active conditions as
/// chips (or a hint) plus an Edit button — so debuffs are visible and editable
/// without backing out to the roster. [prefix] keys the edit button.
Widget conditionsSection(
        BuildContext context, WidgetRef ref, Character c, String prefix) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sheetSection(context, 'Status'),
        Row(
          children: [
            Expanded(
              child: c.conditions.isEmpty
                  ? Text('No conditions',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant))
                  : Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final cond in c.conditions)
                          Chip(label: Text(cond)),
                      ],
                    ),
            ),
            TextButton.icon(
              key: Key('$prefix-edit-conditions'),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
              onPressed: () => showConditionsEditor(context, ref, c),
            ),
          ],
        ),
      ],
    );
