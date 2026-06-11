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

  /// Await the loaded list: mutating before build() completes must not
  /// throw on [_scopedKey] or clobber previously persisted data.
  Future<List<T>> get _ready async => state.valueOrNull ?? await future;
}

// -- Journal ----------------------------------------------------------------
class JournalNotifier extends _PersistedList<JournalEntry> {
  @override
  String get prefsKey => 'juice.journal.v2';
  @override
  JournalEntry fromJson(Map<String, dynamic> json) =>
      JournalEntry.fromJson(json);
  @override
  Map<String, dynamic> toJsonMap(JournalEntry item) => item.toJson();

  static const _legacyKey = 'juice.log.v1';

  @override
  Future<List<JournalEntry>> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    final prefs = await SharedPreferences.getInstance();
    final scoped = '$prefsKey.${sessions.active}';
    // One-shot, non-destructive migration from the legacy log key. Old
    // entries lack 'kind' and parse as JournalKind.result.
    if (prefs.getString(scoped) == null) {
      final legacy = prefs.getString('$_legacyKey.${sessions.active}');
      if (legacy != null) await prefs.setString(scoped, legacy);
    }
    return super.build();
  }

  Future<void> add(String title, String body) async {
    await _persist([
      JournalEntry(
          id: _newId(), timestamp: DateTime.now(), title: title, body: body),
      ...await _ready,
    ]);
  }

  Future<void> addText(String body) async {
    await _persist([
      JournalEntry(
          id: _newId(),
          timestamp: DateTime.now(),
          title: '',
          body: body,
          kind: JournalKind.text),
      ...await _ready,
    ]);
  }

  Future<void> addScene(String title, {int? chaosFactor}) async {
    await _persist([
      JournalEntry(
          id: _newId(),
          timestamp: DateTime.now(),
          title: title,
          body: '',
          kind: JournalKind.scene,
          chaosFactor: chaosFactor),
      ...await _ready,
    ]);
  }

  Future<void> replace(JournalEntry entry) async {
    await _persist([
      for (final e in await _ready) if (e.id == entry.id) entry else e,
    ]);
  }

  Future<void> remove(String id) async {
    await _persist((await _ready).where((e) => e.id != id).toList());
  }

  Future<void> clear() async {
    await _ready;
    await _persist(<JournalEntry>[]);
  }
}

final journalProvider =
    AsyncNotifierProvider<JournalNotifier, List<JournalEntry>>(
        JournalNotifier.new);

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
      ...await _ready,
    ]);
  }

  Future<void> replace(Thread thread) async {
    await _persist([
      for (final t in await _ready) if (t.id == thread.id) thread else t,
    ]);
  }

  Future<void> toggleOpen(String id) async {
    await _persist([
      for (final t in await _ready)
        if (t.id == id) t.copyWith(open: !t.open) else t,
    ]);
  }

  Future<void> remove(String id) async {
    await _persist((await _ready).where((t) => t.id != id).toList());
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
      ...await _ready,
    ]);
  }

  Future<void> replace(Character character) async {
    await _persist([
      for (final c in await _ready) if (c.id == character.id) character else c,
    ]);
  }

  Future<void> remove(String id) async {
    await _persist((await _ready).where((c) => c.id != id).toList());
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

// -- Encounter tracker (initiative order, turns, rounds) ---------------------
class EncounterNotifier extends AsyncNotifier<EncounterState> {
  static const _baseKey = 'juice.encounter.v1';

  late String _scopedKey;

  @override
  Future<EncounterState> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey);
    if (raw == null || raw.isEmpty) return const EncounterState();
    return EncounterState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(EncounterState s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, jsonEncode(s.toJson()));
    state = AsyncData(s);
  }

  /// Awaited state: mutating before build() completes must not throw on
  /// [_scopedKey] or clobber previously persisted data.
  Future<EncounterState> get _ready async => state.valueOrNull ?? await future;

  /// Insert keeping initiative order (descending); on ties the new combatant
  /// goes AFTER existing equals. turnIndex adjusts so the current turn's
  /// combatant stays current.
  Future<void> addCombatant(Combatant c) async {
    final s = await _ready;
    final list = [...s.combatants];
    var insertIndex = list.indexWhere((e) => e.initiative < c.initiative);
    if (insertIndex == -1) insertIndex = list.length;
    list.insert(insertIndex, c);
    final turnIndex = (s.combatants.isNotEmpty && insertIndex <= s.turnIndex)
        ? s.turnIndex + 1
        : s.turnIndex;
    await save(s.copyWith(combatants: list, turnIndex: turnIndex));
  }

  /// Manual order override from drag: move [oldIndex] -> [newIndex]
  /// (raw ReorderableListView indices); turnIndex follows the combatant
  /// it pointed at.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final s = await _ready;
    if (s.combatants.isEmpty) return;
    if (newIndex > oldIndex) newIndex--;
    final pointedId = s.combatants[s.turnIndex].id;
    final list = [...s.combatants];
    list.insert(newIndex, list.removeAt(oldIndex));
    final turnIndex = list.indexWhere((c) => c.id == pointedId);
    await save(s.copyWith(combatants: list, turnIndex: turnIndex));
  }

  /// Replace the combatant with the same id.
  Future<void> updateCombatant(Combatant c) async {
    final s = await _ready;
    await save(s.copyWith(combatants: [
      for (final e in s.combatants) if (e.id == c.id) c else e,
    ]));
  }

  /// Remove by id; turnIndex follows the pointed-at combatant, or clamps
  /// into range when the pointed combatant itself is removed.
  Future<void> removeCombatant(String id) async {
    final s = await _ready;
    final idx = s.combatants.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final list = [...s.combatants]..removeAt(idx);
    int turnIndex;
    if (idx == s.turnIndex) {
      turnIndex = list.isEmpty ? 0 : s.turnIndex.clamp(0, list.length - 1);
    } else {
      final pointedId = s.combatants[s.turnIndex].id;
      final followed = list.indexWhere((c) => c.id == pointedId);
      turnIndex = followed == -1 ? 0 : followed;
    }
    await save(s.copyWith(combatants: list, turnIndex: turnIndex));
  }

  /// Advance to the next non-defeated combatant. Wrapping past the end
  /// increments round. If all combatants are defeated (or list empty): no-op.
  Future<void> nextTurn() async {
    final s = await _ready;
    final n = s.combatants.length;
    if (n == 0 || s.combatants.every((c) => c.defeated)) return;
    var i = s.turnIndex;
    var round = s.round;
    do {
      i++;
      if (i >= n) {
        i = 0;
        round++;
      }
    } while (s.combatants[i].defeated);
    await save(s.copyWith(turnIndex: i, round: round));
  }

  Future<void> reset() async {
    await _ready;
    await save(const EncounterState());
  }
}

final encounterProvider =
    AsyncNotifierProvider<EncounterNotifier, EncounterState>(
        EncounterNotifier.new);

// -- Sessions ---------------------------------------------------------------
/// Base keys holding per-session data; scoped as '<base>.<sessionId>'.
const sessionScopedKeys = [
  'juice.journal.v2',
  'juice.log.v1', // legacy; kept so v1 campaign imports round-trip
  'juice.threads.v1',
  'juice.characters.v1',
  'juice.crawl.v1',
  'juice.encounter.v1',
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
      // Exports carry journal v2 only; log v1 is import-only.
      if (base == 'juice.log.v1') continue;
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

  static const _bases = {'classic', 'starforged'};
  static const _expansionOf = {
    'delve': 'classic',
    'sundered_isles': 'starforged'
  };

  /// Apply the family rules: expansions require their base; the two base
  /// games are mutually exclusive (enabling one drops the other family).
  Future<void> setRuleset(String id, bool on) async {
    final current = {...(state.valueOrNull ?? await future)};
    if (on) {
      final base = _expansionOf[id] ?? id;
      if (_bases.contains(base)) {
        final otherBase = base == 'classic' ? 'starforged' : 'classic';
        current.remove(otherBase);
        current.removeWhere((r) => _expansionOf[r] == otherBase);
      }
      current.add(base);
      if (_expansionOf.containsKey(id)) current.add(id);
    } else {
      current.remove(id);
      current.removeWhere((r) => _expansionOf[r] == id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(current.toList()));
    state = AsyncData(current);
  }
}

final rulesetsProvider =
    AsyncNotifierProvider<RulesetsNotifier, Set<String>>(RulesetsNotifier.new);

// -- Tool MRU (global, not session-scoped) ----------------------------------
class ToolMruNotifier extends AsyncNotifier<List<String>> {
  static const _key = 'juice.tools.mru.v1';
  static const _cap = 6;

  @override
  Future<List<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return const []; // corrupt persisted MRU: start fresh
    }
  }

  Future<void> record(String toolId) async {
    // Await the loaded list: recording before build() completes must not
    // clobber a previously persisted MRU.
    final current = [...(state.valueOrNull ?? await future)];
    current.remove(toolId);
    current.insert(0, toolId);
    final capped = current.take(_cap).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(capped));
    state = AsyncData(capped);
  }
}

final toolMruProvider =
    AsyncNotifierProvider<ToolMruNotifier, List<String>>(ToolMruNotifier.new);

/// Lazy per-ruleset asset, loaded only when its toggle is on.
final rulesetDataProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final raw = await rootBundle.loadString('assets/ruleset_$id.json');
  return jsonDecode(raw) as Map<String, dynamic>;
});
