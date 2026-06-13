import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/verdant.dart';
import 'providers.dart' show sessionsProvider;

const _kTransportKeys = {'mount', 'boat', 'airship'};

/// Persisted Verdant journey bookkeeping. Map/hex data lives in mapProvider.
class VerdantJourney {
  const VerdantJourney({
    this.partySize = 1,
    this.independentFollowers = 0,
    this.day = 1,
    this.watch = 1,
    this.step = 1,
    this.safetyLevel = 0,
    this.pace = Pace.normal,
    this.transport,
    this.rushUsedToday = false,
    this.travelingThisRound = false,
    this.roundNote = '',
  });

  final int partySize;
  final int independentFollowers;
  final int day;
  final int watch; // 1..4
  final int step; // 1..6 (Journey Round step)
  final int safetyLevel;
  final Pace pace;
  final String? transport; // 'mount' | 'boat' | 'airship' | null
  final bool rushUsedToday;
  final bool travelingThisRound;
  final String roundNote;

  bool get isNight => watch >= 3; // Evening or Night
  int get er => encounterRisk(partySize); // followers excluded
  int get newRoundSafety => baselineSafety(night: isNight, pace: pace);

  VerdantJourney copyWith({
    int? partySize,
    int? independentFollowers,
    int? day,
    int? watch,
    int? step,
    int? safetyLevel,
    Pace? pace,
    String? transport,
    bool clearTransport = false,
    bool? rushUsedToday,
    bool? travelingThisRound,
    String? roundNote,
  }) =>
      VerdantJourney(
        partySize: partySize ?? this.partySize,
        independentFollowers: independentFollowers ?? this.independentFollowers,
        day: day ?? this.day,
        watch: watch ?? this.watch,
        step: step ?? this.step,
        safetyLevel: safetyLevel ?? this.safetyLevel,
        pace: pace ?? this.pace,
        transport: clearTransport ? null : (transport ?? this.transport),
        rushUsedToday: rushUsedToday ?? this.rushUsedToday,
        travelingThisRound: travelingThisRound ?? this.travelingThisRound,
        roundNote: roundNote ?? this.roundNote,
      );

  Map<String, dynamic> toJson() => {
        'partySize': partySize,
        'independentFollowers': independentFollowers,
        'day': day,
        'watch': watch,
        'step': step,
        'safetyLevel': safetyLevel,
        'pace': pace.name,
        'transport': transport,
        'rushUsedToday': rushUsedToday,
        'travelingThisRound': travelingThisRound,
        'roundNote': roundNote,
      };

  factory VerdantJourney.fromJson(Map<String, dynamic> j) {
    final paceName = j['pace'] as String?;
    final pace = Pace.values
        .firstWhere((p) => p.name == paceName, orElse: () => Pace.normal);
    final t = j['transport'] as String?;
    return VerdantJourney(
      partySize: (j['partySize'] as int?) ?? 1,
      independentFollowers: (j['independentFollowers'] as int?) ?? 0,
      day: (j['day'] as int?) ?? 1,
      watch: ((j['watch'] as int?) ?? 1).clamp(1, 4),
      step: ((j['step'] as int?) ?? 1).clamp(1, 6),
      safetyLevel: (j['safetyLevel'] as int?) ?? 0,
      pace: pace,
      transport: _kTransportKeys.contains(t) ? t : null,
      rushUsedToday: (j['rushUsedToday'] as bool?) ?? false,
      travelingThisRound: (j['travelingThisRound'] as bool?) ?? false,
      roundNote: (j['roundNote'] as String?) ?? '',
    );
  }
}

class VerdantNotifier extends AsyncNotifier<VerdantJourney> {
  static const _baseKey = 'juice.verdant.v1';
  late String _scopedKey;

  @override
  Future<VerdantJourney> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey);
    if (raw == null || raw.isEmpty) return const VerdantJourney();
    return VerdantJourney.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<VerdantJourney> get _ready async => state.valueOrNull ?? await future;

  Future<void> save(VerdantJourney j) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, jsonEncode(j.toJson()));
    state = AsyncData(j);
  }

  Future<void> setPartySize(int n) async =>
      save((await _ready).copyWith(partySize: n.clamp(1, 99)));

  Future<void> setFollowers(int n) async =>
      save((await _ready).copyWith(independentFollowers: n.clamp(0, 99)));

  Future<void> setPace(Pace p) async => save((await _ready).copyWith(pace: p));

  Future<void> setTransport(String? key) async {
    final s = await _ready;
    await save(key == null
        ? s.copyWith(clearTransport: true)
        : s.copyWith(transport: key));
  }

  Future<void> setWatch(int w) async =>
      save((await _ready).copyWith(watch: w.clamp(1, 4)));

  Future<void> setTraveling(bool v) async =>
      save((await _ready).copyWith(travelingThisRound: v));

  /// A task outcome: Safer (+2) / Riskier (−1) / Deadly (−2).
  Future<void> applyDelta(int delta) async {
    final s = await _ready;
    await save(s.copyWith(safetyLevel: s.safetyLevel + delta));
  }

  Future<void> setSafety(int v) async =>
      save((await _ready).copyWith(safetyLevel: v));

  Future<void> advanceStep() async {
    final s = await _ready;
    await save(s.copyWith(step: s.step >= 6 ? 6 : s.step + 1));
  }

  /// Start a fresh round: step 1, Safety reset to the night±pace baseline.
  Future<void> newRound() async {
    final s = await _ready;
    await save(
        s.copyWith(step: 1, safetyLevel: s.newRoundSafety, roundNote: ''));
  }

  /// Advance the watch; past Night rolls into the next day and resets Rush.
  Future<void> nextWatch() async {
    final s = await _ready;
    if (s.watch >= 4) {
      await save(s.copyWith(day: s.day + 1, watch: 1, rushUsedToday: false));
    } else {
      await save(s.copyWith(watch: s.watch + 1));
    }
  }

  /// Mounts only: once per day. Caller checks transport == 'mount'.
  Future<void> useRush() async {
    final s = await _ready;
    if (s.rushUsedToday) return;
    await save(s.copyWith(rushUsedToday: true));
  }

  Future<void> reset() async {
    await _ready;
    await save(const VerdantJourney());
  }
}

final verdantProvider =
    AsyncNotifierProvider<VerdantNotifier, VerdantJourney>(VerdantNotifier.new);
