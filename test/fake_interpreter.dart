import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';
import 'package:juice_oracle/state/interpreter.dart';

/// Scriptable fake. Tests drive [status] directly and queue results.
class FakeInterpreterService implements InterpreterService {
  FakeInterpreterService({InterpreterStatus? initial})
      : statusNotifier = ValueNotifier(
            initial ?? const InterpreterStatus(InterpreterPhase.needsDownload));

  final ValueNotifier<InterpreterStatus> statusNotifier;
  final List<List<OracleInterpretation>> queuedResults = [];
  Object? interpretError;
  final List<String> queuedVoice = [];
  Object? voiceError;
  VoiceSeed? lastVoiceSeed;
  int voiceCalls = 0;

  /// When set, interpret() blocks on it after counting the call — lets a
  /// test hold a generation in flight (e.g. to probe reentrancy guards).
  Completer<void>? interpretGate;
  OracleSeed? lastSeed;
  int refreshCalls = 0;
  int warmUpCalls = 0;
  int interpretCalls = 0;
  int disposeCalls = 0;

  @override
  ValueListenable<InterpreterStatus> get status => statusNotifier;

  @override
  String get downloadLabel => '~123 MB';

  @override
  Future<void> refresh() async => refreshCalls++;

  @override
  Future<void> warmUp() async {
    warmUpCalls++;
    statusNotifier.value = const InterpreterStatus(InterpreterPhase.ready);
  }

  @override
  Future<List<OracleInterpretation>> interpret(OracleSeed seed) async {
    lastSeed = seed;
    interpretCalls++;
    if (interpretGate case final gate?) await gate.future;
    if (interpretError != null) throw interpretError!;
    if (queuedResults.isEmpty) {
      return const [OracleInterpretation(lens: 'literal', reading: 'fallback')];
    }
    return queuedResults.removeAt(0);
  }

  @override
  Future<String> voiceLine(VoiceSeed seed) async {
    lastVoiceSeed = seed;
    voiceCalls++;
    if (voiceError != null) throw voiceError!;
    if (queuedVoice.isEmpty) return 'A canned voiced line.';
    return queuedVoice.removeAt(0);
  }

  @override
  Future<void> dispose() async => disposeCalls++;
}
