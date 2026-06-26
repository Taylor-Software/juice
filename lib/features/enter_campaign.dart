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
/// Use this on the in-shell-switch path, where [context]/[ref] survive the call
/// (the shell stays mounted). The launcher Continue/switch paths can't use this
/// — dismissing the launcher gate disposes their context/ref before the resume
/// route would push — so they call [enterCampaignWith] with handles captured
/// while the launcher is still mounted. The New-campaign path keeps calling
/// [ShellRouteNotifier.landFor] directly (a brand-new campaign has nothing to
/// resume).
Future<void> enterCampaign(
  BuildContext context,
  WidgetRef ref,
  CampaignMode mode,
) async {
  final entries = await ref.read(journalProvider.future);
  final enc = await ref.read(encounterProvider.future);
  if (!context.mounted) return;
  await enterCampaignWith(
    nav: Navigator.of(context, rootNavigator: true),
    shellRoute: ref.read(shellRouteProvider.notifier),
    mode: mode,
    entries: entries,
    hasEncounter: enc.combatants.isNotEmpty,
  );
}

/// The decision half of [enterCampaign], driven by handles + data captured by
/// the caller — so it survives the caller's widget being disposed (the launcher
/// gate dismiss). [nav] must be the ROOT navigator (it outlives the launcher);
/// [shellRoute] is a long-lived Riverpod notifier (safe to hold past disposal).
/// Reads no `ref`/`context` of the caller.
Future<void> enterCampaignWith({
  required NavigatorState nav,
  required ShellRouteNotifier shellRoute,
  required CampaignMode mode,
  required List<JournalEntry> entries,
  required bool hasEncounter,
}) async {
  if (entries.isEmpty) {
    shellRoute.landFor(mode, hasEncounter: hasEncounter);
    return;
  }
  await nav.push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const SessionResumeScreen(),
    ),
  );
}
