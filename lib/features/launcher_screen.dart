import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../shared/destination.dart';
import '../shared/home_shell.dart'
    show
        CampaignIdentityLeading,
        NewCampaignDialog,
        NewCampaignResult,
        campaignSubtitle;
import '../shared/shell_route.dart';
import '../state/providers.dart';
import 'enter_campaign.dart';

/// Startup campaign menu: Continue / switch / New / Import. Shown while
/// [launcherGateProvider] is true; every entry action dismisses the gate.
class LauncherScreen extends ConsumerWidget {
  const LauncherScreen({super.key});

  /// Lands on the campaign's mode home — or its in-progress encounter, if any —
  /// then dismisses the launcher gate.
  Future<void> _enter(WidgetRef ref, CampaignMode mode) async {
    final enc = await ref.read(encounterProvider.future);
    ref
        .read(shellRouteProvider.notifier)
        .landFor(mode, hasEncounter: enc.combatants.isNotEmpty);
    ref.read(launcherGateProvider.notifier).dismiss();
  }

  /// "Continue" path: capture everything that must outlive the launcher (the
  /// root navigator + the long-lived shell-route notifier + the resume-decision
  /// data) WHILE STILL MOUNTED, then dismiss the gate and navigate via those
  /// captured handles. Dismissing the gate disposes this widget's context/ref,
  /// so we must not touch them afterward — only the pre-captured `nav`/notifier.
  Future<void> _resume(
      BuildContext context, WidgetRef ref, CampaignMode mode) async {
    final nav = Navigator.of(context, rootNavigator: true);
    final shellRoute = ref.read(shellRouteProvider.notifier);
    final entries = await ref.read(journalProvider.future);
    final enc = await ref.read(encounterProvider.future);

    ref.read(launcherGateProvider.notifier).dismiss();
    // Let the shell mount under the root navigator before pushing resume.
    await WidgetsBinding.instance.endOfFrame;

    await enterCampaignWith(
      nav: nav,
      shellRoute: shellRoute,
      mode: mode,
      entries: entries,
      hasEncounter: enc.combatants.isNotEmpty,
    );
  }

  /// In-launcher campaign switch: switch FIRST (so the session-scoped journal/
  /// encounter providers reflect the new campaign), then capture + decide the
  /// resume hop while still mounted, then dismiss + navigate via the captured
  /// handles. Mirrors [_resume]'s capture-before-dismiss discipline.
  Future<void> _switch(
      BuildContext context, WidgetRef ref, SessionMeta m) async {
    await ref.read(sessionsProvider.notifier).switchTo(m.id);
    if (!context.mounted) return;

    final nav = Navigator.of(context, rootNavigator: true);
    final shellRoute = ref.read(shellRouteProvider.notifier);
    final entries = await ref.read(journalProvider.future);
    final enc = await ref.read(encounterProvider.future);
    if (!context.mounted) return;

    ref.read(launcherGateProvider.notifier).dismiss();
    await WidgetsBinding.instance.endOfFrame;

    await enterCampaignWith(
      nav: nav,
      shellRoute: shellRoute,
      mode: m.mode,
      entries: entries,
      hasEncounter: enc.combatants.isNotEmpty,
    );
  }

  Future<void> _new(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<NewCampaignResult>(
      context: context,
      builder: (context) => const NewCampaignDialog(),
    );
    if (result == null || result.name.trim().isEmpty) return;
    await ref.read(sessionsProvider.notifier).create(result.name.trim(),
        systems: result.systems,
        mode: result.mode,
        genre: result.genre,
        tone: result.tone);
    if (result.start == 'funnel') {
      // Seed the funnel into the new (now-active) campaign, then land on the
      // roster where it lives + dismiss the launcher.
      await ref.read(charactersProvider.notifier).addFunnel(result.seedSystem);
      ref.read(shellRouteProvider.notifier).goTo(Destination.sheet);
      ref.read(launcherGateProvider.notifier).dismiss();
    } else {
      _enter(ref, result.mode);
    }
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
      // Land on the imported campaign's restored mode.
      _enter(
          ref,
          ref.read(sessionsProvider).valueOrNull?.activeMeta.mode ??
              CampaignMode.party);
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
                  onPressed: () => _resume(context, ref, active.mode),
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Continue · ${active.name}'),
                ),
                const SizedBox(height: 16),
                Text('Campaigns', style: theme.textTheme.titleSmall),
                for (final s in sessions.sessions)
                  ListTile(
                    key: Key('launcher-campaign-${s.id}'),
                    leading: CampaignIdentityLeading(
                      meta: s,
                      active: s.id == sessions.active,
                    ),
                    title: Text(s.name),
                    subtitle: Text(
                      campaignSubtitle(s),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    onTap: () => _switch(context, ref, s),
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
