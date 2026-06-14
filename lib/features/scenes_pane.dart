import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/models.dart';
import '../shared/destination.dart';
import '../shared/shell_route.dart';
import '../state/providers.dart';

/// Tracking → Scenes: derived list of journal scene dividers, newest first.
class ScenesPane extends ConsumerWidget {
  const ScenesPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries =
        ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final scenes = entries.where((e) => e.kind == JournalKind.scene).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Scenes',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              // Flexible bounds the button under the loose tool-host width
              // constraints (see the freeze rule).
              Flexible(
                child: FilledButton.tonalIcon(
                  key: const Key('scenes-new'),
                  icon: const Icon(Icons.add),
                  label: const Text('New scene'),
                  onPressed: () => _newScene(context, ref),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: scenes.isEmpty
              ? const Center(child: Text('No scenes yet.'))
              : ListView(
                  children: [
                    for (final s in scenes)
                      ListTile(
                        leading: const Icon(Icons.movie_outlined),
                        title: Text(s.title),
                        subtitle: s.chaosFactor != null
                            ? Text('Chaos ${s.chaosFactor}')
                            : null,
                        onTap: () => ref
                            .read(shellRouteProvider.notifier)
                            .goTo(Destination.journal),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _newScene(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New scene'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Scene title'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Start scene')),
        ],
      ),
    );
    if (title == null || title.trim().isEmpty) return;
    await ref.read(journalProvider.notifier).addScene(
          title.trim(),
          chaosFactor: ref.read(crawlProvider).valueOrNull?.chaosFactor,
        );
  }
}
