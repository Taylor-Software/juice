import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/ironsworn.dart';
import '../engine/models.dart';
import '../shared/result_card.dart';
import '../state/providers.dart';

String _licenseLabel(String licenseUrl) {
  if (licenseUrl.contains('by-nc-sa')) return 'CC-BY-NC-SA 4.0';
  return 'CC-BY 4.0';
}

class MovesScreen extends ConsumerStatefulWidget {
  const MovesScreen({super.key, required this.rulesetIds});
  final List<String> rulesetIds;

  @override
  ConsumerState<MovesScreen> createState() => _MovesScreenState();
}

class _MovesScreenState extends ConsumerState<MovesScreen> {
  final _iron = Ironsworn(Dice());
  GenResult? _last;

  @override
  Widget build(BuildContext context) {
    final asyncs = widget.rulesetIds
        .map((id) => ref.watch(rulesetDataProvider(id)))
        .toList();
    if (asyncs.any((a) => a.isLoading)) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = asyncs.where((a) => a.hasError).firstOrNull;
    if (err != null) return Center(child: Text('Error: ${err.error}'));
    final datas = asyncs.map((a) => a.value!).toList();
    final categories = <Map<String, dynamic>>[
      for (var i = 0; i < datas.length; i++)
        for (final cat in (datas[i]['move_categories'] as List)
            .cast<Map<String, dynamic>>())
          i == 0
              ? cat
              : {
                  ...cat,
                  'name':
                      '${cat['name']} (${(datas[i]['meta'] as Map)['title']})'
                },
    ];
    final collections = <Map<String, dynamic>>[
      for (var i = 0; i < datas.length; i++)
        for (final coll in (datas[i]['oracle_collections'] as List)
            .cast<Map<String, dynamic>>())
          i == 0
              ? coll
              : {
                  ...coll,
                  'name':
                      '${coll['name']} (${(datas[i]['meta'] as Map)['title']})'
                },
    ];
    final attributionLines = datas.map((d) {
      final meta = d['meta'] as Map<String, dynamic>;
      final title = meta['title'] as String;
      final authors = (meta['authors'] as List).join(', ');
      final license = _licenseLabel(meta['license'] as String);
      return '$title © $authors — $license';
    }).join('\n');
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Material(
            child: TabBar(tabs: [Tab(text: 'Moves'), Tab(text: 'Oracles')]),
          ),
          if (_last != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: ResultCard(
                result: _last!,
                onLog: () {
                  ref
                      .read(journalProvider.notifier)
                      .add(_last!.title, _last!.asText);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Added to journal')));
                },
              ),
            ),
          Expanded(
            // IndexedStack (not TabBarView): unbounded page width under the
            // loose tool host → freeze. Same fix as the Maps tool.
            child: Builder(
              builder: (context) {
                final controller = DefaultTabController.of(context);
                return AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => IndexedStack(
                    index: controller.index,
                    children: [
                      _MovesList(
                          categories: categories,
                          onRoll: (g) => setState(() => _last = g),
                          iron: _iron),
                      _OraclesList(
                          collections: collections,
                          onRoll: (g) => setState(() => _last = g),
                          iron: _iron),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              attributionLines,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _MovesList extends StatelessWidget {
  const _MovesList(
      {required this.categories, required this.onRoll, required this.iron});
  final List<Map<String, dynamic>> categories;
  final void Function(GenResult) onRoll;
  final Ironsworn iron;

  @override
  Widget build(BuildContext context) {
    final cats = categories;
    return ListView(
      children: [
        for (final cat in cats)
          ExpansionTile(
            title: Text(cat['name'] as String),
            children: [
              for (final mv
                  in (cat['moves'] as List).cast<Map<String, dynamic>>())
                ListTile(
                  title: Text(mv['name'] as String),
                  subtitle: Text(
                    mv['trigger'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: mv['rollType'] == 'action_roll' ||
                          mv['rollType'] == 'progress_roll'
                      ? const Icon(Icons.casino_outlined)
                      : null,
                  onTap: () => _showMove(context, mv),
                ),
            ],
          ),
      ],
    );
  }

  void _showMove(BuildContext context, Map<String, dynamic> mv) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        var stat = 2, adds = 0, score = 5;
        return StatefulBuilder(builder: (context, setSheet) {
          final rollType = mv['rollType'] as String;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(mv['name'] as String,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(mv['text'] as String),
                const SizedBox(height: 12),
                if (rollType == 'action_roll') ...[
                  _Stepper(
                      label: 'Stat',
                      value: stat,
                      min: 0,
                      max: 5,
                      onChanged: (v) => setSheet(() => stat = v)),
                  _Stepper(
                      label: 'Adds',
                      value: adds,
                      min: 0,
                      max: 5,
                      onChanged: (v) => setSheet(() => adds = v)),
                ],
                if (rollType == 'progress_roll')
                  _Stepper(
                      label: 'Progress',
                      value: score,
                      min: 0,
                      max: 10,
                      onChanged: (v) => setSheet(() => score = v)),
                if (rollType == 'action_roll' || rollType == 'progress_roll')
                  FilledButton(
                    onPressed: () {
                      final r = rollType == 'action_roll'
                          ? iron.actionRoll(stat: stat, adds: adds)
                          : iron.progressRoll(score: score);
                      final outcomeText = (mv['outcomes']
                          as Map<String, dynamic>?)?[switch (r.outcome) {
                        'Strong Hit' => 'strong_hit',
                        'Weak Hit' => 'weak_hit',
                        _ => 'miss',
                      }] as String?;
                      onRoll(GenResult(title: mv['name'] as String, rolls: [
                        Roll(
                            label: 'Outcome',
                            value: r.outcome + (r.match ? ' (match)' : ''),
                            detail: rollType == 'action_roll'
                                ? '${r.actionDie}+${r.total - r.actionDie} vs ${r.challenge1} & ${r.challenge2}'
                                : '${r.total} vs ${r.challenge1} & ${r.challenge2}'),
                        if (outcomeText != null && outcomeText.isNotEmpty)
                          Roll(label: 'Result', value: outcomeText),
                      ]));
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text('Roll'),
                  ),
              ],
            ),
          );
        });
      },
    );
  }
}

({int roll, String text}) rollTable(
    Ironsworn iron, Map<String, dynamic> table) {
  final sides = int.parse((table['dice'] as String).split('d').last);
  final rows = table['rows'] as List;
  if (sides == 100) return iron.oracleRoll(rows);
  final roll = iron.dice.dN(sides);
  dynamic row;
  for (final r in rows) {
    if (roll >= (r[0] as int) && roll <= (r[1] as int)) {
      row = r;
      break;
    }
  }
  row ??= rows.last;
  return (roll: roll, text: row[2] as String);
}

class _OraclesList extends StatelessWidget {
  const _OraclesList(
      {required this.collections, required this.onRoll, required this.iron});
  final List<Map<String, dynamic>> collections;
  final void Function(GenResult) onRoll;
  final Ironsworn iron;

  @override
  Widget build(BuildContext context) {
    final colls = collections;
    return ListView(
      children: [
        for (final coll in colls)
          ExpansionTile(
            title: Text(coll['name'] as String),
            children: [
              for (final table
                  in (coll['tables'] as List).cast<Map<String, dynamic>>())
                ListTile(
                  title: Text(table['name'] as String),
                  trailing: const Icon(Icons.casino_outlined),
                  onTap: () {
                    final r = rollTable(iron, table);
                    onRoll(GenResult(
                      title: '${coll['name']}: ${table['name']}',
                      rolls: [
                        Roll(
                            label: 'Result',
                            value: r.text,
                            detail: '${table['dice']} ${r.roll}'),
                      ],
                    ));
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('$label: $value')),
        IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > min ? () => onChanged(value - 1) : null),
        IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < max ? () => onChanged(value + 1) : null),
      ],
    );
  }
}
