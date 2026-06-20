import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';

/// Lonelog Resource Tracking addon: a compact per-campaign inventory tracker
/// (`[Inv:Name|qty|props]`). Add items, step quantity, edit properties, delete.
class ResourcesPane extends ConsumerStatefulWidget {
  const ResourcesPane({super.key});

  @override
  ConsumerState<ResourcesPane> createState() => _ResourcesPaneState();
}

class _ResourcesPaneState extends ConsumerState<ResourcesPane> {
  final _add = TextEditingController();

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _add.text.trim();
    if (name.isEmpty) return;
    ref.read(inventoryProvider.notifier).add(name);
    _add.clear();
  }

  Future<void> _editProps(InvItem it) async {
    final ctrl = TextEditingController(text: it.props);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(it.name),
        content: TextField(
          key: const Key('inv-props-input'),
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Properties (condition, charges x/y, …)'),
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
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (result != null) {
      await ref.read(inventoryProvider.notifier).setProps(it.id, result.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(inventoryProvider).valueOrNull ?? const <InvItem>[];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('inv-add'),
                  controller: _add,
                  decoration: const InputDecoration(
                      labelText: 'Add item', isDense: true),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              IconButton(
                key: const Key('inv-add-btn'),
                icon: const Icon(Icons.add),
                onPressed: _submit,
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('No items yet.'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final it = items[i];
                    return ListTile(
                      key: Key('inv-${it.id}'),
                      title:
                          Text('${it.name}${it.qty == 1 ? '' : ' ×${it.qty}'}'),
                      subtitle: it.props.isEmpty ? null : Text(it.props),
                      onTap: () => _editProps(it),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: () => ref
                                .read(inventoryProvider.notifier)
                                .adjustQty(it.id, -1),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () => ref
                                .read(inventoryProvider.notifier)
                                .adjustQty(it.id, 1),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => ref
                                .read(inventoryProvider.notifier)
                                .remove(it.id),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
