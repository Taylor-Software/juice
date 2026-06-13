import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/command_registry.dart';
import '../engine/journal_export.dart';
import '../engine/journal_search.dart';
import '../engine/models.dart';
import '../engine/oracle_interpreter.dart';
import '../shared/tool_host.dart';
import '../state/interpreter.dart';
import '../state/providers.dart';
import 'oracle_interpretation_sheet.dart';

/// The campaign journal: a forward-reading stream of entries (oldest at top)
/// with a composer pinned at the bottom for free-text and scene entries.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  /// Save seam: tests swap this to capture (fileName, bytes) instead of
  /// opening the platform save dialog ([FilePicker.saveFile] is static).
  @visibleForTesting
  static Future<void> Function(String fileName, List<int> bytes) saveFile =
      defaultSaveFile;

  @visibleForTesting
  static Future<void> defaultSaveFile(String fileName, List<int> bytes) =>
      FilePicker.saveFile(
        dialogTitle: 'Export journal',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [fileName.split('.').last],
        bytes: Uint8List.fromList(bytes),
      );

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  String? _filterThreadId;
  String? _filterTag;
  bool _searching = false;
  final TextEditingController _composer = TextEditingController();
  final TextEditingController _search = TextEditingController();
  bool _slashActive = false;

  // Built-in (non-registry) slash commands handled inline.
  static const _builtinScene = 'scene';
  static const _builtinHelp = 'help';

  @override
  void initState() {
    super.initState();
    _composer.addListener(_onComposerChanged);
  }

  void _onComposerChanged() {
    final isSlash = _composer.text.startsWith('/');
    if (isSlash != _slashActive) {
      setState(() => _slashActive = isSlash);
    } else if (isSlash) {
      setState(() {}); // refilter as the token changes
    }
  }

  @override
  void dispose() {
    _composer.removeListener(_onComposerChanged);
    _composer.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(journalProvider);
    // Watch the oracle so payload entries gain their re-roll affordance once
    // it finishes loading (re-roll runs a command against it).
    ref.watch(oracleProvider);
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
              final tags = allTags(entries);
              var visible = _filterThreadId == null
                  ? entries
                  : entries
                      .where((e) => e.threadId == _filterThreadId)
                      .toList();
              if (_filterTag != null) {
                visible =
                    visible.where((e) => e.tags.contains(_filterTag)).toList();
              }
              if (_searching) {
                visible = searchEntries(visible, _search.text);
              }
              return Column(
                children: [
                  if (threads.isNotEmpty || tags.isNotEmpty)
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
                              selected:
                                  _filterThreadId == null && _filterTag == null,
                              onSelected: (_) => setState(() {
                                _filterThreadId = null;
                                _filterTag = null;
                              }),
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
                          for (final tag in tags)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                key: Key('tag-chip-$tag'),
                                label: Text('#$tag'),
                                selected: _filterTag == tag,
                                onSelected: (_) => setState(() => _filterTag =
                                    _filterTag == tag ? null : tag),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          key: const Key('journal-search'),
                          icon: const Icon(Icons.search),
                          tooltip: 'Search journal',
                          onPressed: () => setState(() {
                            _searching = !_searching;
                            if (!_searching) _search.clear();
                          }),
                        ),
                        IconButton(
                          key: const Key('journal-export'),
                          icon: const Icon(Icons.ios_share),
                          tooltip: 'Export journal…',
                          onPressed: _export,
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Clear'),
                          onPressed: _confirmClear,
                        ),
                      ],
                    ),
                  ),
                  if (_searching)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: TextField(
                        key: const Key('journal-search-field'),
                        controller: _search,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search journal…',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Close search',
                            onPressed: () => setState(() {
                              _search.clear();
                              _searching = false;
                            }),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
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
        if (_slashActive) _slashPalette(),
        _composerBar(),
      ],
    );
  }

  // -- Entry rendering ------------------------------------------------------

  Widget _entry(JournalEntry e, List<Thread> threads,
      String Function(String) threadTitle) {
    // Read without listening is safe: `unsupported` is decided once in the
    // GemmaInterpreterService constructor and never flips later.
    final canInterpret = e.kind == JournalKind.result &&
        ref.read(interpreterServiceProvider).status.value.phase !=
            InterpreterPhase.unsupported;
    final menu = PopupMenuButton<String>(
      onSelected: (action) => _onAction(action, e, threads),
      itemBuilder: (_) => [
        if (canInterpret)
          const PopupMenuItem(value: 'interpret', child: Text('Interpret…')),
        const PopupMenuItem(value: 'link', child: Text('Link to thread…')),
        const PopupMenuItem(value: 'tags', child: Text('Tags…')),
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
        final extras = _suffixLines(e, threadTitle);
        return Card(
          child: ListTile(
            title: Text(e.body),
            subtitle: extras.isEmpty ? null : Text(extras.join('\n')),
            trailing: menu,
          ),
        );
      case JournalKind.result:
        final extras = _suffixLines(e, threadTitle);
        final p = e.payload;
        if (p != null && p['v'] == 1 && p['rolls'] is List) {
          return _PayloadCard(
            entry: e,
            extras: extras,
            menu: menu,
            onReroll: _canReroll(e) ? () => _reroll(e) : null,
            onOpenTool: e.sourceTool == null
                ? null
                : () {
                    if (!ToolHost.openToolIfKnown(context, e.sourceTool!)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Tool not available')));
                    }
                  },
          );
        }
        return Card(
          child: ListTile(
            title: Text(e.title),
            subtitle: Text([e.body, ...extras].join('\n')),
            trailing: menu,
            isThreeLine: e.body.contains('\n') || extras.isNotEmpty,
          ),
        );
    }
  }

  bool _canReroll(JournalEntry e) {
    final p = e.payload;
    return p != null &&
        p['rerollable'] == true &&
        p['command'] is String &&
        ref.read(oracleProvider).valueOrNull != null;
  }

  Future<void> _reroll(JournalEntry e) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    final p = e.payload;
    if (oracle == null || p == null) return;
    final cmd = commandById(buildCommandRegistry(), p['command'] as String);
    if (cmd == null) return;
    final args = <String, String>{
      for (final entry in ((p['args'] as Map?) ?? const {}).entries)
        '${entry.key}': '${entry.value}',
    };
    if (cmd.id == 'fate-mythic') {
      args['chaos'] =
          '${ref.read(crawlProvider).valueOrNull?.chaosFactor ?? 5}';
    }
    final r = cmd.run(oracle, args);
    await ref.read(journalProvider.notifier).addResult(r.title, r.body,
        sourceTool: e.sourceTool, payload: r.payload);
  }

  /// Runs a registry command from the palette: rolls against the loaded
  /// oracle and drops a structured entry. Mythic pulls live chaos.
  Future<void> _runCommand(CommandDef cmd,
      {String? odds, String? notation}) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final args = <String, String>{};
    if (odds != null) args['odds'] = odds;
    if (notation != null) args['notation'] = notation;
    if (cmd.id == 'fate-mythic') {
      args['chaos'] =
          '${ref.read(crawlProvider).valueOrNull?.chaosFactor ?? 5}';
    }
    try {
      final r = cmd.run(oracle, args);
      await ref.read(journalProvider.notifier).addResult(r.title, r.body,
          sourceTool: cmd.toolId, payload: r.payload);
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Card-subtitle suffix lines: the `⤷ thread` link, then the `#a #b` tags.
  List<String> _suffixLines(
          JournalEntry e, String Function(String) threadTitle) =>
      [
        if (e.threadId != null) '⤷ ${threadTitle(e.threadId!)}',
        if (e.tags.isNotEmpty) e.tags.map((t) => '#$t').join(' '),
      ];

  // -- Slash palette ----------------------------------------------------------

  Widget _slashPalette() {
    final parsed = parseSlash(_composer.text);
    if (parsed == null) return const SizedBox.shrink();
    final registry = buildCommandRegistry();
    // Built-ins surface when their name prefixes the token.
    final showScene = _builtinScene.startsWith(parsed.token.toLowerCase());
    final showHelp = _builtinHelp.startsWith(parsed.token.toLowerCase());
    final matches = matchCommands(registry, parsed.token);
    final theme = Theme.of(context);
    return Material(
      key: const Key('slash-palette'),
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 280),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            for (final c in matches)
              _SlashRow(
                command: c,
                notation: parsed.rest,
                onRun: ({String? odds}) => _selectCommand(c, odds: odds),
              ),
            if (showScene)
              ListTile(
                key: const Key('slash-cmd-scene'),
                dense: true,
                leading: const Icon(Icons.movie_outlined),
                title: const Text('Start a scene'),
                onTap: () {
                  _composer.clear();
                  _newScene();
                },
              ),
            if (showHelp)
              ListTile(
                key: const Key('slash-cmd-help'),
                dense: true,
                leading: const Icon(Icons.help_outline),
                title: const Text('Open Help'),
                onTap: () {
                  _composer.clear();
                  ToolHost.openToolIfKnown(context, 'help');
                },
              ),
            if (matches.isEmpty && !showScene && !showHelp)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No matching command'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectCommand(CommandDef c, {String? odds}) async {
    final parsed = parseSlash(_composer.text);
    _composer.clear(); // also flips _slashActive off via the listener
    await _runCommand(c,
        odds: odds,
        notation: c.arg == CommandArg.notation ? (parsed?.rest ?? '') : null);
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
    final text = _composer.text;
    if (text.startsWith('/')) {
      // Enter runs the first matching command (built-ins win when they
      // exactly head the token); otherwise the palette stays open.
      final parsed = parseSlash(text)!;
      final tok = parsed.token.toLowerCase();
      // A bare '/' with no command typed shouldn't silently fire a roll.
      if (tok.isEmpty) return;
      if (_builtinScene == tok) {
        _composer.clear();
        await _newScene();
        return;
      }
      if (_builtinHelp == tok) {
        _composer.clear();
        if (mounted) ToolHost.openToolIfKnown(context, 'help');
        return;
      }
      final matches = matchCommands(buildCommandRegistry(), parsed.token);
      if (matches.isNotEmpty) await _selectCommand(matches.first);
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _composer.clear();
    await ref.read(journalProvider.notifier).addText(trimmed);
  }

  Future<void> _export() async {
    final built = await _buildExport();
    if (built == null) return;
    final (fileName, content) = built;
    try {
      await JournalScreen.saveFile(fileName, utf8.encode(content));
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not access files: ${e.message}')),
      );
    }
  }

  /// Format dialog + document building. Returns the (fileName, content) the
  /// save seam would write, or null when the user cancels.
  Future<(String, String)?> _buildExport() async {
    final format = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Export journal'),
        children: [
          SimpleDialogOption(
            key: const Key('export-markdown'),
            onPressed: () => Navigator.pop(context, 'md'),
            child: const Text('Markdown'),
          ),
          SimpleDialogOption(
            key: const Key('export-html'),
            onPressed: () => Navigator.pop(context, 'html'),
            child: const Text('HTML'),
          ),
        ],
      ),
    );
    if (format == null || !mounted) return null;
    final entries =
        ref.read(journalProvider).valueOrNull ?? const <JournalEntry>[];
    // All threads, open AND closed, so closed-thread links keep their titles.
    final allThreads =
        ref.read(threadsProvider).valueOrNull ?? const <Thread>[];
    final threadTitles = {for (final t in allThreads) t.id: t.title};
    final name =
        ref.read(sessionsProvider).valueOrNull?.activeMeta.name ?? 'campaign';
    final content = format == 'md'
        ? journalToMarkdown(
            campaignName: name,
            entriesNewestFirst: entries,
            threadTitles: threadTitles,
            exportedAt: DateTime.now())
        : journalToHtml(
            campaignName: name,
            entriesNewestFirst: entries,
            threadTitles: threadTitles,
            exportedAt: DateTime.now());
    var slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
    return ('${slug.isEmpty ? 'campaign' : slug}-journal.$format', content);
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
      case 'interpret':
        await _interpret(entry);
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
      case 'tags':
        final updated = await showDialog<List<String>>(
          context: context,
          builder: (_) => _TagsDialog(initial: entry.tags),
        );
        if (updated == null) return;
        await notifier.replace(entry.copyWith(tags: updated));
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
        final relevant =
            entry.kind == JournalKind.text ? result.note : result.title;
        if (relevant.trim().isEmpty) return;
        await notifier.replace(entry.kind == JournalKind.text
            ? entry.copyWith(body: result.note)
            : entry.copyWith(title: result.title.trim(), body: result.note));
    }
  }

  /// Latest scene entry (storage is newest-first), as model context.
  String _sceneContext() {
    final entries = ref.read(journalProvider).valueOrNull ?? const [];
    for (final e in entries) {
      if (e.kind == JournalKind.scene) {
        final chaos = e.chaosFactor != null ? ' (Chaos ${e.chaosFactor})' : '';
        return 'Scene: ${e.title}$chaos';
      }
    }
    return '';
  }

  Future<void> _interpret(JournalEntry entry) async {
    // Recall: the most relevant past entries ride into the prompt so
    // readings can reference established NPCs, places, and threads.
    final related = relatedEntries(
        ref.read(journalProvider).valueOrNull ?? const [], entry);
    final seed = OracleSeed(
      resultText:
          entry.title.isEmpty ? entry.body : '${entry.title}\n${entry.body}',
      sceneContext: _sceneContext(),
      journalContext: [
        for (final e in related)
          e.title.isEmpty ? e.body : '${e.title} — ${e.body}',
      ],
    );
    final accepted = await showModalBottomSheet<OracleInterpretation>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => OracleInterpretationSheet(
        seed: seed,
        onAccept: (card) => Navigator.pop(sheetContext, card),
      ),
    );
    if (accepted == null || !mounted) return;
    // The sheet can stay open a long time; re-read the entry so the append
    // can't clobber concurrent edits or resurrect a deleted entry.
    final fresh = (ref.read(journalProvider).valueOrNull ?? const [])
        .where((e) => e.id == entry.id)
        .firstOrNull;
    if (fresh == null) return;
    await ref.read(journalProvider.notifier).replace(fresh.copyWith(
        body:
            '${fresh.body}\n\n— Oracle reading (${accepted.lens}): ${accepted.reading}'));
  }
}

// -- Tags dialog ---------------------------------------------------------------
/// Edits an entry's tag list locally; pops the updated list on Save, null on
/// Cancel. Add-tag flow mirrors the character sheet's (tracker_screen.dart).
class _TagsDialog extends StatefulWidget {
  const _TagsDialog({required this.initial});
  final List<String> initial;

  @override
  State<_TagsDialog> createState() => _TagsDialogState();
}

class _TagsDialogState extends State<_TagsDialog> {
  late final List<String> _tags = [...widget.initial];

  Future<void> _addTag() async {
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
    // Preserve case (search compares case-insensitively); dedupe exact.
    final tag = result?.trim() ?? '';
    if (tag.isEmpty || _tags.contains(tag)) return;
    setState(() => _tags.add(tag));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tags'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_tags.isEmpty)
            const Text('No tags yet.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final tag in _tags)
                  InputChip(
                    label: Text(tag),
                    onDeleted: () => setState(() => _tags.remove(tag)),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('add-tag'),
            icon: const Icon(Icons.add),
            label: const Text('Add tag'),
            onPressed: _addTag,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _tags),
          child: const Text('Save'),
        ),
      ],
    );
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

// -- Slash row ----------------------------------------------------------------

class _SlashRow extends StatefulWidget {
  const _SlashRow(
      {required this.command, required this.notation, required this.onRun});
  final CommandDef command;
  final String notation;
  final void Function({String? odds}) onRun;

  @override
  State<_SlashRow> createState() => _SlashRowState();
}

class _SlashRowState extends State<_SlashRow> {
  bool _expanded = false;

  List<String> get _oddsOptions => switch (widget.command.id) {
        'fate-juice' => const ['unlikely', 'normal', 'likely'],
        'fate-mythic' => kMythicOdds,
        'fate-roll-high' => kRollHighOdds,
        _ => const [],
      };

  @override
  Widget build(BuildContext context) {
    final c = widget.command;
    final hasOdds = c.arg == CommandArg.odds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: Key('slash-cmd-${c.id}'),
          dense: true,
          title: Text(c.label),
          subtitle: c.arg == CommandArg.notation
              ? Text(widget.notation.isEmpty
                  ? 'Type dice notation, e.g. /dice 3d6+2'
                  : 'Roll ${widget.notation}')
              : null,
          trailing: hasOdds ? const Icon(Icons.tune, size: 18) : null,
          onTap: () {
            if (hasOdds) {
              setState(() => _expanded = !_expanded);
            } else {
              widget.onRun();
            }
          },
        ),
        if (hasOdds && _expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final o in _oddsOptions)
                  ActionChip(
                    key: Key('slash-odds-$o'),
                    label: Text(o == 'normal'
                        ? 'Normal'
                        : (o.isNotEmpty
                            ? '${o[0].toUpperCase()}${o.substring(1)}'
                            : o)),
                    onPressed: () => widget.onRun(odds: o),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Rich rendering for entries that carry a structured payload: summary +
/// roll rows + appended-notes remainder + re-roll / open-in-tool actions.
class _PayloadCard extends StatelessWidget {
  const _PayloadCard({
    required this.entry,
    required this.extras,
    required this.menu,
    this.onReroll,
    this.onOpenTool,
  });

  final JournalEntry entry;
  final List<String> extras;
  final Widget menu;
  final VoidCallback? onReroll;
  final VoidCallback? onOpenTool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = entry.payload!;
    final summary = p['summary'] as String?;
    final rolls = [
      for (final r in (p['rolls'] as List))
        if (r is Map) ('${r['label']}', '${r['display']}'),
    ];
    // Body content beyond the payload-derived text (e.g. appended oracle
    // readings) still renders; the base text is shown structured instead.
    final rollsText = rolls.map((r) => '${r.$1}: ${r.$2}').join('\n');
    final baseText = summary == null ? rollsText : '$summary\n$rollsText';
    var remainder = '';
    if (entry.body != baseText) {
      remainder = entry.body.startsWith(baseText)
          ? entry.body.substring(baseText.length).trimLeft()
          : entry.body;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child:
                        Text(entry.title, style: theme.textTheme.titleSmall)),
                if (onReroll != null)
                  IconButton(
                    key: Key('entry-reroll-${entry.id}'),
                    tooltip: 'Roll again',
                    icon: const Icon(Icons.replay, size: 20),
                    onPressed: onReroll,
                  ),
                if (onOpenTool != null)
                  IconButton(
                    key: Key('entry-open-tool-${entry.id}'),
                    tooltip: 'Open in tool',
                    icon: const Icon(Icons.open_in_new, size: 20),
                    onPressed: onOpenTool,
                  ),
                menu,
              ],
            ),
            if (summary != null)
              Text(
                summary,
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            const SizedBox(height: 4),
            for (final r in rolls)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        r.$1,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                        child: Text(r.$2, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            if (remainder.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(remainder, style: theme.textTheme.bodyMedium),
            ],
            if (extras.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                extras.join('\n'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
