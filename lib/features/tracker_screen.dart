import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'journal_screen.dart';

class TrackerScreen extends ConsumerWidget {
  const TrackerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const Material(
            child: TabBar(
              tabs: [
                Tab(text: 'Threads'),
                Tab(text: 'Characters'),
                Tab(text: 'Journal'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _ThreadsTab(),
                _CharactersTab(),
                JournalScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -- Threads --------------------------------------------------------------
class _ThreadsTab extends ConsumerWidget {
  const _ThreadsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(threadsProvider);
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (threads) {
          if (threads.isEmpty) {
            return const _Empty('No threads yet. Track quests, vows, mysteries.');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: threads.length,
            itemBuilder: (context, i) {
              final t = threads[i];
              return Card(
                child: ListTile(
                  leading: Checkbox(
                    value: !t.open,
                    onChanged: (_) =>
                        ref.read(threadsProvider.notifier).toggleOpen(t.id),
                  ),
                  title: Text(
                    t.title,
                    style: t.open
                        ? null
                        : TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: theme.colorScheme.onSurfaceVariant),
                  ),
                  subtitle: t.note.isEmpty ? null : Text(t.note),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        ref.read(threadsProvider.notifier).remove(t.id),
                  ),
                  onTap: () => _editThread(context, ref, t),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editThread(context, ref, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _editThread(
      BuildContext context, WidgetRef ref, Thread? existing) async {
    final result = await showDialog<({String title, String note})>(
      context: context,
      builder: (_) => _EditDialog(
        heading: existing == null ? 'New Thread' : 'Edit Thread',
        labelA: 'Title',
        labelB: 'Note (optional)',
        initialA: existing?.title ?? '',
        initialB: existing?.note ?? '',
      ),
    );
    if (result == null || result.title.trim().isEmpty) return;
    final notifier = ref.read(threadsProvider.notifier);
    if (existing == null) {
      await notifier.add(result.title.trim());
      // apply note if provided
      if (result.note.trim().isNotEmpty) {
        final added = ref.read(threadsProvider).valueOrNull?.first;
        if (added != null) {
          await notifier.replace(added.copyWith(note: result.note.trim()));
        }
      }
    } else {
      await notifier.replace(
          existing.copyWith(title: result.title.trim(), note: result.note.trim()));
    }
  }
}

// -- Characters -----------------------------------------------------------
class _CharactersTab extends ConsumerWidget {
  const _CharactersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(charactersProvider);
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (chars) {
          if (chars.isEmpty) {
            return const _Empty('No characters yet. Track NPCs and PCs.');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: chars.length,
            itemBuilder: (context, i) {
              final c = chars[i];
              return Card(
                child: ListTile(
                  title: Text(c.name),
                  subtitle: c.note.isEmpty ? null : Text(c.note),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        ref.read(charactersProvider.notifier).remove(c.id),
                  ),
                  onTap: () => _editCharacter(context, ref, c),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editCharacter(context, ref, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _editCharacter(
      BuildContext context, WidgetRef ref, Character? existing) async {
    final result = await showDialog<({String title, String note})>(
      context: context,
      builder: (_) => _EditDialog(
        heading: existing == null ? 'New Character' : 'Edit Character',
        labelA: 'Name',
        labelB: 'Note (optional)',
        initialA: existing?.name ?? '',
        initialB: existing?.note ?? '',
      ),
    );
    if (result == null || result.title.trim().isEmpty) return;
    final notifier = ref.read(charactersProvider.notifier);
    if (existing == null) {
      await notifier.add(result.title.trim());
      if (result.note.trim().isNotEmpty) {
        final added = ref.read(charactersProvider).valueOrNull?.first;
        if (added != null) {
          await notifier.replace(added.copyWith(note: result.note.trim()));
        }
      }
    } else {
      await notifier.replace(
          existing.copyWith(name: result.title.trim(), note: result.note.trim()));
    }
  }
}

// -- Shared dialog + empty state -----------------------------------------
class _EditDialog extends StatefulWidget {
  const _EditDialog({
    required this.heading,
    required this.labelA,
    required this.labelB,
    required this.initialA,
    required this.initialB,
  });
  final String heading;
  final String labelA;
  final String labelB;
  final String initialA;
  final String initialB;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _a =
      TextEditingController(text: widget.initialA);
  late final TextEditingController _b =
      TextEditingController(text: widget.initialB);

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.heading),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _a,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.labelA),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _b,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(labelText: widget.labelB),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (title: _a.text, note: _b.text)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
