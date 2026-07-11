/// flutter_gemma-backed interpreter. Never constructed in tests.
///
/// Mobile/desktop: Gemma 4 E4B int4 `.litertlm` (`ModelType.gemma4`) from the
/// ungated litert-community repo, downloaded on demand (~3.7 GB) — never
/// bundled. The on-device LLM is DISABLED on web (no model): web reports
/// `unsupported` and the UI hides every AI affordance.
///
/// E4B replaced the original E2B pin (2026-07-01): same tokenizer/prompt
/// template (`ModelType.gemma4` unchanged) so no reprompting was needed, just
/// a stronger model at ~1GB more download. Quality was the reason to move —
/// E2B's output was judged too weak for narration/interpretation.
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
      'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
  filename: 'gemma-4-E4B-it.litertlm',
  modelType: ModelType.gemma4,
  fileType: ModelFileType.litertlm,
  approxMb: 3660,
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

  /// Try a roomy context first (E4B handles far more than the retired web
  /// model's 1280; 4096 gives the loosened recall caps + few-shot prompts real
  /// headroom); some artifacts cap the KV cache, so step down, and from the
  /// GPU backend to CPU.
  Future<InferenceModel> _loadModel() async {
    Object? firstError;
    for (final maxTokens in const [4096, 2048, 1280]) {
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

  /// Creative seams (interpret/voice/narrate/…): variety is the product, so
  /// override the topK-1 defaults.
  static const double _kCreativeTemp = 1.0;

  /// Structured/factual seams (rankSuggestions JSON, summarize): a cooler
  /// temperature trades variety for parse reliability and faithfulness.
  static const double _kPreciseTemp = 0.4;

  /// One set of chat params per seam temperament (see the temp constants).
  Future<InferenceChat> _createChat(InferenceModel model,
      {String? systemInstruction, double temperature = _kCreativeTemp}) {
    return model.createChat(
      temperature: temperature,
      topK: 64,
      topP: 0.95,
      isThinking: false,
      modelType: _spec.modelType,
      systemInstruction: systemInstruction,
    );
  }

  /// One prompt → raw model text, the shared generation discipline for
  /// every seam: fresh chat + inter-token watchdog.
  Future<String> _generate(String prompt,
      {String? systemInstruction,
      double temperature = _kCreativeTemp}) async {
    final model = _model;
    if (model == null) throw StateError('Interpreter not ready');
    final chat = await _createChat(model,
        systemInstruction: systemInstruction, temperature: temperature);
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
    return parseSummary(await _generate(buildSummaryPrompt(entries),
        temperature: _kPreciseTemp));
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
    return parseRankResult(await _generate(buildRankPrompt(seed),
        temperature: _kPreciseTemp));
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
