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

  final List<String> queuedSummary = [];
  Object? summaryError;
  List<String>? lastSummaryEntries;
  int summaryCalls = 0;

  final List<String> queuedGmChat = [];
  GmChatSeed? lastGmChatSeed;
  int gmChatCalls = 0;
  Object? gmChatError;

  final List<String> queuedNarrate = [];
  NarrateSeed? lastNarrateSeed;
  int narrateCalls = 0;
  Object? narrateError;

  final List<String> queuedFleshOut = [];
  FleshOutSeed? lastFleshOutSeed;
  int fleshOutCalls = 0;
  Object? fleshOutError;

  final List<RankResult> queuedRank = [];
  RankSuggestionsSeed? lastRankSeed;
  int rankCalls = 0;
  Object? rankError;

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
  Future<String> summarize(List<String> entries) async {
    lastSummaryEntries = entries;
    summaryCalls++;
    if (summaryError != null) throw summaryError!;
    if (queuedSummary.isEmpty) return 'A canned recap.';
    return queuedSummary.removeAt(0);
  }

  @override
  Future<String> gmChat(GmChatSeed seed) async {
    lastGmChatSeed = seed;
    gmChatCalls++;
    if (gmChatError != null) throw gmChatError!;
    if (queuedGmChat.isEmpty) return 'A canned GM reply.';
    return queuedGmChat.removeAt(0);
  }

  @override
  Future<String> narrate(NarrateSeed seed) async {
    lastNarrateSeed = seed;
    narrateCalls++;
    if (narrateError != null) throw narrateError!;
    if (queuedNarrate.isEmpty) return 'A canned narration.';
    return queuedNarrate.removeAt(0);
  }

  @override
  Future<String> fleshOut(FleshOutSeed seed) async {
    lastFleshOutSeed = seed;
    fleshOutCalls++;
    if (fleshOutError != null) throw fleshOutError!;
    if (queuedFleshOut.isEmpty) return 'Fleshed-out detail.';
    return queuedFleshOut.removeAt(0);
  }

  @override
  Future<RankResult> rankSuggestions(RankSuggestionsSeed seed) async {
    lastRankSeed = seed;
    rankCalls++;
    if (rankError != null) throw rankError!;
    if (queuedRank.isEmpty) return const RankResult();
    return queuedRank.removeAt(0);
  }

  @override
  Future<void> dispose() async => disposeCalls++;
}
