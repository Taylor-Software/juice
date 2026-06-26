import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

class DccSheetView extends ConsumerWidget {
  const DccSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  void _save(WidgetRef ref, Character c, DccSheet next) =>
      ref.read(charactersProvider.notifier).replace(c.copyWith(dcc: next));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = character.dcc!;
    return s.isFunnel
        ? _buildFunnel(context, ref, character, s)
        : _buildLeveled(context, ref, character, s);
  }

  // ---- shared stepper (mirrors OseSheetView._stepper) ----
  Widget _stepper(String key, String label, int value,
          {required ValueChanged<int> onSet, int min = 0, int max = 9999}) =>
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

  String _sign(int n) => n >= 0 ? '+$n' : '$n';

  // ===================== FUNNEL =====================
  Widget _buildFunnel(
      BuildContext context, WidgetRef ref, Character c, DccSheet s) {
    final theme = Theme.of(context);
    final alive = s.peasants.where((p) => p.alive).length;
    return ListView(
      key: const Key('dcc-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        sheetNameHeader(context, ref, c, onBack: onBack, nameKey: 'dcc-name'),
        Text('0-Level Funnel', style: theme.textTheme.labelSmall),
        Text('$alive / ${s.peasants.length} alive',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < s.peasants.length; i++)
          _peasantCard(context, ref, c, s, i),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const Key('dcc-add-peasant'),
            onPressed: s.peasants.length >= 4
                ? null
                : () => _save(ref, c,
                    s.copyWith(peasants: [...s.peasants, const DccPeasant()])),
            icon: const Icon(Icons.person_add),
            label: const Text('Add peasant'),
          ),
        ),
      ],
    );
  }

  Widget _peasantCard(
      BuildContext context, WidgetRef ref, Character c, DccSheet s, int i) {
    final p = s.peasants[i];
    void setP(DccPeasant np) {
      final list = [...s.peasants];
      list[i] = np;
      _save(ref, c, s.copyWith(peasants: list));
    }

    final titleStyle = p.alive
        ? null
        : const TextStyle(
            decoration: TextDecoration.lineThrough, color: Colors.grey);

    return Card(
      child: ExpansionTile(
        key: Key('dcc-peasant-$i'),
        title: Text(p.name.isEmpty ? 'Peasant ${i + 1}' : p.name,
            style: titleStyle),
        subtitle: Text('HP ${p.hp}  •  ${p.alive ? "alive" : "dead"}'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          TextFormField(
            key: Key('dcc-peasant-$i-name'),
            initialValue: p.name,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (v) => setP(p.copyWith(name: v)),
          ),
          TextFormField(
            key: Key('dcc-peasant-$i-occupation'),
            initialValue: p.occupation,
            decoration: const InputDecoration(labelText: 'Occupation'),
            onChanged: (v) => setP(p.copyWith(occupation: v)),
          ),
          TextFormField(
            key: Key('dcc-peasant-$i-weapon'),
            initialValue: p.weapon,
            decoration: const InputDecoration(labelText: 'Weapon'),
            onChanged: (v) => setP(p.copyWith(weapon: v)),
          ),
          TextFormField(
            key: Key('dcc-peasant-$i-goods'),
            initialValue: p.tradeGoods,
            decoration: const InputDecoration(labelText: 'Trade goods'),
            onChanged: (v) => setP(p.copyWith(tradeGoods: v)),
          ),
          const SizedBox(height: 8),
          _stepper('dcc-peasant-$i-hp', 'HP', p.hp,
              min: 1, max: 8, onSet: (v) => setP(p.copyWith(hp: v))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final k in kDccStats)
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${kDccStatLabels[k]} (${_sign(p.mod(k))})',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                _stepper('dcc-peasant-$i-$k', '', p.stats[k] ?? 10,
                    min: 3,
                    max: 18,
                    onSet: (v) => setP(p.copyWith(stats: {...p.stats, k: v}))),
              ]),
          ]),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton(
                key: Key('dcc-peasant-$i-${p.alive ? "kill" : "revive"}'),
                onPressed: () => setP(p.copyWith(alive: !p.alive)),
                child: Text(p.alive ? 'Mark dead' : 'Mark alive'),
              ),
              if (p.alive)
                FilledButton(
                  key: Key('dcc-peasant-$i-graduate'),
                  onPressed: () => _graduateDialog(context, ref, c, s, i),
                  child: const Text('Graduate →'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _graduateDialog(BuildContext context, WidgetRef ref, Character c,
      DccSheet s, int i) async {
    var cls = 'Warrior';
    var align = 'Neutral';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Graduate to 1st level'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<String>(
              key: const Key('dcc-graduate-class'),
              value: cls,
              isExpanded: true,
              items: kDccClasses
                  .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                  .toList(),
              onChanged: (v) => setState(() => cls = v ?? cls),
            ),
            DropdownButton<String>(
              key: const Key('dcc-graduate-alignment'),
              value: align,
              isExpanded: true,
              items: kDccAlignments
                  .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                  .toList(),
              onChanged: (v) => setState(() => align = v ?? align),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                key: const Key('dcc-graduate-confirm'),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Graduate')),
          ],
        ),
      ),
    );
    if (ok == true) _save(ref, c, s.graduate(i, cls, align));
  }

  // ===================== LEVELED (stub; Task 7) =====================
  Widget _buildLeveled(
          BuildContext context, WidgetRef ref, Character c, DccSheet s) =>
      const SizedBox.shrink();
}
