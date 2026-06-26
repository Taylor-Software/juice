import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../shared/shell_route.dart';
import '../state/providers.dart';
import 'session_resume_screen.dart';

/// Enters [mode]'s campaign. When the campaign has prior session state (≥1
/// journal entry) it shows the [SessionResumeScreen] "where did I leave off?"
/// ritual — pushed over the shell — instead of dropping straight onto the last
/// verb; the resume screen's Continue then calls [ShellRouteNotifier.landFor]
/// and pops. A fresh campaign (no entries) lands directly, as before.
///
/// Use this on the "Continue"/in-shell-switch paths. The New-campaign path
/// keeps calling [landFor] directly (a brand-new campaign has nothing to
/// resume).
Future<void> enterCampaign(
  BuildContext context,
  WidgetRef ref,
  CampaignMode mode,
) async {
  final entries = await ref.read(journalProvider.future);
  if (entries.isEmpty) {
    final enc = await ref.read(encounterProvider.future);
    ref
        .read(shellRouteProvider.notifier)
        .landFor(mode, hasEncounter: enc.combatants.isNotEmpty);
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const SessionResumeScreen(),
    ),
  );
}
