import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/models.dart';
import '../state/providers.dart';

/// Tracking → Rumors: a per-campaign list of leads/rumors to resolve.
class RumorsPane extends ConsumerWidget {
  const RumorsPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rumors = ref.watch(rumorsProvider).valueOrNull ?? const <Rumor>[];
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Rumors', style: theme.textTheme.titleMedium),
              ),
              // Flexible bounds the button under the loose host width
              // constraints (freeze rule).
              Flexible(
                child: FilledButton.tonalIcon(
                  key: const Key('rumors-add'),
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                  onPressed: () => _add(context, ref),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: rumors.isEmpty
              ? const Center(child: Text('No rumors yet.'))
              : ListView(
                  children: [
                    for (final r in rumors)
                      CheckboxListTile(
                        key: Key('rumor-${r.id}'),
                        value: r.resolved,
                        onChanged: (_) => ref
                            .read(rumorsProvider.notifier)
                            .toggleResolved(r.id),
                        title: Text(
                          r.text,
                          style: r.resolved
                              ? TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  color: theme.colorScheme.onSurfaceVariant)
                              : null,
                        ),
                        subtitle: r.note.isEmpty ? null : Text(r.note),
                        secondary: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete',
                          onPressed: () =>
                              ref.read(rumorsProvider.notifier).remove(r.id),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add rumor'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Rumor'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Add')),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (text == null || text.trim().isEmpty) return;
    await ref.read(rumorsProvider.notifier).add(text.trim());
  }
}
