import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/home_shell.dart' show NewCampaignDialog;
import '../state/providers.dart';

/// Startup campaign menu: Continue / switch / New / Import. Shown while
/// [launcherGateProvider] is true; every entry action dismisses the gate.
class LauncherScreen extends ConsumerWidget {
  const LauncherScreen({super.key});

  void _enter(WidgetRef ref) =>
      ref.read(launcherGateProvider.notifier).dismiss();

  Future<void> _switch(WidgetRef ref, String id) async {
    await ref.read(sessionsProvider.notifier).switchTo(id);
    _enter(ref);
  }

  Future<void> _new(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<
        ({String name, Set<String> systems, String genre, String tone})>(
      context: context,
      builder: (context) => const NewCampaignDialog(),
    );
    if (result == null || result.name.trim().isEmpty) return;
    await ref.read(sessionsProvider.notifier).create(result.name.trim(),
        systems: result.systems, genre: result.genre, tone: result.tone);
    _enter(ref);
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
      _enter(ref);
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
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
                  onPressed: () => _enter(ref),
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
                    onTap: () => _switch(ref, s.id),
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
