import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../shared/destination.dart';
import '../shared/shell_route.dart';
import '../state/providers.dart';

/// One-shot "scroll the journal to this entry" request. The journal consumes
/// (and clears) it post-frame; anything can set it — currently the scene
/// jump sheet. Ephemeral, never persisted.
final journalRevealProvider = StateProvider<String?>((_) => null);

/// Scene jump list: every scene divider in the campaign, newest first.
/// Tapping a row routes to the Journal and scrolls it to that scene.
Future<void> showSceneJumpSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _SceneJumpList(),
    );

class _SceneJumpList extends ConsumerWidget {
  const _SceneJumpList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries =
        ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final scenes = entries
        .where((e) => e.kind == JournalKind.scene)
        .toList(); // newest 1st
    if (scenes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No scenes yet — start one from the journal or the loop.'),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('Jump to scene',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final s in scenes)
          ListTile(
            key: Key('scene-jump-${s.id}'),
            leading: const Icon(Icons.local_fire_department_outlined),
            title: Text(s.title.isEmpty ? '(untitled scene)' : s.title),
            subtitle: s.body.trim().isEmpty
                ? null
                : Text(s.body.trim(),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              ref.read(journalRevealProvider.notifier).state = s.id;
              ref.read(shellRouteProvider.notifier).goTo(Destination.journal);
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }
}
