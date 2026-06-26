/// flutter_gemma-backed interpreter. Never constructed in tests.
///
/// Mobile/desktop: Gemma 4 E2B int4 `.litertlm` (`ModelType.gemma4`) from the
/// ungated litert-community repo, downloaded on demand (~2.6 GB) — never
/// bundled. The on-device LLM is DISABLED on web (no model): web reports
/// `unsupported` and the UI hides every AI affordance.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../engine/oracle_interpreter.dart';
import 'interpreter.dart';

class _ModelSpec {
  const _ModelSpec({
    required this.url,
    required this.filename,
    required this.modelType,
    required this.fileType,
    required this.approxMb,
  });
  final String url;
  final String filename;
  final ModelType modelType;
  final ModelFileType fileType;
  final int approxMb;
}

const _gemma4Spec = _ModelSpec(
  url:
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
  filename: 'gemma-4-E2B-it.litertlm',
  modelType: ModelType.gemma4,
  fileType: ModelFileType.litertlm,
  approxMb: 2588,
);

class GemmaInterpreterService implements InterpreterService {
  GemmaInterpreterService() {
    if (kIsWeb) {
      _status.value = const InterpreterStatus(InterpreterPhase.unsupported,
          message: 'On-device AI runs in the mobile and desktop apps, '
              'not on the web.');
    }
  }

  final _spec = _gemma4Spec;
  final _status =
      ValueNotifier(const InterpreterStatus(InterpreterPhase.needsDownload));
  InferenceModel? _model;

  /// Single-flight warm-up: concurrent warmUp() calls join this future.
  Future<void>? _warming;

  /// Set by dispose(); a warm-up that finishes after dispose() must not
  /// resurrect the service with a model nobody will close.
  bool _disposed = false;

  @override
  ValueListenable<InterpreterStatus> get status => _status;

  @override
  String get downloadLabel => formatDownloadSize(_spec.approxMb);

  bool get _unsupported => _status.value.phase == InterpreterPhase.unsupported;

  @override
  Future<void> refresh() async {
    if (_unsupported || _model != null || _warming != null) return;
    try {
      if (await FlutterGemma.isModelInstalled(_spec.filename)) {
        await warmUp(); // already consented (it's on disk) — just load
      } else {
        _status.value = const InterpreterStatus(InterpreterPhase.needsDownload);
      }
    } catch (e) {
      _status.value = InterpreterStatus(InterpreterPhase.error, message: '$e');
    }
  }

  @override
  Future<void> warmUp() {
    if (_unsupported || _model != null) return Future.value();
    _disposed = false; // an explicit re-warm after dispose() is valid
    // Join any in-flight warm-up instead of double-installing/loading.
    // _doWarmUp never throws (errors land in _status), so whenComplete
    // always runs and _warming can't get stuck on a failed attempt.
    return _warming ??= _doWarmUp().whenComplete(() => _warming = null);
  }

  Future<void> _doWarmUp() async {
    try {
      if (!await FlutterGemma.isModelInstalled(_spec.filename)) {
        _status.value = const InterpreterStatus(InterpreterPhase.installing);
        await FlutterGemma.installModel(
                modelType: _spec.modelType, fileType: _spec.fileType)
            .fromNetwork(_spec.url)
            .withProgress((p) {
          if (_disposed) return; // don't repaint a disposed service
          _status.value =
              InterpreterStatus(InterpreterPhase.installing, progress: p);
        }).install();
      }
      if (!_disposed) {
        _status.value = const InterpreterStatus(InterpreterPhase.loading);
      }
      final model = await _loadModel();
      if (_disposed) {
        // dispose() ran mid-load: release the model and stay torn down
        // (dispose already reset the status) instead of going ready with
        // a model nobody owns.
        await model.close();
        return;
      }
      _model = model;
      _status.value = const InterpreterStatus(InterpreterPhase.ready);
    } catch (e) {
      if (_disposed) return; // see above — don't repaint a disposed service
      _status.value = InterpreterStatus(InterpreterPhase.error, message: '$e');
    }
  }

  /// Try a roomy context first; some artifacts cap the KV cache, so fall back
  /// to 1280, and from the GPU backend to CPU.
  Future<InferenceModel> _loadModel() async {
    Object? firstError;
    for (final maxTokens in const [2048, 1280]) {
      for (final backend in const [
        PreferredBackend.gpu,
        PreferredBackend.cpu,
      ]) {
        try {
          return await FlutterGemma.getActiveModel(
              maxTokens: maxTokens, preferredBackend: backend);
        } catch (e) {
          // Keep the FIRST failure for the message: it names the real
          // cause (e.g. a corrupt file), not the last-ditch attempt.
          firstError ??= e;
        }
      }
    }
    throw StateError('Model load failed: $firstError');
  }

  /// One set of chat params for interpret() and voiceLine(): variety is the
  /// product, so override the topK-1 defaults.
  Future<InferenceChat> _createChat(InferenceModel model,
      {String? systemInstruction}) {
    return model.createChat(
      temperature: 1.0,
      topK: 64,
      topP: 0.95,
      isThinking: false,
      modelType: _spec.modelType,
      systemInstruction: systemInstruction,
    );
  }

  /// One prompt → raw model text, the shared generation discipline for
  /// interpret() and voiceLine(): fresh chat + inter-token watchdog.
  Future<String> _generate(String prompt, {String? systemInstruction}) async {
    final model = _model;
    if (model == null) throw StateError('Interpreter not ready');
    final chat = await _createChat(model, systemInstruction: systemInstruction);
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    final buffer = StringBuffer();
    // Inter-token watchdog: 60s with no token means the generation hung.
    // Stream.timeout throws TimeoutException into the await-for; it
    // propagates and the caller's UI shows its retry affordance.
    await for (final r in chat
        .generateChatResponseAsync()
        .timeout(const Duration(seconds: 60))) {
      if (r is TextResponse) buffer.write(r.token);
    }
    return buffer.toString();
  }

  @override
  Future<List<OracleInterpretation>> interpret(OracleSeed seed) async {
    return parseInterpretations(await _generate(buildOraclePrompt(seed),
        systemInstruction: oracleSystemInstruction));
  }

  @override
  Future<String> voiceLine(VoiceSeed seed) async {
    return parseVoiceResponse(await _generate(buildVoicePrompt(seed)));
  }

  @override
  Future<String> summarize(List<String> entries) async {
    return parseSummary(await _generate(buildSummaryPrompt(entries)));
  }

  @override
  Future<String> gmChat(GmChatSeed seed) async {
    return parseGmChatResponse(await _generate(buildGmChatPrompt(seed)));
  }

  @override
  Future<String> narrate(NarrateSeed seed) async {
    return parseNarrateResponse(await _generate(buildNarratePrompt(seed)));
  }

  @override
  Future<String> fleshOut(FleshOutSeed seed) async {
    return parseFleshOutResponse(await _generate(buildFleshOutPrompt(seed)));
  }

  @override
  Future<RankResult> rankSuggestions(RankSuggestionsSeed seed) async {
    return parseRankResult(await _generate(buildRankPrompt(seed)));
  }

  @override
  Future<void> dispose() async {
    _disposed = true; // an in-flight warm-up must not resurrect us
    await _model?.close();
    _model = null;
    if (!_unsupported) {
      _status.value = const InterpreterStatus(InterpreterPhase.needsDownload);
    }
  }
}
