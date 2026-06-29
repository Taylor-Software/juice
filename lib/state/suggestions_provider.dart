import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle.dart';
import '../engine/solo_oracle.dart';
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
    hasTally: threads.any((t) => t.tally != null),
  );
});

/// Executes an `inline`-action [Suggestion] (`roll-oracle` / `scene-event`) by
/// rolling against [oracle] and appending the result to the journal. Shared by
/// the assistant rail and the always-visible inline roll dock so the roll
/// behavior lives in exactly one place. Returns the journal write Future so
/// callers can await it (e.g. to scroll to the new entry). Unknown ids are a
/// no-op.
Future<void> rollInlineSuggestion(WidgetRef ref, Oracle oracle, Suggestion s) {
  switch (s.id) {
    case 'roll-oracle':
      final g = fateCheckGenResult(oracle.fateCheck(Likelihood.normal));
      return ref.read(journalProvider.notifier).addResult(g.title, g.asText,
          sourceTool: 'fate-check', payload: g.toPayload());
    case 'ask-yes-no':
      final g = soloYesNo(SoloLikelihood.even, oracle.dice).toGenResult();
      return ref.read(journalProvider.notifier).addResult(g.title, g.asText,
          sourceTool: 'solo-loop', payload: g.toPayload());
    case 'scene-event':
      final g = oracle.randomEvent();
      return ref.read(journalProvider.notifier).addResult(g.title, g.asText,
          sourceTool: 'mythic', payload: g.toPayload());
    default:
      return Future<void>.value();
  }
}
