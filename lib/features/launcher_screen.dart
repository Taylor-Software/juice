import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../shared/home_shell.dart' show NewCampaignDialog;
import '../shared/shell_route.dart';
import '../state/providers.dart';

/// Startup campaign menu: Continue / switch / New / Import. Shown while
/// [launcherGateProvider] is true; every entry action dismisses the gate.
class LauncherScreen extends ConsumerWidget {
  const LauncherScreen({super.key});

  /// Lands on the campaign's mode home, then dismisses the launcher gate.
  void _enter(WidgetRef ref, CampaignMode mode) {
    ref.read(shellRouteProvider.notifier).landFor(mode);
    ref.read(launcherGateProvider.notifier).dismiss();
  }

  Future<void> _switch(WidgetRef ref, SessionMeta m) async {
    await ref.read(sessionsProvider.notifier).switchTo(m.id);
    _enter(ref, m.mode);
  }

  Future<void> _new(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<
        ({
          String name,
          Set<String> systems,
          CampaignMode mode,
          String genre,
          String tone
        })>(
      context: context,
      builder: (context) => const NewCampaignDialog(),
    );
    if (result == null || result.name.trim().isEmpty) return;
    await ref.read(sessionsProvider.notifier).create(result.name.trim(),
        systems: result.systems,
        mode: result.mode,
        genre: result.genre,
        tone: result.tone);
    _enter(ref, result.mode);
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: 'Import campaign',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
    } on PlatformException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not access files: ${e.message}')));
      }
      return;
    }
    final bytes = (result == null || result.files.isEmpty)
        ? null
        : result.files.first.bytes;
    if (bytes == null) return; // cancelled
    try {
      await ref
          .read(sessionsProvider.notifier)
          .importCampaign(utf8.decode(bytes));
      // Imported campaigns are always party (files carry no mode).
      _enter(ref, CampaignMode.party);
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, SessionMeta m) async {
    var draft = m.name;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename campaign'),
        content: TextFormField(
          key: const Key('rename-field'),
          initialValue: m.name,
          autofocus: true,
          onChanged: (v) => draft = v,
          onFieldSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('rename-confirm'),
              onPressed: () => Navigator.of(context).pop(draft),
              child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(sessionsProvider.notifier).rename(m.id, name);
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, SessionMeta m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${m.name}"?'),
        content: const Text(
            'Its journal, threads, characters, and maps are removed permanently.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('delete-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await ref.read(sessionsProvider.notifier).remove(m.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sessions = ref.watch(sessionsProvider).valueOrNull;
    if (sessions == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final active = sessions.activeMeta;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Text('Juice', style: theme.textTheme.headlineMedium),
                Text('Solo TTRPG toolkit',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('launcher-continue'),
                  onPressed: () => _enter(ref, active.mode),
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Continue · ${active.name}'),
                ),
                const SizedBox(height: 16),
                Text('Campaigns', style: theme.textTheme.titleSmall),
                for (final s in sessions.sessions)
                  ListTile(
                    key: Key('launcher-campaign-${s.id}'),
                    leading: Icon(s.id == sessions.active
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off),
                    title: Text(s.name),
                    onTap: () => _switch(ref, s),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: Key('launcher-rename-${s.id}'),
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Rename',
                          onPressed: () => _rename(context, ref, s),
                        ),
                        if (sessions.sessions.length > 1)
                          IconButton(
                            key: Key('launcher-delete-${s.id}'),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Delete',
                            onPressed: () => _delete(context, ref, s),
                          ),
                      ],
                    ),
                  ),
                const Divider(),
                ListTile(
                  key: const Key('launcher-new'),
                  leading: const Icon(Icons.add),
                  title: const Text('New campaign'),
                  onTap: () => _new(context, ref),
                ),
                ListTile(
                  key: const Key('launcher-import'),
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Import from file'),
                  onTap: () => _import(context, ref),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
