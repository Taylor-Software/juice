import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';

/// The campaign journal: a forward-reading stream of entries (oldest at top)
/// with a composer pinned at the bottom for free-text and scene entries.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  String? _filterThreadId;
  final TextEditingController _composer = TextEditingController();

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(journalProvider);
    final threads = (ref.watch(threadsProvider).valueOrNull ?? const <Thread>[])
        .where((t) => t.open)
        .toList();
    String threadTitle(String id) => threads
        .firstWhere((t) => t.id == id,
            orElse: () => Thread(id: id, title: '(closed thread)'))
        .title;
    return Column(
      children: [
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (entries) {
              if (entries.isEmpty) {
                return const _Empty(
                    'Your journal is empty. Write below, or roll something and add it.');
              }
              // Storage is newest-first; a reversed ListView reads forward
              // (oldest at top) while anchoring the viewport at the newest
              // entry, chat-style.
              final visible = _filterThreadId == null
                  ? entries
                  : entries
                      .where((e) => e.threadId == _filterThreadId)
                      .toList();
              return Column(
                children: [
                  if (threads.isNotEmpty)
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: const Text('All'),
                              selected: _filterThreadId == null,
                              onSelected: (_) =>
                                  setState(() => _filterThreadId = null),
                            ),
                          ),
                          for (final t in threads)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(t.title),
                                selected: _filterThreadId == t.id,
                                onSelected: (_) =>
                                    setState(() => _filterThreadId = t.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
                      child: TextButton.icon(
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Clear'),
                        onPressed: _confirmClear,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: visible.length,
                      itemBuilder: (context, i) =>
                          _entry(visible[i], threads, threadTitle),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        _composerBar(),
      ],
    );
  }

  // -- Entry rendering ------------------------------------------------------

  Widget _entry(JournalEntry e, List<Thread> threads,
      String Function(String) threadTitle) {
    final menu = PopupMenuButton<String>(
      onSelected: (action) => _onAction(action, e, threads),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'link', child: Text('Link to thread…')),
        const PopupMenuItem(value: 'edit', child: Text('Edit note…')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    switch (e.kind) {
      case JournalKind.scene:
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(e.title, style: theme.textTheme.titleSmall),
              ),
              if (e.chaosFactor != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(
                    label: Text('Chaos ${e.chaosFactor}'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              const Expanded(child: Divider()),
              menu,
            ],
          ),
        );
      case JournalKind.text:
        return Card(
          child: ListTile(
            title: Text(e.body),
            subtitle:
                e.threadId != null ? Text('⤷ ${threadTitle(e.threadId!)}') : null,
            trailing: menu,
          ),
        );
      case JournalKind.result:
        return Card(
          child: ListTile(
            title: Text(e.title),
            subtitle: Text(e.threadId != null
                ? '${e.body}\n⤷ ${threadTitle(e.threadId!)}'
                : e.body),
            trailing: menu,
            isThreeLine: e.body.contains('\n') || e.threadId != null,
          ),
        );
    }
  }

  // -- Composer ---------------------------------------------------------------

  Widget _composerBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('journal-composer'),
                controller: _composer,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Write in your journal…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.movie_outlined),
              tooltip: 'New scene',
              onPressed: _newScene,
            ),
            IconButton(
              key: const Key('journal-send'),
              icon: const Icon(Icons.send),
              tooltip: 'Add to journal',
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    // Clear before the await so a second tap can't re-send the same text.
    _composer.clear();
    await ref.read(journalProvider.notifier).addText(text);
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear journal?'),
        content:
            const Text("This deletes every entry in this campaign's journal."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(journalProvider.notifier).clear();
  }

  Future<void> _newScene() async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => const _SceneDialog(),
    );
    if (!mounted) return;
    if (title == null || title.trim().isEmpty) return;
    await ref.read(journalProvider.notifier).addScene(
          title.trim(),
          chaosFactor: ref.read(crawlProvider).valueOrNull?.chaosFactor,
        );
  }

  // -- Entry actions ----------------------------------------------------------

  Future<void> _onAction(
      String action, JournalEntry entry, List<Thread> threads) async {
    final notifier = ref.read(journalProvider.notifier);
    switch (action) {
      case 'delete':
        await notifier.remove(entry.id);
      case 'link':
        final picked = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Link to thread'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop('__none__'),
                child: const Text('No thread'),
              ),
              for (final t in threads)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(t.id),
                  child: Text(t.title),
                ),
            ],
          ),
        );
        if (picked == null) return;
        await notifier.replace(picked == '__none__'
            ? entry.copyWith(clearThreadId: true)
            : entry.copyWith(threadId: picked));
      case 'edit':
        final result = await showDialog<({String title, String note})>(
          context: context,
          builder: (_) => _EditDialog(
            heading: 'Edit journal entry',
            labelA: 'Title',
            labelB: 'Note',
            initialA: entry.title,
            initialB: entry.body,
          ),
        );
        if (result == null) return;
        // Text entries have no title; scenes have no body. Require only the
        // field that actually carries the entry's content.
        final relevant = entry.kind == JournalKind.text
            ? result.note
            : result.title;
        if (relevant.trim().isEmpty) return;
        await notifier.replace(entry.kind == JournalKind.text
            ? entry.copyWith(body: result.note)
            : entry.copyWith(title: result.title.trim(), body: result.note));
    }
  }
}

// -- Scene dialog -------------------------------------------------------------
class _SceneDialog extends StatefulWidget {
  const _SceneDialog();

  @override
  State<_SceneDialog> createState() => _SceneDialogState();
}

class _SceneDialogState extends State<_SceneDialog> {
  final TextEditingController _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New scene'),
      content: TextField(
        controller: _title,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Scene title'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _title.text),
          child: const Text('Start scene'),
        ),
      ],
    );
  }
}

// -- Edit dialog ---------------------------------------------------------------
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
