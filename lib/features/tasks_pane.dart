import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/tally.dart';
import '../shared/destination.dart';
import '../shared/empty_state.dart';
import '../shared/shell_route.dart';
import '../state/providers.dart';
import 'tracker_screen.dart';

/// Tracking → Tasks: a thin management view over "tasks" — threads that carry a
/// success [Tally]. No new model or persistence; reuses [threadsProvider] and
/// the [ThreadTallyRow] controls. Complementary to the Loop pane's task step.
class TasksPane extends ConsumerWidget {
  const TasksPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(threadsProvider).valueOrNull ?? const <Thread>[];
    final tasks = threads.where((t) => t.tally != null).toList();
    final theme = Theme.of(context);

    if (tasks.isEmpty) {
      return EmptyState(
        icon: Icons.flag_outlined,
        title: 'No tasks yet',
        body: 'Track a major undertaking with a success tally.',
        primaryLabel: 'New task',
        onPrimary: () => _newTask(context, ref),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Tasks', style: theme.textTheme.titleMedium),
              ),
              Flexible(
                child: FilledButton.tonalIcon(
                  key: const Key('task-new'),
                  icon: const Icon(Icons.add),
                  label: const Text('New task'),
                  onPressed: () => _newTask(context, ref),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            children: [
              for (final task in tasks)
                Card(
                  key: Key('task-${task.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        key: Key('task-open-${task.id}'),
                        title: Text(task.title),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => ref
                            .read(shellRouteProvider.notifier)
                            .goTo(Destination.track, subtab: 'threads'),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: ThreadTallyRow(task),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _newTask(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New task'),
        content: TextField(
          key: const Key('task-name'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Task name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Next'),
          ),
        ],
      ),
    );
    // Post-frame: the route's exit transition may still read the controller.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (name == null || name.isEmpty) return;
    if (!context.mounted) return;

    final preset = await showModalBottomSheet<(String, int, int)>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in kTallyPresets)
              ListTile(
                key: Key('task-preset-${p.$1}'),
                title: Text(p.$1),
                trailing: Text('${p.$2}(${p.$3})'),
                onTap: () => Navigator.pop(context, p),
              ),
          ],
        ),
      ),
    );
    if (preset == null) return;

    final notifier = ref.read(threadsProvider.notifier);
    final id = await notifier.addReturningId(name);
    await notifier.setTally(
      id,
      Tally(start: preset.$2, current: preset.$2, target: preset.$3),
    );
  }
}
