import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/models.dart';
import '../state/providers.dart';

/// Tracking → Tracks: simple capped progress tracks (clocks) for solo play.
class TracksPane extends ConsumerWidget {
  const TracksPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(tracksProvider).valueOrNull ?? const <Track>[];
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Tracks', style: theme.textTheme.titleMedium),
              ),
              Flexible(
                child: FilledButton.tonalIcon(
                  key: const Key('tracks-add'),
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                  onPressed: () => _add(context, ref),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: tracks.isEmpty
              ? const Center(child: Text('No tracks yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: tracks.length,
                  itemBuilder: (context, i) {
                    final t = tracks[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(t.name,
                                      style: theme.textTheme.titleSmall),
                                ),
                                IconButton(
                                  key: Key('track-dec-$i'),
                                  icon: const Icon(Icons.remove),
                                  tooltip: 'Decrease',
                                  onPressed: t.filled > 0
                                      ? () => ref
                                          .read(tracksProvider.notifier)
                                          .adjust(t.id, -1)
                                      : null,
                                ),
                                Text('${t.filled} / ${t.max}',
                                    style: theme.textTheme.bodyMedium),
                                IconButton(
                                  key: Key('track-inc-$i'),
                                  icon: const Icon(Icons.add),
                                  tooltip: 'Increase',
                                  onPressed: t.filled < t.max
                                      ? () => ref
                                          .read(tracksProvider.notifier)
                                          .adjust(t.id, 1)
                                      : null,
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'rename') {
                                      _rename(context, ref, t);
                                    } else if (v == 'delete') {
                                      ref
                                          .read(tracksProvider.notifier)
                                          .remove(t.id);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: 'rename', child: Text('Rename')),
                                    PopupMenuItem(
                                        value: 'delete', child: Text('Delete')),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: t.max == 0 ? 0 : t.filled / t.max,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = await _nameDialog(context, title: 'New track');
    if (name == null || name.trim().isEmpty) return;
    await ref.read(tracksProvider.notifier).add(name.trim());
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Track t) async {
    final name =
        await _nameDialog(context, title: 'Rename track', initial: t.name);
    if (name == null || name.trim().isEmpty) return;
    await ref.read(tracksProvider.notifier).rename(t.id, name.trim());
  }

  Future<String?> _nameDialog(BuildContext context,
      {required String title, String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Save')),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }
}
