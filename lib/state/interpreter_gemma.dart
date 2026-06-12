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

  @override
  ValueListenable<InterpreterStatus> get status => _status;

  @override
  String get downloadLabel => '~${_spec.approxMb} MB';

  bool get _unsupported =>
      _status.value.phase == InterpreterPhase.unsupported;

  @override
  Future<void> refresh() async {
    if (_unsupported || _model != null) return;
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
  Future<void> warmUp() async {
    if (_unsupported || _model != null) return;
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
      _model = await _loadModel();
      _status.value = const InterpreterStatus(InterpreterPhase.ready);
    } catch (e) {
      _status.value =
          InterpreterStatus(InterpreterPhase.error, message: '$e');
    }
  }

  /// Try a roomy context first; some artifacts cap the KV cache (the web
  /// build was only proven at 1280 in the spike).
  Future<InferenceModel> _loadModel() async {
    Object? lastError;
    for (final maxTokens in const [2048, 1280]) {
      for (final backend in [
        PreferredBackend.gpu,
        if (!kIsWeb) PreferredBackend.cpu, // web is GPU-only
      ]) {
        try {
          return await FlutterGemma.getActiveModel(
              maxTokens: maxTokens, preferredBackend: backend);
        } catch (e) {
          lastError = e;
        }
      }
    }
    throw StateError('Model load failed: $lastError');
  }

  @override
  Future<List<OracleInterpretation>> interpret(OracleSeed seed) async {
    final model = _model;
    if (model == null) throw StateError('Interpreter not ready');
    final chat = await model.createChat(
      temperature: 1.0, // variety is the product; defaults (topK 1) kill it
      topK: 64,
      topP: 0.95,
      isThinking: false,
      modelType: _spec.modelType,
      systemInstruction: oracleSystemInstruction,
    );
    await chat.addQueryChunk(
        Message.text(text: buildOraclePrompt(seed), isUser: true));
    final buffer = StringBuffer();
    await for (final r in chat.generateChatResponseAsync()) {
      if (r is TextResponse) buffer.write(r.token);
    }
    return parseInterpretations(buffer.toString());
  }

  @override
  Future<void> dispose() async {
    await _model?.close();
    _model = null;
    if (!_unsupported) {
      _status.value = const InterpreterStatus(InterpreterPhase.needsDownload);
    }
  }
}
