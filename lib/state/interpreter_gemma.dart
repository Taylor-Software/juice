/// flutter_gemma-backed interpreter. Never constructed in tests.
///
/// Per-platform model (see spec "Spike results" for why they differ):
/// - web: Gemma3 1B int4 `-web.task` via MediaPipe/WebGPU. NOTE: the
///   pinned URL is a third-party mirror for DEVELOPMENT ONLY — the
///   release merge-gate is swapping it to the user's own HF mirror.
/// - mobile: Qwen3 0.6B int4 `.litertlm` from the official
///   litert-community repo.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../engine/oracle_interpreter.dart';
import '../shared/webgpu_check_stub.dart'
    if (dart.library.js_interop) '../shared/webgpu_check_web.dart';
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

// DEV PIN — swap to the user's own HF mirror before enabling web in a
// release (spec: "Weights provenance").
const _webSpec = _ModelSpec(
  url:
      'https://huggingface.co/darkB/gemma3-1b-it-int4-web-litert/resolve/main/gemma3-1b-it-int4-web.task',
  filename: 'gemma3-1b-it-int4-web.task',
  modelType: ModelType.gemmaIt,
  fileType: ModelFileType.task,
  approxMb: 670,
);

const _mobileSpec = _ModelSpec(
  url:
      'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3_0_6b_mixed_int4.litertlm',
  filename: 'qwen3_0_6b_mixed_int4.litertlm',
  modelType: ModelType.qwen3,
  fileType: ModelFileType.litertlm,
  approxMb: 480,
);

class GemmaInterpreterService implements InterpreterService {
  GemmaInterpreterService() {
    if (kIsWeb && !hasWebGpu) {
      _status.value = const InterpreterStatus(InterpreterPhase.unsupported,
          message: 'This browser has no WebGPU support.');
    }
  }

  final _spec = kIsWeb ? _webSpec : _mobileSpec;
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
  String get downloadLabel => '~${_spec.approxMb} MB';

  bool get _unsupported =>
      _status.value.phase == InterpreterPhase.unsupported;

  @override
  Future<void> refresh() async {
    if (_unsupported || _model != null || _warming != null) return;
    try {
      if (await FlutterGemma.isModelInstalled(_spec.filename)) {
        await warmUp(); // already consented (it's on disk) — just load
      } else {
        _status.value =
            const InterpreterStatus(InterpreterPhase.needsDownload);
      }
    } catch (e) {
      _status.value =
          InterpreterStatus(InterpreterPhase.error, message: '$e');
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
        _status.value =
            const InterpreterStatus(InterpreterPhase.installing);
        await FlutterGemma.installModel(
                modelType: _spec.modelType, fileType: _spec.fileType)
            .fromNetwork(_spec.url)
            .withProgress((p) => _status.value =
                InterpreterStatus(InterpreterPhase.installing, progress: p))
            .install();
      }
      _status.value = const InterpreterStatus(InterpreterPhase.loading);
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
      _status.value =
          InterpreterStatus(InterpreterPhase.error, message: '$e');
    }
  }

  /// Try a roomy context first; some artifacts cap the KV cache (the web
  /// build was only proven at 1280 in the spike).
  Future<InferenceModel> _loadModel() async {
    Object? firstError;
    for (final maxTokens in const [2048, 1280]) {
      for (final backend in [
        PreferredBackend.gpu,
        if (!kIsWeb) PreferredBackend.cpu, // web is GPU-only
      ]) {
        try {
          final model = await FlutterGemma.getActiveModel(
              maxTokens: maxTokens, preferredBackend: backend);
          if (kIsWeb) {
            // flutter_gemma 0.16.5 web: createModel/getActiveModel only
            // constructs a WebInferenceModel — the real WASM + weights
            // load happens in createSession (cached in _initCompleter),
            // which createChat calls via initSession. Probe it here so a
            // too-big maxTokens fails NOW and the fallback loop engages,
            // instead of blowing up the first interpret(). The probed
            // session is the one every later chat reuses, so it must be
            // created with interpret()'s sampling params (web bakes
            // temperature/topK/topP into the engine at session creation).
            await _createChat(model);
          }
          return model;
        } catch (e) {
          // Keep the FIRST failure for the message: it names the real
          // cause (e.g. a corrupt file), not the last-ditch attempt.
          firstError ??= e;
        }
      }
    }
    throw StateError('Model load failed: $firstError');
  }

  /// One set of chat params for both the web load probe and interpret():
  /// on web the first createSession fixes the sampling params for the
  /// lifetime of the (reused) engine session, so they must not diverge.
  Future<InferenceChat> _createChat(InferenceModel model) {
    return model.createChat(
      temperature: 1.0, // variety is the product; defaults (topK 1) kill it
      topK: 64,
      topP: 0.95,
      isThinking: false,
      modelType: _spec.modelType,
      // Web reuses one engine session whose _systemInstructionSent latch
      // never resets, so a session-level instruction would vanish after
      // the first roll; inline it into the prompt there instead (same
      // "[System: ...]" wrapping upstream applies on every platform).
      systemInstruction: kIsWeb ? null : oracleSystemInstruction,
    );
  }

  @override
  Future<List<OracleInterpretation>> interpret(OracleSeed seed) async {
    final model = _model;
    if (model == null) throw StateError('Interpreter not ready');
    final chat = await _createChat(model);
    final prompt = kIsWeb
        ? '[System: $oracleSystemInstruction]\n\n${buildOraclePrompt(seed)}'
        : buildOraclePrompt(seed);
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    final buffer = StringBuffer();
    // Inter-token watchdog: 60s with no token means the generation hung
    // (seen on web, where a MediaPipe error can leave the stream open
    // forever). Stream.timeout throws TimeoutException into the await-for;
    // it propagates and the sheet shows its retry affordance.
    await for (final r in chat
        .generateChatResponseAsync()
        .timeout(const Duration(seconds: 60))) {
      if (r is TextResponse) buffer.write(r.token);
    }
    if (kIsWeb) {
      // Upstream web behavior: one WebModelSession is cached and reused by
      // every chat, and addQueryChunk appends to its _promptParts list,
      // which nothing clears on success — each roll would re-send all
      // previous prompts. stopGeneration() clears the list in a `finally`
      // without closing the engine (cancelProcessing is a no-op once the
      // stream completed). Mobile recreates the native session per chat,
      // so this is web-only.
      await chat.stopGeneration();
    }
    return parseInterpretations(buffer.toString());
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
