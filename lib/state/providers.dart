import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/models.dart';
import '../engine/oracle.dart';
import '../engine/oracle_data.dart';
import 'campaign_io.dart';

/// Loads the data asset and builds the engine once.
final oracleProvider = FutureProvider<Oracle>((ref) async {
  final data = await OracleData.load();
  return Oracle(data);
});

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

/// Generic persisted list backed by a JSON string in SharedPreferences.
abstract class _PersistedList<T> extends AsyncNotifier<List<T>> {
  String get prefsKey;
  T fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJsonMap(T item);

  late String _scopedKey;

  @override
  Future<List<T>> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$prefsKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey);
    if (raw == null || raw.isEmpty) return <T>[];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(fromJson).toList();
  }

  Future<void> _persist(List<T> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _scopedKey,
      jsonEncode(items.map(toJsonMap).toList()),
    );
    state = AsyncData(items);
  }

  List<T> get _current => state.valueOrNull ?? <T>[];
}

// -- Log ------------------------------------------------------------------
class LogNotifier extends _PersistedList<LogEntry> {
  @override
  String get prefsKey => 'juice.log.v1';
  @override
  LogEntry fromJson(Map<String, dynamic> json) => LogEntry.fromJson(json);
  @override
  Map<String, dynamic> toJsonMap(LogEntry item) => item.toJson();

  Future<void> add(String title, String body) async {
    final entry = LogEntry(
      id: _newId(),
      timestamp: DateTime.now(),
      title: title,
      body: body,
    );
    await _persist([entry, ..._current]);
  }

  Future<void> replace(LogEntry entry) async {
    await _persist([
      for (final e in _current) if (e.id == entry.id) entry else e,
    ]);
  }

  Future<void> remove(String id) async {
    await _persist(_current.where((e) => e.id != id).toList());
  }

  Future<void> clear() async => _persist(<LogEntry>[]);
}

final logProvider =
    AsyncNotifierProvider<LogNotifier, List<LogEntry>>(LogNotifier.new);

// -- Threads --------------------------------------------------------------
class ThreadNotifier extends _PersistedList<Thread> {
  @override
  String get prefsKey => 'juice.threads.v1';
  @override
  Thread fromJson(Map<String, dynamic> json) => Thread.fromJson(json);
  @override
  Map<String, dynamic> toJsonMap(Thread item) => item.toJson();

  Future<void> add(String title) async {
    await _persist([
      Thread(id: _newId(), title: title),
      ..._current,
    ]);
  }

  Future<void> replace(Thread thread) async {
    await _persist([
      for (final t in _current) if (t.id == thread.id) thread else t,
    ]);
  }

  Future<void> toggleOpen(String id) async {
    await _persist([
      for (final t in _current)
        if (t.id == id) t.copyWith(open: !t.open) else t,
    ]);
  }

  Future<void> remove(String id) async {
    await _persist(_current.where((t) => t.id != id).toList());
  }
}

final threadsProvider =
    AsyncNotifierProvider<ThreadNotifier, List<Thread>>(ThreadNotifier.new);

// -- Characters -----------------------------------------------------------
class CharacterNotifier extends _PersistedList<Character> {
  @override
  String get prefsKey => 'juice.characters.v1';
  @override
  Character fromJson(Map<String, dynamic> json) => Character.fromJson(json);
  @override
  Map<String, dynamic> toJsonMap(Character item) => item.toJson();

  Future<void> add(String name) async {
    await _persist([
      Character(id: _newId(), name: name),
      ..._current,
    ]);
  }

  Future<void> replace(Character character) async {
    await _persist([
      for (final c in _current) if (c.id == character.id) character else c,
    ]);
  }

  Future<void> remove(String id) async {
    await _persist(_current.where((c) => c.id != id).toList());
  }
}

final charactersProvider =
    AsyncNotifierProvider<CharacterNotifier, List<Character>>(
        CharacterNotifier.new);

// -- Crawl state (wilderness + dialog marker) -------------------------------
class CrawlNotifier extends AsyncNotifier<CrawlState> {
  static const _baseKey = 'juice.crawl.v1';

  late String _scopedKey;

  @override
  Future<CrawlState> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey);
    if (raw == null || raw.isEmpty) return const CrawlState();
    return CrawlState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(CrawlState s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, jsonEncode(s.toJson()));
    state = AsyncData(s);
  }

  Future<void> reset() => save(const CrawlState());
}

final crawlProvider =
    AsyncNotifierProvider<CrawlNotifier, CrawlState>(CrawlNotifier.new);

// -- Sessions ---------------------------------------------------------------
/// Base keys holding per-session data; scoped as '<base>.<sessionId>'.
const sessionScopedKeys = [
  'juice.log.v1',
  'juice.threads.v1',
  'juice.characters.v1',
  'juice.crawl.v1',
];

class SessionsNotifier extends AsyncNotifier<SessionsState> {
  static const _key = 'juice.sessions.v1';

  @override
  Future<SessionsState> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      return SessionsState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    // First run with sessions: adopt legacy single-campaign data, if any.
    const def = SessionMeta(id: 'default', name: 'Campaign 1');
    for (final base in sessionScopedKeys) {
      final legacy = prefs.getString(base);
      if (legacy != null) {
        await prefs.setString('$base.${def.id}', legacy);
        await prefs.remove(base);
      }
    }
    const initial = SessionsState(active: 'default', sessions: [def]);
    await prefs.setString(_key, jsonEncode(initial.toJson()));
    return initial;
  }

  Future<void> _save(SessionsState s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(s.toJson()));
    state = AsyncData(s);
  }

  Future<void> switchTo(String id) async {
    final s = state.valueOrNull;
    if (s == null || s.active == id) return;
    await _save(SessionsState(active: id, sessions: s.sessions));
  }

  Future<void> create(String name) async {
    final s = state.valueOrNull;
    if (s == null) return;
    final meta = SessionMeta(id: _newId(), name: name);
    await _save(
        SessionsState(active: meta.id, sessions: [...s.sessions, meta]));
  }

  Future<void> remove(String id) async {
    final s = state.valueOrNull;
    if (s == null || s.sessions.length <= 1) return; // keep at least one
    final prefs = await SharedPreferences.getInstance();
    for (final base in sessionScopedKeys) {
      await prefs.remove('$base.$id');
    }
    final remaining = s.sessions.where((m) => m.id != id).toList();
    final active = s.active == id ? remaining.first.id : s.active;
    await _save(SessionsState(active: active, sessions: remaining));
  }

  /// Serialize the active session to the campaign file format.
  Future<String> exportActive() async {
    final s = state.valueOrNull ?? await future;
    final prefs = await SharedPreferences.getInstance();
    final rawByKey = <String, String>{};
    for (final base in sessionScopedKeys) {
      final raw = prefs.getString('$base.${s.active}');
      if (raw != null) rawByKey[base] = raw;
    }
    return encodeCampaign(
      name: s.activeMeta.name,
      savedAt: DateTime.now(),
      rawByKey: rawByKey,
    );
  }

  /// Import a campaign file as a NEW session and switch to it.
  /// Throws [FormatException] on invalid files.
  Future<void> importCampaign(String fileContent) async {
    final parsed = parseCampaign(fileContent);
    final s = state.valueOrNull ?? await future;
    final meta = SessionMeta(id: _newId(), name: parsed.name);
    final prefs = await SharedPreferences.getInstance();
    for (final e in parsed.rawByKey.entries) {
      await prefs.setString('${e.key}.${meta.id}', e.value);
    }
    await _save(
        SessionsState(active: meta.id, sessions: [...s.sessions, meta]));
  }
}

final sessionsProvider = AsyncNotifierProvider<SessionsNotifier, SessionsState>(
    SessionsNotifier.new);

// -- Enabled rulesets (global, not session-scoped) ---------------------------
class RulesetsNotifier extends AsyncNotifier<Set<String>> {
  static const _key = 'juice.rulesets.v1';

  @override
  Future<Set<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String>{};
    return (jsonDecode(raw) as List).cast<String>().toSet();
  }

  Future<void> toggle(String id) async {
    final current = {...(state.valueOrNull ?? await future)};
    if (!current.remove(id)) current.add(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(current.toList()));
    state = AsyncData(current);
  }
}

final rulesetsProvider =
    AsyncNotifierProvider<RulesetsNotifier, Set<String>>(RulesetsNotifier.new);

/// Lazy per-ruleset asset, loaded only when its toggle is on.
final rulesetDataProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final raw = await rootBundle.loadString('assets/ruleset_$id.json');
  return jsonDecode(raw) as Map<String, dynamic>;
});
