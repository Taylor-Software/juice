import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/suggestions.dart';
import 'play_context.dart';
import 'providers.dart';

/// Ranked suggestions for the active campaign, derived from the play state.
/// A plain (sync) Provider: it reads each source's `valueOrNull`, treating
/// still-loading sources as empty, so it always yields at least the always-on
/// suggestions and a consumer mounted during load never crashes.
final suggestionsProvider = Provider<List<Suggestion>>((ref) {
  final journal =
      ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
  final threads = ref.watch(threadsProvider).valueOrNull ?? const <Thread>[];
  final encounter = ref.watch(encounterProvider).valueOrNull;
  final ctx = ref.watch(playContextProvider).valueOrNull;
  final systems =
      ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
          kAllSystems;
  final rulesets = ref.watch(rulesetsProvider).valueOrNull ?? const <String>{};
  final mode = ref.watch(modeProvider);

  final ironswornFamily = systems.contains('ironsworn') &&
      (rulesets.contains('classic') ||
          rulesets.contains('starforged') ||
          rulesets.contains('sundered_isles'));

  return suggestionsFor(
    hasScenes: journal.any((e) => e.kind == JournalKind.scene),
    hasOpenThreads: threads.any((t) => t.open),
    encounterActive: (encounter?.combatants.isNotEmpty) ?? false,
    ironswornFamily: ironswornFamily,
    hasFocusCharacter: ctx?.activeCharacterId != null,
    partyMode: mode == CampaignMode.party,
  );
});
