/// Inspire: the shared "read this result for me" affordance.
///
/// Every tool that produces a potential journal entry offers it — the roll is a
/// prompt, not a verdict, and the player retries (the sheet's own Regenerate)
/// until a reading fits their story. One builder ([buildInterpretSeed]) grounds
/// them all, and one format ([appendReading]) lands them all as a single
/// combined entry: the result that was rolled, plus the reading it inspired.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle_interpreter.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import 'oracle_interpretation_sheet.dart';

/// Run the interpretation sheet for [resultText] and return the accepted card
/// (null when dismissed). [excludeId] drops an entry from its own recall.
///
/// The sheet owns generation, Regenerate, and Retry — this is only the seed +
/// modal plumbing.
Future<OracleInterpretation?> showInspire(
  BuildContext context,
  WidgetRef ref, {
  required String resultText,
  String? excludeId,
}) {
  final seed =
      buildInterpretSeed(ref, resultText: resultText, excludeId: excludeId);
  return showModalBottomSheet<OracleInterpretation>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => OracleInterpretationSheet(
      seed: seed,
      onAccept: (card) => Navigator.pop(sheetContext, card),
    ),
  );
}

/// Inspire a [result] that isn't in the journal yet: on accept, log ONE entry
/// carrying the rolls and the reading together. [payload] rides through, so the
/// entry still renders structured (and stays rerollable) via `PayloadCard`.
///
/// [body] overrides the logged/read text for surfaces whose entry body isn't
/// plain `asText` (e.g. a tarot draw folds its card meanings in) — it must match
/// what that surface's own Add-to-journal writes, or `PayloadCard` will render
/// the whole body as an appended remainder instead of structured rolls.
///
/// Returns true when a reading was accepted and logged.
Future<bool> inspireGenResult(
  BuildContext context,
  WidgetRef ref,
  GenResult result, {
  String? sourceTool,
  Map<String, dynamic>? payload,
  String? body,
}) async {
  final text = body ?? result.asText;
  final card = await showInspire(
    context,
    ref,
    resultText: '${result.title}\n$text',
  );
  if (card == null) return false;
  await ref.read(journalProvider.notifier).addResult(
        result.title,
        appendReading(text, card),
        sourceTool: sourceTool,
        payload: payload,
      );
  return true;
}

/// Inspire an entry that's already logged: on accept, append the reading to its
/// body — the same one combined entry, reached from the other direction.
///
/// Re-reads the entry after the sheet closes: it can stay open a long time, so
/// the append must not clobber a concurrent edit or resurrect a deleted entry.
Future<bool> inspireEntry(
  BuildContext context,
  WidgetRef ref,
  String entryId,
) async {
  final entry = _entry(ref, entryId);
  if (entry == null) return false;
  final card = await showInspire(
    context,
    ref,
    resultText:
        entry.title.isEmpty ? entry.body : '${entry.title}\n${entry.body}',
    excludeId: entry.id,
  );
  if (card == null) return false;
  final fresh = _entry(ref, entryId);
  if (fresh == null) return false;
  await ref
      .read(journalProvider.notifier)
      .replace(fresh.copyWith(body: appendReading(fresh.body, card)));
  return true;
}

JournalEntry? _entry(WidgetRef ref, String id) =>
    (ref.read(journalProvider).valueOrNull ?? const <JournalEntry>[])
        .where((e) => e.id == id)
        .firstOrNull;

/// The confirmation SnackBar shown by the instant-log surfaces (custom tables,
/// scenes, combat, HUD/composer draws), carrying an Inspire action that reads
/// the entry just written. Gated: no action when interpret isn't ready.
///
/// Only safe where the HOST stays mounted — this closes over [ref] and [context]
/// for a tap that happens later. Never call it from a dialog/sheet that is about
/// to pop; show it from the caller once the route is gone.
void showLoggedSnackBar(
  BuildContext context,
  WidgetRef ref,
  String entryId, {
  String message = 'Added to journal',
}) {
  final ready = ref.read(interpretReadyProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action: !ready
          ? null
          : SnackBarAction(
              label: 'Inspire',
              onPressed: () => inspireEntry(context, ref, entryId),
            ),
    ),
  );
}
