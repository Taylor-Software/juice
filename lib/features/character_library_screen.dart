// App-global character library manager, opened from the launcher. A library
// of COPIES: nothing here references campaign state, and copying in/out
// always mints fresh ids (see lib/engine/character_library.dart).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/character_library.dart';
import '../engine/models.dart';
import '../shared/undo_snackbar.dart';
import '../state/providers.dart';

class CharacterLibraryScreen extends ConsumerWidget {
  const CharacterLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries =
        ref.watch(characterLibraryProvider).valueOrNull ?? const <Character>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Character library')),
      body: ListView(
        children: [
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No saved characters yet. Copy one in from a '
                  'campaign below, or use "Save to library" on a roster '
                  'character.'),
            ),
          for (final c in entries)
            ListTile(
              key: Key('library-char-${c.id}'),
              title: Text(c.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(sheetRoleBadge(c)),
                  if (c.note.isNotEmpty)
                    Text(c.note, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('library-rename-${c.id}'),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Rename',
                    onPressed: () => _rename(context, ref, c),
                  ),
                  IconButton(
                    key: Key('library-delete-${c.id}'),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete',
                    onPressed: () => _delete(context, ref, c, entries),
                  ),
                ],
              ),
            ),
          const Divider(),
          ListTile(
            key: const Key('library-copy-from-campaign'),
            leading: const Icon(Icons.download_outlined),
            title: const Text('Copy from campaign'),
            onTap: () => _copyFromCampaign(context, ref),
          ),
        ],
      ),
    );
  }

  void _delete(BuildContext context, WidgetRef ref, Character c,
      List<Character> entries) {
    final idx = entries.indexWhere((x) => x.id == c.id);
    // Captured before the snackbar shows: the snackbar's undo callback fires
    // later, and a popped/rebuilt ConsumerWidget's `ref` may already be dead
    // by then.
    final notifier = ref.read(characterLibraryProvider.notifier);
    notifier.remove(c.id);
    showUndoSnackbar(context, '${c.name} deleted',
        () => notifier.insertAt(idx < 0 ? 0 : idx, c));
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Character c) async {
    final ctrl = TextEditingController(text: c.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    await ref.read(characterLibraryProvider.notifier).rename(c.id, name);
  }

  Future<void> _copyFromCampaign(BuildContext context, WidgetRef ref) async {
    final sessions = await ref.read(sessionsProvider.future);
    final prefs = await ref.read(prefsProvider.future);
    if (!context.mounted) return;
    // Step 1: pick a campaign.
    final sessionId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Copy from campaign'),
        children: [
          for (final s in sessions.sessions)
            SimpleDialogOption(
              key: Key('library-src-${s.id}'),
              onPressed: () => Navigator.pop(context, s.id),
              child: Text(s.name),
            ),
          SimpleDialogOption(
            key: const Key('library-src-cancel'),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (sessionId == null || !context.mounted) return;
    // Step 2: pick a character from that campaign's roster.
    final roster = sessionCharactersFromPrefs(prefs, sessionId);
    final picked = await showDialog<Character>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Pick a character'),
        children: [
          if (roster.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No characters in that campaign.'),
            ),
          for (final c in roster)
            SimpleDialogOption(
              key: Key('library-src-char-${c.id}'),
              onPressed: () => Navigator.pop(context, c),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.name),
                  Text(sheetRoleBadge(c),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          SimpleDialogOption(
            key: const Key('library-src-char-cancel'),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await ref.read(characterLibraryProvider.notifier).add(
        libraryCopy(picked, DateTime.now().microsecondsSinceEpoch.toString()));
  }
}
