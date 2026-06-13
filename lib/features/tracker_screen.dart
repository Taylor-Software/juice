import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';

class TrackerScreen extends ConsumerWidget {
  const TrackerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Material(
            child: TabBar(
              tabs: [
                Tab(text: 'Threads'),
                Tab(text: 'Characters'),
              ],
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
                    children: const [
                      _ThreadsTab(),
                      _CharactersTab(),
                    ],
                  ),
                );
              },
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
            return const _Empty(
                'No threads yet. Track quests, vows, mysteries.');
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('pin-thread-${t.id}'),
                        visualDensity: VisualDensity.compact,
                        icon: Icon(t.pinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined),
                        tooltip: t.pinned ? 'Unpin' : 'Pin',
                        onPressed: () => ref
                            .read(threadsProvider.notifier)
                            .togglePinned(t.id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () =>
                            ref.read(threadsProvider.notifier).remove(t.id),
                      ),
                    ],
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
      await notifier.replace(existing.copyWith(
          title: result.title.trim(), note: result.note.trim()));
    }
  }
}

// -- Characters -----------------------------------------------------------
class _CharactersTab extends ConsumerStatefulWidget {
  const _CharactersTab();

  @override
  ConsumerState<_CharactersTab> createState() => _CharactersTabState();
}

class _CharactersTabState extends ConsumerState<_CharactersTab> {
  /// Id of the character whose sheet is open, or null for the list view.
  String? _editingId;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(charactersProvider);
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (chars) {
          if (_editingId != null) {
            // Resolve fresh each build; if the id vanished (e.g. session
            // switch), fall back to the list view.
            final match = chars.where((c) => c.id == _editingId);
            if (match.isEmpty) {
              _editingId = null;
            } else {
              return _buildSheet(context, match.first);
            }
          }
          if (chars.isEmpty) {
            return const _Empty('No characters yet. Track NPCs and PCs.');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: chars.length,
            itemBuilder: (context, i) {
              final c = chars[i];
              final t = c.tracks.isEmpty ? null : c.tracks.first;
              return Card(
                child: ListTile(
                  title: Text(c.name),
                  subtitle: t != null
                      ? Text('${t.label} ${t.current}/${t.max}')
                      : (c.note.isEmpty ? null : Text(c.note)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('star-char-${c.id}'),
                        visualDensity: VisualDensity.compact,
                        icon: Icon(c.starred ? Icons.star : Icons.star_border),
                        tooltip: c.starred ? 'Unstar' : 'Star',
                        onPressed: () => ref
                            .read(charactersProvider.notifier)
                            .toggleStarred(c.id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () =>
                            ref.read(charactersProvider.notifier).remove(c.id),
                      ),
                    ],
                  ),
                  onTap: () => setState(() => _editingId = c.id),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: _editingId == null
          ? FloatingActionButton(
              onPressed: () => _addCharacter(context),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Future<void> _addCharacter(BuildContext context) async {
    final result = await showDialog<({String title, String note})>(
      context: context,
      builder: (_) => const _EditDialog(
        heading: 'New Character',
        labelA: 'Name',
        labelB: 'Note (optional)',
        initialA: '',
        initialB: '',
      ),
    );
    if (result == null || result.title.trim().isEmpty) return;
    final notifier = ref.read(charactersProvider.notifier);
    await notifier.add(result.title.trim());
    final added = ref.read(charactersProvider).valueOrNull?.first;
    if (added == null) return;
    if (result.note.trim().isNotEmpty) {
      await notifier.replace(added.copyWith(note: result.note.trim()));
    }
    if (mounted) setState(() => _editingId = added.id);
  }

  Future<void> _editNameNote(BuildContext context, Character c) async {
    final result = await showDialog<({String title, String note})>(
      context: context,
      builder: (_) => _EditDialog(
        heading: 'Edit Character',
        labelA: 'Name',
        labelB: 'Note (optional)',
        initialA: c.name,
        initialB: c.note,
      ),
    );
    if (result == null || result.title.trim().isEmpty) return;
    await ref.read(charactersProvider.notifier).replace(
        c.copyWith(name: result.title.trim(), note: result.note.trim()));
  }

  Future<void> _replace(Character updated) =>
      ref.read(charactersProvider.notifier).replace(updated);

  Widget _buildSheet(BuildContext context, Character c) {
    final theme = Theme.of(context);
    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(title, style: theme.textTheme.titleMedium),
        );
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('sheet-back'),
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _editingId = null),
            ),
            Expanded(
              child: Text(c.name,
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit name & notes',
              onPressed: () => _editNameNote(context, c),
            ),
          ],
        ),
        section('Stats'),
        for (var i = 0; i < c.stats.length; i++)
          Row(
            children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: c.stats[i].label,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: '  ${c.stats[i].value}'),
                ])),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    _replace(c.copyWith(stats: [...c.stats]..removeAt(i))),
              ),
            ],
          ),
        OutlinedButton.icon(
          key: const Key('add-stat'),
          icon: const Icon(Icons.add),
          label: const Text('Add stat'),
          onPressed: () => _addStat(context, c),
        ),
        section('Tracks'),
        for (var i = 0; i < c.tracks.length; i++)
          Row(
            children: [
              Expanded(child: Text(c.tracks[i].label)),
              IconButton(
                key: Key('track-minus-$i'),
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => _replace(c.copyWith(
                    tracks: [...c.tracks]..[i] = c.tracks[i].adjusted(-1))),
              ),
              Text('${c.tracks[i].current}/${c.tracks[i].max}'),
              IconButton(
                key: Key('track-plus-$i'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _replace(c.copyWith(
                    tracks: [...c.tracks]..[i] = c.tracks[i].adjusted(1))),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    _replace(c.copyWith(tracks: [...c.tracks]..removeAt(i))),
              ),
            ],
          ),
        OutlinedButton.icon(
          key: const Key('add-track'),
          icon: const Icon(Icons.add),
          label: const Text('Add track'),
          onPressed: () => _addTrack(context, c),
        ),
        section('Tags'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final tag in c.tags)
              InputChip(
                label: Text(tag),
                onDeleted: () => _replace(
                    c.copyWith(tags: c.tags.where((t) => t != tag).toList())),
              ),
          ],
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          key: const Key('add-tag'),
          icon: const Icon(Icons.add),
          label: const Text('Add tag'),
          onPressed: () => _addTag(context, c),
        ),
        // Read-only summary; the Party Emulator tool owns the editing.
        if (c.emulation != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Emulation: ${c.emulation!.prominentTags.length} prominent '
              'traits · ${c.emulation!.tokens} tokens',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        section('Notes'),
        Text(c.note.isEmpty ? '—' : c.note),
      ],
    );
  }

  Future<void> _addStat(BuildContext context, Character c) async {
    final result = await showDialog<({String label, String value})>(
      context: context,
      builder: (context) {
        final label = TextEditingController();
        final value = TextEditingController();
        return AlertDialog(
          title: const Text('Add stat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('stat-label'),
                controller: label,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('stat-value'),
                controller: value,
                decoration: const InputDecoration(labelText: 'Value'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                  context, (label: label.text, value: value.text)),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    if (result == null || result.label.trim().isEmpty) return;
    await _replace(c.copyWith(stats: [
      ...c.stats,
      CharStat(label: result.label.trim(), value: result.value.trim()),
    ]));
  }

  Future<void> _addTrack(BuildContext context, Character c) async {
    final result = await showDialog<({String label, String max})>(
      context: context,
      builder: (context) {
        final label = TextEditingController();
        final max = TextEditingController();
        return AlertDialog(
          title: const Text('Add track'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('track-label'),
                controller: label,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('track-max'),
                controller: max,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Max'),
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
                  Navigator.pop(context, (label: label.text, max: max.text)),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    if (result == null || result.label.trim().isEmpty) return;
    var max = int.tryParse(result.max.trim()) ?? 1;
    if (max < 1) max = 1;
    await _replace(c.copyWith(tracks: [
      ...c.tracks,
      CharTrack(label: result.label.trim(), current: max, max: max),
    ]));
  }

  Future<void> _addTag(BuildContext context, Character c) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final tag = TextEditingController();
        return AlertDialog(
          title: const Text('Add tag'),
          content: TextField(
            key: const Key('tag-input'),
            controller: tag,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tag'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, tag.text),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    final tag = result?.trim() ?? '';
    if (tag.isEmpty || c.tags.contains(tag)) return;
    await _replace(c.copyWith(tags: [...c.tags, tag]));
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
