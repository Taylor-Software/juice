/// Interpreter service seam. UI and tests depend on this file only; the
/// flutter_gemma implementation lives in interpreter_gemma.dart.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/oracle_interpreter.dart';
import 'cloud_interpreter.dart';
import 'interpreter_gemma.dart';
import 'providers.dart';

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

  /// Free-form GM answer continuing a multi-turn conversation (plain text).
  /// Stateless: the whole transcript rides in the prompt. Requires ready.
  Future<String> gmChat(GmChatSeed seed);

  /// GM narration: the next scene beat or a complication (plain text). Same
  /// readiness contract as the other seams. Requires ready.
  Future<String> narrate(NarrateSeed seed);

  /// Flesh out an entity (NPC / thread / location) into richer detail (plain
  /// text). Same readiness contract as the other seams. Requires ready.
  Future<String> fleshOut(FleshOutSeed seed);

  /// Rank candidate suggestion chips for the current play state. Best-effort:
  /// returns an empty [RankResult] rather than throwing on a model miss.
  Future<RankResult> rankSuggestions(RankSuggestionsSeed seed);

  /// Free the native session (model stays on disk). Next use reloads.
  Future<void> dispose();
}

/// Wraps an on-device [InterpreterService], routing ONLY interpret() to a
/// [CloudInterpreter] when cloud is enabled and a key is available; every
/// other method delegates straight through unchanged. Takes plain closures
/// (not a Riverpod Ref) so it's constructible and testable without any
/// Riverpod machinery — see interpreterServiceProvider below for how the real
/// app wires the closures to actual providers.
class RoutingInterpreterService implements InterpreterService {
  RoutingInterpreterService(
    this._onDevice, {
    required bool Function() cloudEnabled,
    required Future<String?> Function() cloudApiKey,
    CloudInterpreter? cloudInterpreter,
  })  : _cloudEnabled = cloudEnabled,
        _cloudApiKey = cloudApiKey,
        _cloud = cloudInterpreter ?? const CloudInterpreter();

  final InterpreterService _onDevice;
  final bool Function() _cloudEnabled;
  final Future<String?> Function() _cloudApiKey;
  final CloudInterpreter _cloud;

  @override
  Future<List<OracleInterpretation>> interpret(OracleSeed seed) async {
    if (_cloudEnabled()) {
      final key = await _cloudApiKey();
      if (key != null && key.isNotEmpty) {
        return _cloud.interpret(seed, key);
      }
    }
    return _onDevice.interpret(seed);
  }

  @override
  ValueListenable<InterpreterStatus> get status => _onDevice.status;

  @override
  String get downloadLabel => _onDevice.downloadLabel;

  @override
  Future<void> refresh() => _onDevice.refresh();

  @override
  Future<void> warmUp() => _onDevice.warmUp();

  @override
  Future<String> voiceLine(VoiceSeed seed) => _onDevice.voiceLine(seed);

  @override
  Future<String> summarize(List<String> entries) =>
      _onDevice.summarize(entries);

  @override
  Future<String> gmChat(GmChatSeed seed) => _onDevice.gmChat(seed);

  @override
  Future<String> narrate(NarrateSeed seed) => _onDevice.narrate(seed);

  @override
  Future<String> fleshOut(FleshOutSeed seed) => _onDevice.fleshOut(seed);

  @override
  Future<RankResult> rankSuggestions(RankSuggestionsSeed seed) =>
      _onDevice.rankSuggestions(seed);

  @override
  Future<void> dispose() => _onDevice.dispose();
}

/// App-global service. Overridden with a fake in every widget test —
/// the real implementation touches platform channels.
final interpreterServiceProvider = Provider<InterpreterService>((ref) {
  final onDevice = GemmaInterpreterService();
  ref.onDispose(onDevice.dispose);
  return RoutingInterpreterService(
    onDevice,
    cloudEnabled: () =>
        ref.read(cloudInterpretEnabledProvider).valueOrNull ?? false,
    cloudApiKey: () => ref.read(cloudApiKeyProvider.future),
  );
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
