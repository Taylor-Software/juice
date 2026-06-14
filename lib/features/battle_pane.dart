import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/lonelog_wargaming.dart';
import '../engine/models.dart';
import '../state/providers.dart';

/// Lonelog Wargaming addon: a compact per-campaign unit roster. Add units, set
/// size + status, and emit a `[BATTLE]` block to the journal.
class BattlePane extends ConsumerStatefulWidget {
  const BattlePane({super.key});

  @override
  ConsumerState<BattlePane> createState() => _BattlePaneState();
}

class _BattlePaneState extends ConsumerState<BattlePane> {
  final _add = TextEditingController();

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _add.text.trim();
    if (name.isEmpty) return;
    ref.read(unitsProvider.notifier).add(name);
    _add.clear();
  }

  Future<void> _edit(Unit u) async {
    final sizeCtrl = TextEditingController(text: u.size);
    var status = u.status;
    final result = await showDialog<Unit>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(u.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('unit-size-input'),
                controller: sizeCtrl,
                decoration: const InputDecoration(
                    labelText: 'Size (×N or full/half/depleted)'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final st in kUnitStatuses)
                    ChoiceChip(
                      label: Text(st),
                      visualDensity: VisualDensity.compact,
                      selected: status == st,
                      onSelected: (sel) =>
                          setLocal(() => status = sel ? st : ''),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context,
                  u.copyWith(size: sizeCtrl.text.trim(), status: status)),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await ref.read(unitsProvider.notifier).updateUnit(result);
    }
  }

  Future<void> _toJournal(List<Unit> units) async {
    await ref
        .read(journalProvider.notifier)
        .add('Battle', battleToLonelog(units));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('[BATTLE] block added to journal')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(unitsProvider).valueOrNull ?? const <Unit>[];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('unit-add'),
                  controller: _add,
                  decoration: const InputDecoration(
                      labelText: 'Add unit', isDense: true),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              IconButton(
                key: const Key('unit-add-btn'),
                icon: const Icon(Icons.add),
                onPressed: _submit,
              ),
            ],
          ),
        ),
        Expanded(
          child: units.isEmpty
              ? const Center(child: Text('No units yet.'))
              : ListView.builder(
                  itemCount: units.length,
                  itemBuilder: (context, i) {
                    final u = units[i];
                    final sub = [
                      if (u.size.isNotEmpty) u.size,
                      if (u.status.isNotEmpty) u.status,
                    ].join(' · ');
                    return ListTile(
                      key: Key('unit-${u.id}'),
                      title: Text(u.name),
                      subtitle: sub.isEmpty ? null : Text(sub),
                      onTap: () => _edit(u),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () =>
                            ref.read(unitsProvider.notifier).remove(u.id),
                      ),
                    );
                  },
                ),
        ),
        if (units.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: OutlinedButton.icon(
              key: const Key('battle-to-journal'),
              icon: const Icon(Icons.post_add_outlined),
              label: const Text('Add [BATTLE] to journal'),
              onPressed: () => _toJournal(units),
            ),
          ),
      ],
    );
  }
}
