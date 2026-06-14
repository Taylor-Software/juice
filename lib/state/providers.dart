import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/dice.dart';
import '../engine/emulator_data.dart';
import '../engine/verdant_data.dart';
import '../engine/help_data.dart';
import '../engine/map_builder.dart';
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

  Future<void> addResult(
    String title,
    String body, {
    String? sourceTool,
    Map<String, dynamic>? payload,
  }) async {
    await _persist([
      JournalEntry(
          id: _newId(),
          timestamp: DateTime.now(),
          title: title,
          body: body,
          sourceTool: sourceTool,
          payload: payload),
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
      for (final e in await _ready)
        if (e.id == entry.id) entry else e,
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

  Future<String> addReturningId(String title) async {
    final id = _newId();
    await _persist([Thread(id: id, title: title), ...await _ready]);
    return id;
  }

  Future<void> replace(Thread thread) async {
    await _persist([
      for (final t in await _ready)
        if (t.id == thread.id) thread else t,
    ]);
  }

  Future<void> toggleOpen(String id) async {
    await _persist([
      for (final t in await _ready)
        if (t.id == id) t.copyWith(open: !t.open) else t,
    ]);
  }

  Future<void> togglePinned(String id) async {
    await _persist([
      for (final t in await _ready)
        if (t.id == id) t.copyWith(pinned: !t.pinned) else t,
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

  Future<String> addReturningId(String name) async {
    final id = _newId();
    await _persist([Character(id: id, name: name), ...await _ready]);
    return id;
  }

  Future<void> replace(Character character) async {
    await _persist([
      for (final c in await _ready)
        if (c.id == character.id) character else c,
    ]);
  }

  Future<void> toggleStarred(String id) async {
    await _persist([
      for (final ch in await _ready)
        if (ch.id == id) ch.copyWith(starred: !ch.starred) else ch,
    ]);
  }

  Future<void> remove(String id) async {
    await _persist((await _ready).where((c) => c.id != id).toList());
  }
}

final charactersProvider =
    AsyncNotifierProvider<CharacterNotifier, List<Character>>(
        CharacterNotifier.new);

// -- Rumors -----------------------------------------------------------------
class RumorNotifier extends _PersistedList<Rumor> {
  @override
  String get prefsKey => 'juice.rumors.v1';
  @override
  Rumor fromJson(Map<String, dynamic> json) => Rumor.fromJson(json);
  @override
  Map<String, dynamic> toJsonMap(Rumor item) => item.toJson();

  Future<void> add(String text) async {
    await _persist([Rumor(id: _newId(), text: text), ...await _ready]);
  }

  Future<void> replace(Rumor rumor) async {
    await _persist([
      for (final r in await _ready)
        if (r.id == rumor.id) rumor else r,
    ]);
  }

  Future<void> toggleResolved(String id) async {
    await _persist([
      for (final r in await _ready)
        if (r.id == id) r.copyWith(resolved: !r.resolved) else r,
    ]);
  }

  Future<void> remove(String id) async {
    await _persist((await _ready).where((r) => r.id != id).toList());
  }
}

final rumorsProvider =
    AsyncNotifierProvider<RumorNotifier, List<Rumor>>(RumorNotifier.new);

// -- Tracks -----------------------------------------------------------------
class TrackNotifier extends _PersistedList<Track> {
  @override
  String get prefsKey => 'juice.tracks.v1';
  @override
  Track fromJson(Map<String, dynamic> json) => Track.fromJson(json);
  @override
  Map<String, dynamic> toJsonMap(Track item) => item.toJson();

  Future<void> add(String name, {int max = 10}) async {
    await _persist(
        [Track(id: _newId(), name: name, max: max), ...await _ready]);
  }

  Future<void> adjust(String id, int delta) async {
    await _persist([
      for (final t in await _ready)
        if (t.id == id)
          t.copyWith(filled: (t.filled + delta).clamp(0, t.max))
        else
          t,
    ]);
  }

  Future<void> rename(String id, String name) async {
    await _persist([
      for (final t in await _ready)
        if (t.id == id) t.copyWith(name: name) else t,
    ]);
  }

  Future<void> remove(String id) async {
    await _persist((await _ready).where((t) => t.id != id).toList());
  }
}

final tracksProvider =
    AsyncNotifierProvider<TrackNotifier, List<Track>>(TrackNotifier.new);

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

  Future<void> setChaos(int n) async {
    final cur = state.valueOrNull ?? await future;
    await save(cur.copyWith(chaosFactor: n.clamp(1, 9)));
  }
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
      for (final e in s.combatants)
        if (e.id == c.id) c else e,
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

// -- Map (dungeon graph + revealed hex field) --------------------------------
class MapNotifier extends AsyncNotifier<MapState> {
  static const _baseKey = 'juice.map.v1';

  late String _scopedKey;

  @override
  Future<MapState> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey);
    if (raw == null || raw.isEmpty) return const MapState();
    return MapState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(MapState s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, jsonEncode(s.toJson()));
    state = AsyncData(s);
  }

  /// Awaited state: mutating before build() completes must not throw on
  /// [_scopedKey] or clobber previously persisted data.
  Future<MapState> get _ready async => state.valueOrNull ?? await future;

  /// Place a new room next to the current one (engine picks the cell),
  /// connect it with a corridor, and make it current.
  Future<DungeonRoom> addRoom(
      {required String title,
      required String detail,
      required Dice dice}) async {
    final s = await _ready;
    final pos = nextRoomPosition(s.rooms, s.currentRoomId, dice);
    final room = DungeonRoom(
        id: _newId(), x: pos.x, y: pos.y, title: title, detail: detail);
    await save(s.copyWith(
      rooms: [...s.rooms, room],
      corridors: pos.attachTo == null
          ? s.corridors
          : [
              ...s.corridors,
              [pos.attachTo!, room.id],
            ],
      currentRoomId: room.id,
    ));
    return room;
  }

  /// Make [id] the current room; no-op for unknown ids.
  Future<void> selectRoom(String id) async {
    final s = await _ready;
    if (!s.rooms.any((r) => r.id == id)) return;
    await save(s.copyWith(currentRoomId: id));
  }

  /// Append a linger result line to a room's detail.
  Future<void> appendRoomDetail(String id, String extra) async {
    final s = await _ready;
    await save(s.copyWith(rooms: [
      for (final r in s.rooms)
        if (r.id == id) r.copyWith(detail: '${r.detail}\n$extra') else r,
    ]));
  }

  /// Reveal the next hex from travel (engine picks the cell) and move
  /// current onto it. Re-entering a revealed cell keeps its environment
  /// but updates its lost flag.
  Future<HexCell> revealHex(
      {required int envRow, required bool lost, required Dice dice}) async {
    final s = await _ready;
    final pos =
        nextHexPosition(s.hexes, s.currentHexCol, s.currentHexRow, dice);
    if (pos.alreadyRevealed) {
      final hexes = [
        for (final h in s.hexes)
          if (h.col == pos.col && h.row == pos.row)
            h.copyWith(lost: lost)
          else
            h,
      ];
      await save(s.copyWith(
          hexes: hexes, currentHexCol: pos.col, currentHexRow: pos.row));
      return hexes.firstWhere((h) => h.col == pos.col && h.row == pos.row);
    }
    final cell =
        HexCell(col: pos.col, row: pos.row, envRow: envRow, lost: lost);
    await save(s.copyWith(
      hexes: [...s.hexes, cell],
      currentHexCol: pos.col,
      currentHexRow: pos.row,
    ));
    return cell;
  }

  /// Manual reveal at explicit coords (does not move current); no-op if the
  /// cell is already revealed.
  Future<void> revealHexAt(int col, int row, int envRow) async {
    final s = await _ready;
    if (s.hexes.any((h) => h.col == col && h.row == row)) return;
    await save(s.copyWith(
        hexes: [...s.hexes, HexCell(col: col, row: row, envRow: envRow)]));
  }

  /// Set the Verdant terrain key on an existing hex; no-op for unknown cells.
  Future<void> setHexTerrain(int col, int row, String terrainKey) async {
    final s = await _ready;
    if (!s.hexes.any((h) => h.col == col && h.row == row)) return;
    await save(s.copyWith(hexes: [
      for (final h in s.hexes)
        if (h.col == col && h.row == row)
          h.copyWith(terrain: terrainKey)
        else
          h,
    ]));
  }

  /// Add a Point of Interest (1..12) to an existing hex; ignores duplicates.
  Future<void> addHexPoi(int col, int row, int poiN) async {
    final s = await _ready;
    if (!s.hexes.any((h) => h.col == col && h.row == row)) return;
    await save(s.copyWith(hexes: [
      for (final h in s.hexes)
        if (h.col == col && h.row == row)
          h.copyWith(pois: h.pois.contains(poiN) ? h.pois : [...h.pois, poiN])
        else
          h,
    ]));
  }

  /// Clear the dungeon graph, keeping the hex field.
  Future<void> resetDungeon() async {
    final s = await _ready;
    await save(s.copyWith(
        rooms: const [], corridors: const [], clearCurrentRoomId: true));
  }

  /// Clear the hex field, keeping the dungeon graph.
  Future<void> resetHexes() async {
    final s = await _ready;
    await save(s.copyWith(hexes: const [], clearCurrentHex: true));
  }
}

final mapProvider =
    AsyncNotifierProvider<MapNotifier, MapState>(MapNotifier.new);

// -- Campaign settings (genre/tone for the interpreter) ----------------------
class SettingsNotifier extends AsyncNotifier<CampaignSettings> {
  static const _baseKey = 'juice.settings.v1';

  late String _scopedKey;

  @override
  Future<CampaignSettings> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey);
    if (raw == null || raw.isEmpty) return const CampaignSettings();
    return CampaignSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(CampaignSettings s) async {
    // Await build() so an early save cannot throw on _scopedKey.
    state.valueOrNull ?? await future;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, jsonEncode(s.toJson()));
    state = AsyncData(s);
  }

  Future<void> setDefaultOracle(String oracle) async {
    final cur = state.valueOrNull ?? await future;
    await save(cur.copyWith(defaultOracle: oracle));
  }

  Future<void> setHeaderCollapsed(bool collapsed) async {
    final cur = state.valueOrNull ?? await future;
    await save(cur.copyWith(headerCollapsed: collapsed));
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, CampaignSettings>(
        SettingsNotifier.new);

// -- Sessions ---------------------------------------------------------------
/// Base keys holding per-session data; scoped as '<base>.<sessionId>'.
const sessionScopedKeys = [
  'juice.journal.v2',
  'juice.log.v1', // legacy; kept so v1 campaign imports round-trip
  'juice.threads.v1',
  'juice.characters.v1',
  'juice.crawl.v1',
  'juice.encounter.v1',
  'juice.map.v1',
  'juice.verdant.v1',
  'juice.rumors.v1',
  'juice.tracks.v1',
  'juice.settings.v1',
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

  Future<void> create(String name, {Set<String>? systems}) async {
    final s = state.valueOrNull;
    if (s == null) return;
    final meta =
        SessionMeta(id: _newId(), name: name, systems: systems?.toList());
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

/// Loads the party-emulator asset (Triple-O + Pettish tables) once.
final emulatorDataProvider =
    FutureProvider<EmulatorData>((ref) => EmulatorData.load());

final verdantDataProvider =
    FutureProvider<VerdantData>((ref) => VerdantData.load());

/// Loads the hand-written help asset once.
final helpDataProvider = FutureProvider<HelpData>((ref) async {
  final raw = await rootBundle.loadString('assets/help_data.json');
  return HelpData(jsonDecode(raw) as Map<String, dynamic>);
});

/// Page id the Help tool should open at (set by the tool-host '?');
/// consumed once by the Help screen, then reset to null.
final helpTopicProvider = StateProvider<String?>((ref) => null);

// -- Dismissed suggestions (session-scoped) -----------------------------------
class DismissedSuggestionsNotifier extends AsyncNotifier<Set<String>> {
  static const _baseKey = 'juice.suggestDismissed';

  late String _scopedKey;

  @override
  Future<Set<String>> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey);
    if (raw == null || raw.isEmpty) return const <String>{};
    try {
      return (jsonDecode(raw) as List).cast<String>().toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  Future<void> dismiss(String key) async {
    final current = {...(state.valueOrNull ?? await future)};
    current.add(key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, jsonEncode(current.toList()));
    state = AsyncData(current);
  }
}

final dismissedSuggestionsProvider =
    AsyncNotifierProvider<DismissedSuggestionsNotifier, Set<String>>(
        DismissedSuggestionsNotifier.new);

// -- Recap cache (session-scoped) ---------------------------------------------
class RecapCacheNotifier extends AsyncNotifier<RecapCache> {
  static const _baseKey = 'juice.recap';

  late String _scopedKey;

  @override
  Future<RecapCache> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey);
    if (raw == null || raw.isEmpty) return const RecapCache();
    try {
      return RecapCache.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const RecapCache();
    }
  }

  Future<void> _save(RecapCache c) async {
    state.valueOrNull ?? await future;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, jsonEncode(c.toJson()));
    state = AsyncData(c);
  }

  Future<void> markSeen(String entryId) async {
    final cur = state.valueOrNull ?? await future;
    await _save(cur.copyWith(lastSeenId: entryId));
  }

  Future<void> cacheSummary(String entryId, String summary) async {
    await _save(RecapCache(lastSeenId: entryId, summary: summary));
  }
}

final recapCacheProvider =
    AsyncNotifierProvider<RecapCacheNotifier, RecapCache>(
        RecapCacheNotifier.new);

/// Immutable recap cache value: last-seen entry id + cached summary.
class RecapCache {
  const RecapCache({this.lastSeenId, this.summary});

  final String? lastSeenId;
  final String? summary;

  factory RecapCache.fromJson(Map<String, dynamic> json) => RecapCache(
        lastSeenId: json['lastSeenId'] as String?,
        summary: json['summary'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (lastSeenId != null) 'lastSeenId': lastSeenId,
        if (summary != null) 'summary': summary,
      };

  RecapCache copyWith({String? lastSeenId, String? summary}) => RecapCache(
        lastSeenId: lastSeenId ?? this.lastSeenId,
        summary: summary ?? this.summary,
      );
}
