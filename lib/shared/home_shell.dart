import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle.dart';
import '../features/journal_screen.dart';
import '../state/interpreter.dart';
import '../state/providers.dart';
import 'tool_host.dart';
import 'tool_registry.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.oracle});
  final Oracle oracle;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  final _hostKey = GlobalKey<ToolHostState>();
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // Mobile: free the native LLM session when backgrounded (the model file
    // stays on disk; next use reloads). Web stays warm — reload is ~40s and
    // browsers fire hide on every tab switch.
    if (!kIsWeb) {
      _lifecycle = AppLifecycleListener(
        onPause: () => ref.read(interpreterServiceProvider).dispose(),
      );
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _showSessions(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) {
          final sessions = ref.watch(sessionsProvider).valueOrNull;
          if (sessions == null) {
            return const Dialog(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return SimpleDialog(
            title: const Text('Campaigns'),
            children: [
              for (final s in sessions.sessions)
                ListTile(
                  leading: Icon(s.id == sessions.active
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off),
                  title: Text(s.name),
                  trailing: sessions.sessions.length > 1
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(dialogContext, s),
                        )
                      : null,
                  onTap: () {
                    ref.read(sessionsProvider.notifier).switchTo(s.id);
                    Navigator.of(dialogContext).pop();
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New campaign'),
                onTap: () => _createSession(dialogContext),
              ),
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('Export campaign'),
                onTap: () => _exportCampaign(dialogContext),
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('Import campaign'),
                onTap: () => _importCampaign(dialogContext),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createSession(BuildContext dialogContext) async {
    final result = await showDialog<({String name, Set<String> systems})>(
      context: dialogContext,
      builder: (context) => const _NewCampaignDialog(),
    );
    if (result == null || result.name.trim().isEmpty) return;
    await ref
        .read(sessionsProvider.notifier)
        .create(result.name.trim(), systems: result.systems);
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
  }

  Future<void> _exportCampaign(BuildContext dialogContext) async {
    final content = await ref.read(sessionsProvider.notifier).exportActive();
    final name =
        ref.read(sessionsProvider).valueOrNull?.activeMeta.name ?? 'campaign';
    var slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
    final fileName = '${slug.isEmpty ? 'campaign' : slug}.juice.json';
    try {
      await FilePicker.saveFile(
        dialogTitle: 'Export campaign',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not access files: ${e.message}')),
      );
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    }
  }

  Future<void> _importCampaign(BuildContext dialogContext) async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: 'Import campaign',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not access files: ${e.message}')),
      );
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      return;
    }
    final bytes = (result == null || result.files.isEmpty)
        ? null
        : result.files.first.bytes;
    if (bytes == null) return; // user cancelled
    try {
      await ref
          .read(sessionsProvider.notifier)
          .importCampaign(utf8.decode(bytes));
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    } on FormatException catch (e) {
      if (!mounted) return;
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        Navigator.of(dialogContext).pop();
      }
    }
  }

  Future<void> _confirmDelete(
      BuildContext dialogContext, SessionMeta session) async {
    final ok = await showDialog<bool>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: Text('Delete "${session.name}"?'),
        content: const Text(
            'Its journal, threads, characters, and crawl state are removed permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(sessionsProvider.notifier).remove(session.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionName =
        ref.watch(sessionsProvider).valueOrNull?.activeMeta.name;
    final rulesets =
        ref.watch(rulesetsProvider).valueOrNull ?? const <String>{};
    final family = [
      if (rulesets.contains('classic')) 'classic',
      if (rulesets.contains('delve')) 'delve',
      if (rulesets.contains('starforged')) 'starforged',
      if (rulesets.contains('sundered_isles')) 'sundered_isles',
    ];
    return Scaffold(
      appBar: AppBar(
        title: sessionName == null
            ? const Text('Juice Oracle')
            : Column(
                children: [
                  const Text('Juice Oracle'),
                  Text(sessionName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.handyman_outlined),
            tooltip: 'Tools',
            onPressed: () => _hostKey.currentState?.openLauncher(),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Rulesets',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => Consumer(builder: (context, ref, _) {
                const rulesetNames = {
                  'classic': 'Ironsworn',
                  'delve': 'Ironsworn: Delve',
                  'starforged': 'Ironsworn: Starforged',
                  'sundered_isles': 'Starforged: Sundered Isles',
                };
                final enabled =
                    ref.watch(rulesetsProvider).valueOrNull ?? const <String>{};
                return SimpleDialog(
                  title: const Text('Rulesets'),
                  children: [
                    for (final id in const [
                      'classic',
                      'delve',
                      'starforged',
                      'sundered_isles'
                    ])
                      SwitchListTile(
                        title: Text(rulesetNames[id]!),
                        subtitle: id == 'classic'
                            ? const Text('Rules © Shawn Tomkin, CC-BY 4.0')
                            : null,
                        value: enabled.contains(id),
                        onChanged: (on) async {
                          final otherFamily = (id == 'classic' || id == 'delve')
                              ? const {'starforged', 'sundered_isles'}
                              : const {'classic', 'delve'};
                          if (on && enabled.any(otherFamily.contains)) {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Switch family?'),
                                content: const Text(
                                    'Ironsworn and Starforged are separate games — enabling this turns the other family off.'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancel')),
                                  FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('Switch')),
                                ],
                              ),
                            );
                            if (ok != true) return;
                          }
                          await ref
                              .read(rulesetsProvider.notifier)
                              .setRuleset(id, on);
                        },
                      ),
                  ],
                );
              }),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder_copy_outlined),
            tooltip: 'Campaigns',
            onPressed: () => _showSessions(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ToolHost(
          key: _hostKey,
          tools: buildToolRegistry(family: family),
          oracle: widget.oracle,
          child: const JournalScreen(),
        ),
      ),
    );
  }
}

/// Dialog for creating a new campaign: name field + four system checkboxes.
/// Returns `({String name, Set<String> systems})?`; null on cancel.
class _NewCampaignDialog extends StatefulWidget {
  const _NewCampaignDialog();

  @override
  State<_NewCampaignDialog> createState() => _NewCampaignDialogState();
}

class _NewCampaignDialogState extends State<_NewCampaignDialog> {
  final _controller = TextEditingController();
  bool _juice = true;
  bool _mythic = true;
  bool _ironsworn = true;
  bool _party = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final picked = <String>{
      if (_juice) 'juice',
      if (_mythic) 'mythic',
      if (_ironsworn) 'ironsworn',
      if (_party) 'party',
    };
    Navigator.of(context).pop((name: _controller.text, systems: picked));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New campaign'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('new-campaign-name'),
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (_) => _submit(),
          ),
          CheckboxListTile(
            key: const Key('sys-juice'),
            title: const Text('Juice oracle'),
            value: _juice,
            onChanged: (v) => setState(() => _juice = v ?? true),
          ),
          CheckboxListTile(
            key: const Key('sys-mythic'),
            title: const Text('Mythic GME'),
            value: _mythic,
            onChanged: (v) => setState(() => _mythic = v ?? true),
          ),
          CheckboxListTile(
            key: const Key('sys-ironsworn'),
            title: const Text('Ironsworn family'),
            value: _ironsworn,
            onChanged: (v) => setState(() => _ironsworn = v ?? true),
          ),
          CheckboxListTile(
            key: const Key('sys-party'),
            title: const Text('Party emulator'),
            value: _party,
            onChanged: (v) => setState(() => _party = v ?? true),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
