import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/loop_kit.dart';
import '../engine/models.dart';
import '../shared/destination.dart';
import '../shared/home_shell.dart'
    show
        CampaignIdentityLeading,
        NewCampaignDialog,
        NewCampaignResult,
        campaignSubtitle;
import '../shared/shell_route.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import 'ai_offer_dialog.dart';
import 'enter_campaign.dart';

/// Startup campaign menu: Continue / switch / New / Import. Shown while
/// [launcherGateProvider] is true; every entry action dismisses the gate.
class LauncherScreen extends ConsumerWidget {
  const LauncherScreen({super.key});

  /// Lands on the Journal — or the in-progress encounter, if any — then
  /// dismisses the launcher gate.
  Future<void> _enter(WidgetRef ref) async {
    final enc = await ref.read(encounterProvider.future);
    ref
        .read(shellRouteProvider.notifier)
        .land(hasEncounter: enc.combatants.isNotEmpty);
    ref.read(launcherGateProvider.notifier).dismiss();
  }

  /// "Continue" path: capture everything that must outlive the launcher (the
  /// root navigator + the long-lived shell-route notifier + the resume-decision
  /// data) WHILE STILL MOUNTED, then dismiss the gate and navigate via those
  /// captured handles. Dismissing the gate disposes this widget's context/ref,
  /// so we must not touch them afterward — only the pre-captured `nav`/notifier.
  Future<void> _resume(BuildContext context, WidgetRef ref) async {
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
      entries: entries,
      hasEncounter: enc.combatants.isNotEmpty,
    );
  }

  Future<void> _new(BuildContext context, WidgetRef ref,
      {bool wasPristine = false}) async {
    final kits = ref.read(kitsProvider).valueOrNull ?? const <LoopKit>[];
    final oracles =
        ref.read(constructedOraclesProvider).valueOrNull ?? const [];
    final result = await showDialog<NewCampaignResult>(
      context: context,
      builder: (context) => NewCampaignDialog(kits: kits, oracles: oracles),
    );
    if (result == null || result.name.trim().isEmpty) return;
    await ref.read(sessionsProvider.notifier).create(result.name.trim(),
        systems: result.systems, genre: result.genre, tone: result.tone);
    await ref
        .read(settingsProvider.notifier)
        .setDefaultOracle(result.defaultOracle);
    // First real campaign replaces the untouched first-run placeholder.
    if (wasPristine) {
      await ref.read(sessionsProvider.notifier).remove('default');
    }
    if (result.start == 'funnel') {
      // Seed the funnel into the new (now-active) campaign, then land on the
      // roster where it lives + dismiss the launcher.
      await ref.read(charactersProvider.notifier).addFunnel(result.seedSystem);
      ref.read(shellRouteProvider.notifier).goTo(Destination.sheet);
      ref.read(launcherGateProvider.notifier).dismiss();
    } else {
      if (result.start == 'kit' && result.kit != null) {
        await applyLoopKit(ref, result.kit!);
      }
      unawaited(_enter(ref));
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref,
      {bool wasPristine = false}) async {
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
      // First real campaign replaces the untouched first-run placeholder.
      if (wasPristine) {
        await ref.read(sessionsProvider.notifier).remove('default');
      }
      unawaited(_enter(ref));
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
    // Pre-warm the bundled loop kits so they're ready by the time the user
    // opens the New-campaign wizard (avoids a first-tap race where the
    // "Import a kit" step would show no kits yet).
    ref.watch(kitsProvider);
    final theme = Theme.of(context);
    final sessions = ref.watch(sessionsProvider).valueOrNull;
    if (sessions == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final active = sessions.activeMeta;
    final welcomeSeen = ref.watch(welcomeSeenProvider).valueOrNull ?? false;
    final showWelcome = !welcomeSeen && sessions.sessions.length == 1;
    final lastExport = ref.watch(lastExportProvider).valueOrNull;
    final journalEntries =
        ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final hasJournal = journalEntries.isNotEmpty;
    final staleDays = lastExport == null
        ? null
        : DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(lastExport))
            .inDays;
    final showBackupNudge = !showWelcome &&
        hasJournal &&
        (lastExport == null || (staleDays != null && staleDays >= 7));
    // Untouched first-run placeholder: route the user into the creation
    // wizard instead of "Continue"-ing into a legacy-shaped Campaign 1.
    // Legacy migration fills the journal and a rename changes the name, so
    // both fall back to the normal launcher.
    final pristine = sessions.sessions.length == 1 &&
        sessions.active == 'default' &&
        active.name == 'Campaign 1' &&
        !hasJournal;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Text("Solo Adventurer's Journal",
                    style: theme.textTheme.headlineMedium),
                Text('Solo TTRPG toolkit',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                // Invisible: fires the one-time first-run AI-enhancements offer
                // once the welcome card is out of the way (see _AiOfferGate).
                _AiOfferGate(welcomeShowing: showWelcome),
                if (showWelcome) ...[
                  const SizedBox(height: 16),
                  _WelcomeCard(
                      onDismiss: () =>
                          ref.read(welcomeSeenProvider.notifier).markSeen()),
                ],
                if (showBackupNudge) ...[
                  const SizedBox(height: 16),
                  _BackupNudge(lastExportMs: lastExport),
                ],
                const SizedBox(height: 24),
                if (pristine) ...[
                  FilledButton.icon(
                    key: const Key('launcher-start-first'),
                    onPressed: () => _new(context, ref, wasPristine: true),
                    icon: const Icon(Icons.auto_stories),
                    label: const Text('Start your first adventure'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('launcher-skip-blank'),
                    onPressed: () => _resume(context, ref),
                    child: const Text('Skip — open a blank campaign'),
                  ),
                  const Divider(),
                  ListTile(
                    key: const Key('launcher-import'),
                    leading: const Icon(Icons.file_download_outlined),
                    title: const Text('Import from file'),
                    onTap: () => _import(context, ref, wasPristine: true),
                  ),
                ] else ...[
                  FilledButton.icon(
                    key: const Key('launcher-continue'),
                    onPressed: () => _resume(context, ref),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Invisible gate that shows the first-run AI-enhancements offer exactly once.
///
/// Fires (post-frame, guarded so it only fires once per mount) when: the
/// platform supports on-device AI, AI isn't already enabled, the offer hasn't
/// been shown before, and the welcome card isn't currently on screen — so a
/// true first-run user reads the welcome first, then gets the AI offer after
/// dismissing it; an existing user who never enabled AI is offered once on
/// their next launch (welcome already seen → offer fires immediately).
class _AiOfferGate extends ConsumerStatefulWidget {
  const _AiOfferGate({required this.welcomeShowing});
  final bool welcomeShowing;

  @override
  ConsumerState<_AiOfferGate> createState() => _AiOfferGateState();
}

class _AiOfferGateState extends ConsumerState<_AiOfferGate> {
  bool _fired = false;

  @override
  Widget build(BuildContext context) {
    if (!_fired && !widget.welcomeShowing) {
      final supported = ref.watch(aiSupportedProvider);
      final enabled = ref.watch(aiEnabledProvider).valueOrNull;
      final offerSeen = ref.watch(aiOfferSeenProvider).valueOrNull;
      // All three gates must be resolved (non-loading) before we act, so a
      // still-loading flag never suppresses the offer or fires it prematurely.
      if (supported && enabled == false && offerSeen == false) {
        _fired = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showAiFirstRunOffer(context, ref);
        });
      }
    }
    return const SizedBox.shrink();
  }
}

/// First-launch welcome card. Shown once until the user dismisses it.
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      key: const Key('welcome-card'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              "Solo Adventurer's Journal is a solo-TTRPG toolkit. There's no "
              'DM — you narrate, and oracle rolls answer the questions you '
              'ask. Journal sessions, track threads, run maps and encounters.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 8),
            _Bullet(
                icon: Icons.auto_stories_outlined,
                text: 'Journal — write prose, log oracle rolls, recap scenes',
                color: muted),
            _Bullet(
                icon: Icons.casino_outlined,
                text: 'Ask — roll fate checks, generators, and custom tables',
                color: muted),
            _Bullet(
                icon: Icons.label_outline,
                text: 'Track — threads, characters, encounters, and maps',
                color: muted),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('welcome-dismiss'),
                onPressed: onDismiss,
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: color)),
          ),
        ]),
      );
}

/// Backup nudge card shown when the campaign has journal entries but hasn't
/// been exported recently (never or >7 days ago).
class _BackupNudge extends StatelessWidget {
  const _BackupNudge({required this.lastExportMs});
  final int? lastExportMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final subtitle = lastExportMs == null
        ? 'You haven\'t exported this campaign yet.'
        : 'Last exported ${_daysAgo(lastExportMs!)} ago.';
    return Card(
      key: const Key('backup-nudge'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            Icon(Icons.backup_outlined, color: muted, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Back up your campaign',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('Campaigns menu → Export',
                style: theme.textTheme.labelSmall?.copyWith(color: muted)),
          ],
        ),
      ),
    );
  }

  static String _daysAgo(int ms) {
    final days = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ms))
        .inDays;
    if (days == 0) return 'today';
    if (days == 1) return '1 day';
    return '$days days';
  }
}
