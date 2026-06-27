import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/funnel.dart';
import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

class FunnelSheetView extends ConsumerWidget {
  const FunnelSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  FunnelSheet get _s => character.funnel!;

  void _save(WidgetRef ref, FunnelSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(funnel: next));

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (character.funnel == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final s = _s;
    final profile = funnelProfileFor(s.seedSystem);
    return ListView(
      key: const Key('funnel-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        sheetNameHeader(context, ref, character,
            onBack: onBack, nameKey: 'funnel-name'),
        Text('0-Level Funnel — ${s.seedSystem}',
            style: theme.textTheme.labelSmall),
        Text('${s.aliveCount} / ${s.peasants.length} alive · '
            '${s.graduatedCount} graduated',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (profile == null)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('No funnel profile for this system.'),
          )
        else ...[
          for (var i = 0; i < s.peasants.length; i++)
            _peasantCard(context, ref, s, profile, i),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('funnel-add-peasant'),
              onPressed: s.peasants.length >= kFunnelMaxPeasants
                  ? null
                  : () => _save(ref,
                      s.copyWith(peasants: [...s.peasants, profile.seedPeasant()])),
              icon: const Icon(Icons.person_add),
              label: const Text('Add peasant'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _peasantCard(BuildContext context, WidgetRef ref, FunnelSheet s,
      FunnelProfile profile, int i) {
    final p = s.peasants[i];
    void setP(FunnelPeasant np) {
      final list = [...s.peasants];
      list[i] = np;
      _save(ref, s.copyWith(peasants: list));
    }

    final dead = !p.alive;
    final titleStyle = p.graduated
        ? const TextStyle(color: Colors.grey)
        : dead
            ? const TextStyle(
                decoration: TextDecoration.lineThrough, color: Colors.grey)
            : null;
    final statusText =
        p.graduated ? 'graduated' : (p.alive ? 'alive' : 'dead');

    return Card(
      child: ExpansionTile(
        key: Key('funnel-peasant-$i'),
        title: Text(p.name.isEmpty ? 'Peasant ${i + 1}' : p.name,
            style: titleStyle),
        subtitle: Text('HP ${p.hp}  •  $statusText'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          TextFormField(
            key: Key('funnel-peasant-$i-name'),
            initialValue: p.name,
            enabled: !p.graduated,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (v) => setP(p.copyWith(name: v)),
          ),
          for (final f in profile.flavorFields)
            TextFormField(
              key: Key('funnel-peasant-$i-flavor-${f.key}'),
              initialValue: p.flavor[f.key] ?? '',
              enabled: !p.graduated,
              decoration: InputDecoration(labelText: f.label),
              onChanged: (v) =>
                  setP(p.copyWith(flavor: {...p.flavor, f.key: v})),
            ),
          const SizedBox(height: 8),
          _stepper('funnel-peasant-$i-hp', 'HP', p.hp,
              min: profile.hpMin,
              max: profile.hpMax,
              onSet: p.graduated ? (_) {} : (v) => setP(p.copyWith(hp: v))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final st in profile.statKeys)
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(st.label,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                _stepper('funnel-peasant-$i-${st.key}',
                    '', p.stats[st.key] ?? profile.statDefault,
                    min: profile.statMin,
                    max: profile.statMax,
                    onSet: p.graduated
                        ? (_) {}
                        : (v) => setP(
                            p.copyWith(stats: {...p.stats, st.key: v}))),
              ]),
          ]),
          const SizedBox(height: 8),
          if (!p.graduated)
            Wrap(alignment: WrapAlignment.spaceBetween, children: [
              TextButton(
                key: Key('funnel-peasant-$i-${p.alive ? "kill" : "revive"}'),
                onPressed: () => setP(p.copyWith(alive: !p.alive)),
                child: Text(p.alive ? 'Mark dead' : 'Mark alive'),
              ),
              if (p.alive)
                FilledButton(
                  key: Key('funnel-peasant-$i-graduate'),
                  onPressed: () => _graduateDialog(context, ref, s, i),
                  child: const Text('Graduate →'),
                ),
            ]),
        ],
      ),
    );
  }

  Future<void> _graduateDialog(
      BuildContext context, WidgetRef ref, FunnelSheet s, int i) async {
    final enabled =
        ref.read(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
            const <String>{};
    final targets = kFunnelProfiles.keys
        .where((sys) => sys == s.seedSystem || enabled.contains(sys))
        .toList();
    if (!targets.contains(s.seedSystem) &&
        funnelProfileFor(s.seedSystem) != null) {
      targets.insert(0, s.seedSystem);
    }
    var target = s.seedSystem;
    var picks = {...funnelProfileFor(target)!.defaultPicks()};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final profile = funnelProfileFor(target)!;
          return AlertDialog(
            title: const Text('Graduate survivor'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButton<String>(
                key: const Key('funnel-graduate-target'),
                value: target,
                isExpanded: true,
                items: targets
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() {
                  target = v ?? target;
                  picks = {...funnelProfileFor(target)!.defaultPicks()};
                }),
              ),
              for (final ch in profile.graduateChoices)
                DropdownButton<String>(
                  key: Key('funnel-graduate-${ch.key}'),
                  value: picks[ch.key],
                  isExpanded: true,
                  items: ch.options
                      .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => picks[ch.key] = v ?? picks[ch.key]!),
                ),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  key: const Key('funnel-graduate-confirm'),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Graduate')),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final profile = funnelProfileFor(target)!;
    final peasant = s.peasants[i];
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(charactersProvider.notifier).graduateFunnelPeasant(
        character, i, (id) => profile.graduate(id, peasant, picks));
    final cls = picks['className'] ?? picks.values.firstOrNull ?? '';
    messenger.showSnackBar(SnackBar(
      content: Text(
          '${peasant.name.isEmpty ? "Peasant" : peasant.name} graduated as a '
          '$target${cls.isEmpty ? "" : " $cls"}'),
      duration: const Duration(seconds: 3),
    ));
  }
}
