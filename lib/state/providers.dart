import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/models.dart';
import '../engine/oracle.dart';
import '../engine/oracle_data.dart';

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

  @override
  Future<List<T>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return <T>[];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(fromJson).toList();
  }

  Future<void> _persist(List<T> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefsKey,
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
