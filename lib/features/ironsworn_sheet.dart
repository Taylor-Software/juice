import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';

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
    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(t, style: theme.textTheme.titleMedium),
        );
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
            onPressed: () => _rename(context, ref),
          ),
        ]),
        Text('Ironsworn · Classic', style: theme.textTheme.labelSmall),
        section('Stats'),
        Row(children: [
          _stat(ref, 'EDGE', s.edge, (v) => _save(ref, s.copyWith(edge: v))),
          _stat(ref, 'HEART', s.heart, (v) => _save(ref, s.copyWith(heart: v))),
          _stat(ref, 'IRON', s.iron, (v) => _save(ref, s.copyWith(iron: v))),
          _stat(ref, 'SHADOW', s.shadow,
              (v) => _save(ref, s.copyWith(shadow: v))),
          _stat(ref, 'WITS', s.wits, (v) => _save(ref, s.copyWith(wits: v))),
        ]),
        section('Condition Meters'),
        _meter(ref, 'Health', 'health', s.health,
            (v) => _save(ref, s.copyWith(health: v))),
        _meter(ref, 'Spirit', 'spirit', s.spirit,
            (v) => _save(ref, s.copyWith(spirit: v))),
        _meter(ref, 'Supply', 'supply', s.supply,
            (v) => _save(ref, s.copyWith(supply: v))),
        section('Momentum'),
        Row(children: [
          IconButton(
            key: const Key('iw-mom-minus'),
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => _save(ref, s.copyWith(momentum: s.momentum - 1)),
          ),
          Text(s.momentum >= 0 ? '+${s.momentum}' : '${s.momentum}',
              style: theme.textTheme.titleLarge),
          IconButton(
            key: const Key('iw-mom-plus'),
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _save(ref, s.copyWith(momentum: s.momentum + 1)),
          ),
          const Spacer(),
          Flexible(
            child: Text('max +${s.momentumMax} · reset +${s.momentumReset}',
                style: theme.textTheme.bodySmall),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: FilledButton(
              key: const Key('iw-burn'),
              onPressed: () =>
                  _save(ref, s.copyWith(momentum: s.momentumReset)),
              child: const Text('Burn'),
            ),
          ),
        ]),
        section('Debilities'),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final e in kIronswornDebilities.entries)
            FilterChip(
              key: Key('iw-deb-${e.key}'),
              label: Text(e.value),
              selected: s.debilities.contains(e.key),
              onSelected: (on) {
                final d = {...s.debilities};
                if (on) {
                  d.add(e.key);
                } else {
                  d.remove(e.key);
                }
                _save(ref, s.copyWith(debilities: d));
              },
            ),
        ]),
        section('Experience & Bonds'),
        Row(children: [
          const Text('XP earned'),
          _intStepper(ref, 'xpEarned', s.xpEarned,
              (v) => _save(ref, s.copyWith(xpEarned: v))),
          const SizedBox(width: 16),
          const Text('spent'),
          _intStepper(ref, 'xpSpent', s.xpSpent,
              (v) => _save(ref, s.copyWith(xpSpent: v))),
        ]),
        Row(children: [
          const Text('Bonds'),
          _intStepper(
              ref, 'bonds', s.bonds, (v) => _save(ref, s.copyWith(bonds: v))),
          Text('/ 10', style: theme.textTheme.bodySmall),
        ]),
        section('Vows'),
        for (var i = 0; i < s.vows.length; i++) _vowRow(context, ref, s, i),
        OutlinedButton.icon(
          key: const Key('iw-add-vow'),
          icon: const Icon(Icons.add),
          label: const Text('Add vow'),
          onPressed: () => _addVow(context, ref),
        ),
        section('Notes'),
        Text(character.note.isEmpty ? '—' : character.note),
      ],
    );
  }

  Widget _stat(WidgetRef ref, String label, int value, ValueChanged<int> set) =>
      Expanded(
        child: Column(children: [
          Text('$value',
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 10)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              key: Key('iw-stat-${label.toLowerCase()}-minus'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove, size: 16),
              onPressed: () => set(value - 1),
            ),
            IconButton(
              key: Key('iw-stat-${label.toLowerCase()}-plus'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add, size: 16),
              onPressed: () => set(value + 1),
            ),
          ]),
        ]),
      );

  Widget _meter(WidgetRef ref, String label, String key, int value,
          ValueChanged<int> set) =>
      Row(children: [
        SizedBox(width: 64, child: Text(label)),
        IconButton(
          key: Key('iw-$key-minus'),
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => set(value - 1),
        ),
        Text('$value / 5'),
        IconButton(
          key: Key('iw-$key-plus'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => set(value + 1),
        ),
      ]);

  Widget _intStepper(
          WidgetRef ref, String key, int value, ValueChanged<int> set) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          key: Key('iw-$key-minus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => set(value - 1),
        ),
        Text('$value'),
        IconButton(
          key: Key('iw-$key-plus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => set(value + 1),
        ),
      ]);

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: character.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          key: const Key('iw-name'),
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(charactersProvider.notifier)
        .replace(character.copyWith(name: name.trim()));
  }

  Widget _vowRow(BuildContext context, WidgetRef ref, IronswornSheet s, int i) {
    final v = s.vows[i];
    IronswornSheet withVows(List<ProgressTrack> vows) => s.copyWith(vows: vows);
    void replaceVow(ProgressTrack nv) =>
        _save(ref, withVows([...s.vows]..[i] = nv));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(v.name,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            DropdownButton<ProgressRank>(
              key: Key('iw-vow-$i-rank'),
              value: v.rank,
              underline: const SizedBox.shrink(),
              items: [
                for (final r in ProgressRank.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (r) => replaceVow(v.copyWith(rank: r)),
            ),
            IconButton(
              key: Key('iw-vow-$i-unmark'),
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Un-mark',
              onPressed: () => replaceVow(v.marked(-1)),
            ),
            IconButton(
              key: Key('iw-vow-$i-mark'),
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Mark progress',
              onPressed: () => replaceVow(v.marked(1)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _save(ref, withVows([...s.vows]..removeAt(i))),
            ),
          ]),
          Text('${v.boxes}/10 boxes · ${v.rank.label}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }

  Future<void> _addVow(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    var rank = ProgressRank.dangerous;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Add vow'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const Key('vow-name'),
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Vow'),
            ),
            const SizedBox(height: 12),
            DropdownButton<ProgressRank>(
              key: const Key('vow-rank'),
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
    if (name == null || name.trim().isEmpty) return;
    _save(
        ref,
        _s.copyWith(vows: [
          ..._s.vows,
          ProgressTrack(name: name.trim(), rank: rank),
        ]));
  }
}
