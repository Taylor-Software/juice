/// Interpreter service seam. UI and tests depend on this file only; the
/// flutter_gemma implementation lives in interpreter_gemma.dart.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/oracle_interpreter.dart';
import 'interpreter_gemma.dart';

enum InterpreterPhase {
  /// Model not on disk; user consent (download) required.
  needsDownload,

  /// Downloading; [InterpreterStatus.progress] is 0-100.
  installing,

  /// Model on disk, loading into memory.
  loading,

  /// Loaded; interpret() may be called.
  ready,

  /// This platform has no on-device LLM (e.g. web). Hide the feature.
  unsupported,

  /// warmUp failed; [InterpreterStatus.message] says why. Retry allowed.
  error,
}

@immutable
class InterpreterStatus {
  const InterpreterStatus(this.phase, {this.progress = 0, this.message = ''});
  final InterpreterPhase phase;
  final int progress;
  final String message;
}

/// Human download size: MB under 1 GB, else one-decimal GB (decimal MB,
/// matching how model hosts list file sizes).
String formatDownloadSize(int approxMb) => approxMb < 1000
    ? '~$approxMb MB'
    : '~${(approxMb / 1000).toStringAsFixed(1)} GB';

abstract class InterpreterService {
  /// Current lifecycle phase; the sheet rebuilds off this.
  ValueListenable<InterpreterStatus> get status;

  /// Human download size, e.g. '~670 MB' — shown in the consent step.
  String get downloadLabel;

  /// Resolve needsDownload vs (auto-)warmUp: if the model is already on
  /// disk, proceeds to load without further consent.
  Future<void> refresh();

  /// User-consented install + load. Safe to call repeatedly.
  Future<void> warmUp();

  /// One roll = one fresh chat. Requires phase == ready.
  Future<List<OracleInterpretation>> interpret(OracleSeed seed);

  /// Voice one rolled sidekick line in character (plain text). Same
  /// lifecycle contract as [interpret]: requires phase == ready.
  Future<String> voiceLine(VoiceSeed seed);

  /// One-shot recap of recent journal entries (plain text). Requires ready.
  Future<String> summarize(List<String> entries);

  /// Free-form GM answer to a player question (plain text). Same readiness
  /// contract as [voiceLine]: requires phase == ready.
  Future<String> askGm(AskGmSeed seed);

  /// Free-form GM answer continuing a multi-turn conversation (plain text).
  /// Stateless: the whole transcript rides in the prompt. Requires ready.
  Future<String> gmChat(GmChatSeed seed);

  /// Free the native session (model stays on disk). Next use reloads.
  Future<void> dispose();
}

/// App-global service. Overridden with a fake in every widget test —
/// the real implementation touches platform channels.
final interpreterServiceProvider = Provider<InterpreterService>((ref) {
  final service = GemmaInterpreterService();
  ref.onDispose(service.dispose);
  return service;
});

/// Debug-only eval over the engine's seed set (spec "Quality bar").
/// Call from a debug build; prints to console.
Future<void> runInterpreterEval(InterpreterService service) async {
  await service.warmUp();
  for (final seed in kEvalSeeds) {
    final cards = await service.interpret(seed);
    debugPrint('-- ${seed.genre} | ${seed.resultText} --');
    for (final c in cards) {
      debugPrint('  [${c.lens}] ${c.reading}');
    }
  }
}
