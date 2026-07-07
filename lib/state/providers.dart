import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/dice.dart';
import '../engine/dungeon/faction.dart';
import '../engine/dungeon/footprint.dart';
import '../engine/dungeon/generator.dart';
import '../engine/dungeon/placement.dart';
import '../engine/dungeon/tables.dart';
import '../engine/emulator_data.dart';
import '../engine/hexcrawl.dart';
import '../engine/hexcrawl_data.dart';
import '../engine/hexcrawl_map.dart';
import '../engine/lonelog_data.dart';
import '../engine/lonelog_export.dart';
import '../engine/lonelog_import.dart';
import '../engine/verdant_data.dart';
import '../engine/help_data.dart';
import '../engine/map_builder.dart';
import '../engine/journal_search.dart';
import '../engine/mention_parser.dart';
import '../engine/funnel.dart';
import '../engine/models.dart';
import '../engine/oracle.dart';
import '../engine/tarot_meanings.dart';
import '../engine/tarot_spreads.dart';
import '../engine/sketch.dart';
import '../engine/oracle_data.dart';
import '../engine/custom_sheet.dart';
import '../engine/custom_table.dart';
import '../engine/system_primer.dart';
import '../engine/quick_ref.dart';
import '../engine/spell.dart';
import '../engine/content_registry.dart';
import '../engine/loop_kit.dart';
import '../engine/tally.dart';
import 'blob_store.dart';
import 'campaign_bundle.dart';
import 'campaign_io.dart';
import 'cloud_key_store.dart';
import 'interpreter.dart';

/// Loads the data asset and builds the engine once. (The rootBundle load
/// lives here, not in the engine — lib/engine/ stays Flutter-free.)
final oracleProvider = FutureProvider<Oracle>((ref) async {
  final raw = await rootBundle.loadString('assets/oracle_data.json');
  return Oracle(OracleData(jsonDecode(raw) as Map<String, dynamic>));
});

/// Loads the Roll 4 Ruin dungeon-branch tables asset once.
final dungeonDataProvider = FutureProvider<DungeonTables>((ref) async {
  final raw = await rootBundle.loadString('assets/dungeon_data.json');
  return DungeonTables.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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

  /// Creates a scene entry and returns its id so callers can point the
  /// [PlayContext] spine (`setActiveScene`) at the new scene.
  Future<String> addScene(String title, {int? chaosFactor}) async {
    final id = _newId();
    await _persist([
      JournalEntry(
          id: id,
          timestamp: DateTime.now(),
          title: title,
          body: '',
          kind: JournalKind.scene,
          chaosFactor: chaosFactor),
      ...await _ready,
    ]);
    return id;
  }

  /// Marks the start of a play session with a divider entry.
  Future<void> addSessionBreak(String title) async {
    await _persist([
      JournalEntry(
          id: _newId(),
          timestamp: DateTime.now(),
          title: title,
          body: '',
          kind: JournalKind.session),
      ...await _ready,
    ]);
  }

  Future<void> addSketch(SketchData data) async {
    await _persist([
      JournalEntry(
          id: _newId(),
          timestamp: DateTime.now(),
          title: 'Sketch',
          body: '',
          kind: JournalKind.sketch,
          payload: {'v': 1, 'sketch': data.toJson()}),
      ...await _ready,
    ]);
  }

  Future<void> replace(JournalEntry entry) async {
    await _persist([
      for (final e in await _ready)
        if (e.id == entry.id) entry else e,
    ]);
  }

  /// Flips the per-entry [JournalEntry.pinned] flag and persists.
  Future<void> togglePin(String id) async {
    await _persist([
      for (final e in await _ready)
        if (e.id == id) e.copyWith(pinned: !e.pinned) else e,
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

/// Cached map of entry-id → character ids mentioned in that entry's body.
/// Recomputed only when the journal changes; avoids O(n) per-entry rescanning
/// on every rebuild in the journal and tracker screens.
final mentionedCharIdsProvider = Provider<Map<String, Set<String>>>((ref) {
  final entries = ref.watch(journalProvider).valueOrNull ?? const [];
  return {for (final e in entries) e.id: mentionedCharIds(e.body)};
});

/// Distinct tags across all journal entries, in first-seen order. Recomputed
/// only when the journal changes; avoids O(n·m) rescanning on every rebuild.
final allTagsProvider = Provider<List<String>>((ref) {
  final entries = ref.watch(journalProvider).valueOrNull ?? const [];
  return allTags(entries);
});

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

  /// Sets the numeric progress clock for thread [id], clamped to
  /// `0..thread.progressMax`, persisting the single updated thread.
  Future<void> setProgress(String id, int value) async {
    final threads = await _ready;
    final thread = threads.where((t) => t.id == id).firstOrNull;
    if (thread == null) return;
    final clamped = value.clamp(0, thread.progressMax);
    await replace(thread.copyWith(progress: clamped));
  }

  /// Attaches (or replaces) a success tally on thread [id].
  Future<void> setTally(String id, Tally tally) async {
    final thread = (await _ready).where((t) => t.id == id).firstOrNull;
    if (thread == null) return;
    await replace(thread.copyWith(tally: tally));
  }

  /// Removes the tally from thread [id], leaving the thread itself intact.
  Future<void> clearTally(String id) async {
    final thread = (await _ready).where((t) => t.id == id).firstOrNull;
    if (thread == null) return;
    await replace(thread.copyWith(clearTally: true));
  }

  /// Nudges the tally's current value by [delta] (clamped by Tally).
  Future<void> adjustTally(String id, int delta) async {
    final thread = (await _ready).where((t) => t.id == id).firstOrNull;
    final tally = thread?.tally;
    if (thread == null || tally == null) return;
    await replace(thread.copyWith(tally: tally.adjust(delta)));
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

  /// Creates a pre-made character seeded for [systemKey] at the top of the
  /// roster and returns its id. See [Character.forSheet] for the key mapping.
  Future<String> addPreMadeSheet(String systemKey) async {
    final id = _newId();
    await _persist([Character.forSheet(systemKey, id), ...await _ready]);
    return id;
  }

  /// Creates a pre-made Classic Ironsworn PC at the top and returns its id.
  Future<String> addIronsworn() => addPreMadeSheet('ironsworn');

  /// Creates a pre-made Starforged (or Sundered Isles) PC and returns its id.
  Future<String> addStarforged({String assetRuleset = 'starforged'}) =>
      addPreMadeSheet(assetRuleset);

  /// Creates a pre-made D&D 5e PC at the top and returns its id.
  Future<String> addDnd() => addPreMadeSheet('dnd');

  /// Creates a pre-made Shadowdark PC at the top and returns its id.
  Future<String> addShadowdark() => addPreMadeSheet('shadowdark');

  /// Creates a pre-made Nimble PC at the top and returns its id.
  Future<String> addNimble() => addPreMadeSheet('nimble');

  /// Creates a pre-made Draw Steel hero at the top and returns its id.
  Future<String> addDrawSteel() => addPreMadeSheet('draw-steel');

  Future<String> addArgosa() => addPreMadeSheet('argosa');
  Future<String> addCairn() => addPreMadeSheet('cairn');
  Future<String> addKnave() => addPreMadeSheet('knave');
  Future<String> addOse() => addPreMadeSheet('ose');
  Future<String> addKalArath() => addPreMadeSheet('kal-arath');
  Future<String> addDcc() => addPreMadeSheet('dcc');

  /// Creates a standalone funnel seeded from [seedSystem]'s FunnelProfile (one
  /// empty peasant) at the top of the roster and returns its id.
  Future<String> addFunnel(String seedSystem, {String seedVariant = ''}) async {
    final id = _newId();
    final profile = funnelProfileFor(seedSystem);
    final seed = profile == null
        ? const <FunnelPeasant>[]
        : [profile.seedPeasant(seedVariant)];
    final ch = Character(
      id: id,
      name: '0-Level Funnel',
      funnel: FunnelSheet(
          seedSystem: seedSystem, seedVariant: seedVariant, peasants: seed),
    );
    await _persist([ch, ...await _ready]);
    return id;
  }

  /// Spawns a hero Character built by [buildHero] (top of roster) and marks
  /// peasant [index] of [funnelChar] graduated — in one persist. Returns the
  /// hero's id.
  Future<String> graduateFunnelPeasant(Character funnelChar, int index,
      Character Function(String id) buildHero) async {
    final id = _newId();
    final hero = buildHero(id);
    final updated =
        funnelChar.copyWith(funnel: funnelChar.funnel!.markGraduated(index));
    await _persist([
      hero,
      for (final c in await _ready)
        if (c.id == funnelChar.id) updated else c,
    ]);
    return id;
  }

  /// Creates a custom/homebrew PC seeded with [blocks] at the top and returns
  /// its id. Unlike the fixed sheets, the schema is supplied by the caller
  /// (a chosen template, or empty for Blank).
  Future<String> addCustom(List<CustomBlock> blocks) async {
    final id = _newId();
    final c = Character(
        id: id,
        name: 'New custom character',
        custom: CustomSheet(blocks: blocks));
    await _persist([c, ...await _ready]);
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

  Future<void> setRole(String id, CharacterRole role) async {
    final list = await _ready;
    final c = list.where((e) => e.id == id).firstOrNull;
    if (c == null) return;
    await replace(c.copyWith(role: role));
  }

  Future<void> setConditions(String id, List<String> conditions) async {
    final list = await _ready;
    final c = list.where((e) => e.id == id).firstOrNull;
    if (c == null) return;
    await replace(c.copyWith(conditions: conditions));
  }

  /// Broadcast a single effect to many characters in one persist: an HP
  /// [hpDelta] (negative = damage, via [Character.withHpDelta]) and/or a set of
  /// [addConditions] merged into each target's conditions. Characters not in
  /// [ids] are untouched.
  Future<void> applyPartyEffect(
    Set<String> ids, {
    int hpDelta = 0,
    List<String> addConditions = const [],
  }) async {
    if (ids.isEmpty) return;
    await _persist([
      for (final c in await _ready)
        if (ids.contains(c.id))
          c.withHpDelta(hpDelta).copyWith(
              conditions: addConditions.isEmpty
                  ? c.conditions
                  : {...c.conditions, ...addConditions}.toList())
        else
          c,
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

// -- Inventory (Lonelog Resource Tracking addon) ----------------------------
class InventoryNotifier extends _PersistedList<InvItem> {
  @override
  String get prefsKey => 'juice.inventory.v1';
  @override
  InvItem fromJson(Map<String, dynamic> json) => InvItem.fromJson(json);
  @override
  Map<String, dynamic> toJsonMap(InvItem item) => item.toJson();

  Future<void> add(String name, {int qty = 1, String props = ''}) async {
    await _persist([
      InvItem(id: _newId(), name: name, qty: qty, props: props),
      ...await _ready
    ]);
  }

  Future<void> adjustQty(String id, int delta) async {
    await _persist([
      for (final i in await _ready)
        if (i.id == id) i.copyWith(qty: (i.qty + delta).clamp(0, 9999)) else i,
    ]);
  }

  Future<void> setProps(String id, String props) async {
    await _persist([
      for (final i in await _ready)
        if (i.id == id) i.copyWith(props: props) else i,
    ]);
  }

  Future<void> remove(String id) async {
    await _persist((await _ready).where((i) => i.id != id).toList());
  }
}

final inventoryProvider =
    AsyncNotifierProvider<InventoryNotifier, List<InvItem>>(
        InventoryNotifier.new);

// -- Units (Lonelog Wargaming addon) ----------------------------------------
class UnitNotifier extends _PersistedList<Unit> {
  @override
  String get prefsKey => 'juice.units.v1';
  @override
  Unit fromJson(Map<String, dynamic> json) => Unit.fromJson(json);
  @override
  Map<String, dynamic> toJsonMap(Unit item) => item.toJson();

  Future<void> add(String name, {String size = '', String status = ''}) async {
    await _persist([
      Unit(id: _newId(), name: name, size: size, status: status),
      ...await _ready
    ]);
  }

  Future<void> updateUnit(Unit unit) async {
    await _persist([
      for (final u in await _ready)
        if (u.id == unit.id) unit else u,
    ]);
  }

  Future<void> remove(String id) async {
    await _persist((await _ready).where((u) => u.id != id).toList());
  }
}

final unitsProvider =
    AsyncNotifierProvider<UnitNotifier, List<Unit>>(UnitNotifier.new);

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

// -- Card-deck oracles (standard 52 + tarot 78), drawn without replacement ---
class DecksNotifier extends AsyncNotifier<DecksState> {
  static const _baseKey = 'juice.decks.v1';

  late String _scopedKey;

  @override
  Future<DecksState> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey);
    if (raw == null || raw.isEmpty) return const DecksState();
    return DecksState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _save(DecksState s) async {
    // Update in-memory state BEFORE the async persist so a rapid second draw
    // (fired during this persist) reads the new deck, not the stale one.
    state = AsyncData(s);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, jsonEncode(s.toJson()));
  }

  /// The active standard-deck list: 54 cards with the jokers variant, else 52.
  List<String> _standardDeck(DecksState s) =>
      s.jokers ? kPlayingDeckWithJokers : kPlayingDeck;

  /// Draws one card (reshuffling if needed), persists the new deck state, and
  /// returns the card result. [tarot] selects the 78-card deck (reversible).
  Future<GenResult> draw(Oracle oracle, {required bool tarot}) async {
    final cur = state.valueOrNull ?? await future;
    final res = oracle.drawCard(
      deck: tarot ? kTarotDeck : _standardDeck(cur),
      state: tarot ? cur.tarot : cur.standard,
      title: tarot ? 'Tarot' : 'Card',
      reversible: tarot,
    );
    await _save(tarot
        ? cur.copyWith(tarot: res.next)
        : cur.copyWith(standard: res.next));
    return res.result;
  }

  /// Draws a card (persisting deck state) AND logs it to the journal with its
  /// tarot meaning folded in. Used by the HUD quick-draw button and the /card
  /// and /tarot slash commands (the Cards section shows the card before logging,
  /// so it uses draw() + manual log instead).
  Future<GenResult> drawAndLog(Oracle oracle, {required bool tarot}) async {
    final g = await draw(oracle, tarot: tarot);
    await ref.read(journalProvider.notifier).addResult(
          g.title,
          g.asText + tarotMeaningSuffix(g.summary ?? ''),
          sourceTool: 'cards',
          payload: g.toPayload(),
        );
    return g;
  }

  /// Draws a [spread] from the tarot deck, persisting the advanced DeckState.
  /// Returns the positioned cards + aggregate GenResult for the caller to
  /// render and log (mirrors draw() + manual log, since the Cards section shows
  /// the spread before logging). Tarot-only — spreads use the 78-card deck.
  Future<({List<({String position, String shown})> cards, GenResult result})>
      drawSpread(Oracle oracle, TarotSpread spread) async {
    final cur = state.valueOrNull ?? await future;
    final out = oracle.drawSpread(
      deck: kTarotDeck,
      state: cur.tarot,
      spread: spread,
      reversible: true,
    );
    await _save(cur.copyWith(tarot: out.next));
    return (cards: out.cards, result: out.result);
  }

  /// Draws a [spread] (persisting deck state) AND logs it as one `cards` journal
  /// entry, folding each position's meaning in via spreadBody. Mirrors
  /// drawAndLog for single cards; used by the /spread slash command. (The Cards
  /// section keeps its own draw → show → manual-log flow.)
  Future<void> drawSpreadAndLog(Oracle oracle, TarotSpread spread) async {
    final out = await drawSpread(oracle, spread);
    await ref.read(journalProvider.notifier).addResult(
          'Tarot Spread',
          spreadBody(spread.name, out.cards),
          sourceTool: 'cards',
        );
  }

  /// Clears a deck so the next draw reshuffles a full deck.
  Future<void> reshuffle({required bool tarot}) async {
    final cur = state.valueOrNull ?? await future;
    await _save(tarot
        ? cur.copyWith(tarot: const DeckState())
        : cur.copyWith(standard: const DeckState()));
  }

  /// Toggles the jokers variant for the standard deck, resetting the standard
  /// DeckState so the next draw reshuffles a full 52- or 54-card deck (keeps the
  /// remaining-readout denominator coherent).
  Future<void> setJokers(bool value) async {
    final cur = state.valueOrNull ?? await future;
    await _save(cur.copyWith(jokers: value, standard: const DeckState()));
  }
}

final decksProvider =
    AsyncNotifierProvider<DecksNotifier, DecksState>(DecksNotifier.new);

// -- Classic-dungeon factions (tracked monster factions per campaign) --------
class DungeonFactionsNotifier extends AsyncNotifier<FactionRegistry> {
  static const _baseKey = 'juice.dungeon_factions.v1';

  late String _scopedKey;

  @override
  Future<FactionRegistry> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey);
    return (raw == null || raw.isEmpty)
        ? const FactionRegistry()
        : FactionRegistry.fromJson(jsonDecode(raw));
  }

  Future<void> save(FactionRegistry reg) async {
    state = AsyncData(reg);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, jsonEncode(reg.toJson()));
  }

  Future<void> reset() async {
    state = const AsyncData(FactionRegistry());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scopedKey);
  }
}

final dungeonFactionsProvider =
    AsyncNotifierProvider<DungeonFactionsNotifier, FactionRegistry>(
        DungeonFactionsNotifier.new);

// -- Light timer (campaign-wide, session-scoped, ungated) -------------------
class LightNotifier extends AsyncNotifier<int> {
  static const _baseKey = 'juice.light.v1';
  late String _scopedKey;

  @override
  Future<int> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    _scopedKey = '$_baseKey.${sessions.active}';
    final prefs = await SharedPreferences.getInstance();
    return int.tryParse(prefs.getString(_scopedKey) ?? '') ?? 0;
  }

  Future<void> set(int value) async {
    final v = value.clamp(0, 9999);
    state = AsyncData(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey, '$v');
  }
}

final lightProvider =
    AsyncNotifierProvider<LightNotifier, int>(LightNotifier.new);

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

  /// Roll a d20 for every combatant whose initiative is unset (<= 0), then
  /// re-sort descending and reset the turn pointer to the top of the order.
  /// Initiatives the GM already entered (> 0) are preserved. No-op when empty.
  Future<void> rollInitiativeForAll({Dice? dice}) async {
    final s = await _ready;
    if (s.combatants.isEmpty) return;
    final d = dice ?? Dice();
    final rolled = [
      for (final c in s.combatants)
        c.initiative <= 0 ? c.copyWith(initiative: d.dN(20) + c.initMod) : c,
    ]..sort((a, b) {
        final byInit = b.initiative.compareTo(a.initiative);
        return byInit != 0 ? byInit : b.initMod.compareTo(a.initMod);
      });
    await save(s.copyWith(combatants: rolled, turnIndex: 0));
  }

  /// Link the encounter to a map cell (room or hex), or clear it with null.
  Future<void> setLocation(LocationRef? ref) async {
    final s = await _ready;
    await save(ref == null
        ? s.copyWith(clearLocationRef: true)
        : s.copyWith(locationRef: ref));
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

  /// Find the hex at (col,row), apply [f] to it, and persist. [f] returning
  /// null (or no hex at that cell) is a no-op — used by the guard cases.
  Future<void> _updateHex(
      int col, int row, HexCell? Function(HexCell) f) async {
    final s = await _ready;
    final idx = s.hexes.indexWhere((h) => h.col == col && h.row == row);
    if (idx < 0) return;
    final next = f(s.hexes[idx]);
    if (next == null) return;
    await save(s.copyWith(hexes: [...s.hexes]..[idx] = next));
  }

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

  /// Generate + place one classic-dungeon room mated to [doorEdge] on room
  /// [fromRoomId] (null/null = the entrance at (0,0)). Persists the faction
  /// registry when the generator extended it. Returns false when no footprint
  /// fits the chosen door (state unchanged).
  Future<bool> addClassicRoom({
    required String? fromRoomId,
    required ({(int, int) cell, Side side})? doorEdge,
    required DungeonTables tables,
    required A2Type effect,
    required Dice dice,
  }) async {
    final s = await _ready;
    final factions = ref.read(dungeonFactionsProvider).valueOrNull ??
        const FactionRegistry();
    // The id is minted BEFORE generating so a faction assigned inside
    // generateRoom carries the real room id from the start.
    final id = _newId();
    final gen = generateRoom(
        DungeonGenContext(
            level: 1,
            effect: effect,
            tables: tables,
            factions: factions,
            roomId: id),
        dice);
    final catalog =
        gen.type == RoomType.corridor ? kCorridorShapes : kChamberShapes;
    final candidates = catalog[gen.shapeFamily]!;

    final List<(int, int)> footprintOffsets;
    final List<DoorEdge> doors;
    final int ax, ay;

    if (fromRoomId == null || doorEdge == null) {
      // Entrance at (0,0): first footprint of the rolled family, unrotated;
      // every opening starts open (there is no entry edge).
      final fp = candidates.first;
      ax = 0;
      ay = 0;
      footprintOffsets = fp.normalizedCells;
      doors = [
        for (final o in fp.openings) DoorEdge(o.cell, o.side, DoorKind.open)
      ];
    } else {
      final occupied = <(int, int)>{
        for (final r in s.rooms)
          for (final c in r.footprint) (r.x + c.$1, r.y + c.$2)
      };
      final placed = placeRoom(occupied, doorEdge, candidates, dice);
      if (placed == null) return false;
      final minX =
          placed.cells.map((c) => c.$1).reduce((a, b) => a < b ? a : b);
      final minY =
          placed.cells.map((c) => c.$2).reduce((a, b) => a < b ? a : b);
      ax = minX;
      ay = minY;
      footprintOffsets = [
        for (final c in placed.cells) (c.$1 - minX, c.$2 - minY)
      ];
      doors = [
        // The mated entry edge takes its kind from the type die.
        DoorEdge(
            (placed.entryDoor.cell.$1 - minX, placed.entryDoor.cell.$2 - minY),
            placed.entryDoor.side,
            gen.entryDoorKind),
        for (final d in placed.openDoors)
          DoorEdge((d.cell.$1 - minX, d.cell.$2 - minY), d.side, DoorKind.open),
      ];
    }

    final room = DungeonRoom(
      id: id,
      x: ax,
      y: ay,
      title: gen.detail.split('\n').first,
      detail: gen.detail,
      footprint: footprintOffsets,
      doors: doors,
      roomType: gen.type == RoomType.corridor ? 'corridor' : 'chamber',
    );

    if (!identical(gen.factions, factions)) {
      await ref.read(dungeonFactionsProvider.notifier).save(gen.factions);
    }

    await save(s.copyWith(
      rooms: [...s.rooms, room],
      corridors: fromRoomId == null
          ? s.corridors
          : [
              ...s.corridors,
              [fromRoomId, id],
            ],
      currentRoomId: room.id,
    ));
    return true;
  }

  /// Hexcrawl crawl: add one dungeon room with generic content.
  Future<void> crawlDungeon(HexcrawlData data, Dice dice) async {
    final r = rollDungeonRoom(data, dice);
    await addRoom(title: r.title, detail: r.detail, dice: dice);
  }

  /// Hexcrawl full dungeon: add [count] connected rooms with generic content.
  Future<void> generateDungeon(HexcrawlData data, int count, Dice dice) async {
    for (var i = 0; i < count; i++) {
      final r = rollDungeonRoom(data, dice);
      await addRoom(title: r.title, detail: r.detail, dice: dice);
    }
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

  /// Append an arbitrary line to a hex site's writeup (AI flesh-out). No-op if
  /// the hex is absent or has no site. Deliberately uncapped — unlike
  /// [crawlSite]'s 5-line dice-writeup cap, this is user-initiated free-text
  /// enrichment and may push the site past 5 lines (which only stops further
  /// dice crawling, by design).
  Future<void> appendSiteLine(int col, int row, String text) async {
    await _updateHex(col, row, (h) {
      if (h.site == null) return null;
      return h.copyWith(siteLines: [...h.siteLines, text]);
    });
  }

  /// Set a room's Lonelog status (Dungeon-Crawling addon); '' clears it.
  Future<void> setRoomStatus(String id, String status) async {
    final s = await _ready;
    await save(s.copyWith(rooms: [
      for (final r in s.rooms)
        if (r.id == id) r.copyWith(status: status) else r,
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

  /// Hexcrawl crawl-reveal: the next hex's terrain is rolled from the current
  /// hex's terrain (or a climate seed), plus an optional site. Advances current.
  Future<void> crawlHexcrawl(
      HexcrawlData data, String climate, Dice dice) async {
    final s = await _ready;
    final pos =
        nextHexPosition(s.hexes, s.currentHexCol, s.currentHexRow, dice);
    if (pos.alreadyRevealed) {
      await save(s.copyWith(currentHexCol: pos.col, currentHexRow: pos.row));
      return;
    }
    HexCell? cur;
    for (final h in s.hexes) {
      if (h.col == s.currentHexCol && h.row == s.currentHexRow) {
        cur = h;
        break;
      }
    }
    final fromTerrain = cur?.terrain ??
        rollTerrain(data, climate, dice)?.key ??
        data.terrains.first.key;
    final rolled = rollCrawlHex(data, fromTerrain, dice);
    final cell = HexCell(
        col: pos.col,
        row: pos.row,
        envRow: 1,
        terrain: rolled.terrain,
        site: rolled.site);
    await save(s.copyWith(
        hexes: [...s.hexes, cell],
        currentHexCol: pos.col,
        currentHexRow: pos.row));
  }

  /// Hexcrawl full-region: place [count] connected hexes (terrain + sites),
  /// anchored at the current hex (or origin); existing hexes are not overwritten.
  Future<void> generateRegion(
      HexcrawlData data, String climate, int count, Dice dice) async {
    final s = await _ready;
    final region =
        growRegion(data: data, climate: climate, count: count, dice: dice);
    // Anchor at the current hex; if none, an existing hex (so the region
    // connects to it); else the origin.
    final (ax, ay) = (s.currentHexCol != null && s.currentHexRow != null)
        ? (s.currentHexCol!, s.currentHexRow!)
        : (s.hexes.isNotEmpty
            ? (s.hexes.first.col, s.hexes.first.row)
            : (0, 0));
    final existing = {for (final h in s.hexes) (h.col, h.row)};
    final added = <HexCell>[];
    for (final g in region) {
      final col = ax + g.col;
      final row = ay + g.row;
      if (existing.contains((col, row))) continue;
      added.add(HexCell(
          col: col, row: row, envRow: 1, terrain: g.terrain, site: g.site));
    }
    await save(s.copyWith(
        hexes: [...s.hexes, ...added], currentHexCol: ax, currentHexRow: ay));
  }

  /// Local-zoom crawl: reveal the next ring sub-hex (0..5) of the hex at
  /// (col,row). No-op if the hex is absent, has no terrain, or is full.
  Future<void> crawlLocal(
      int col, int row, HexcrawlData data, Dice dice) async {
    await _updateHex(col, row, (h) {
      if (h.terrain == null || h.local.length >= 6) return null;
      final cell = rollLocalCell(data, h.terrain!, h.local.length, dice);
      return h.copyWith(local: [...h.local, cell]);
    });
  }

  /// Local-zoom full: fill all 6 ring sub-hexes of the hex at (col,row).
  Future<void> generateLocal(
      int col, int row, HexcrawlData data, Dice dice) async {
    await _updateHex(col, row, (h) {
      if (h.terrain == null) return null;
      final cells = [
        for (var i = 0; i < 6; i++) rollLocalCell(data, h.terrain!, i, dice)
      ];
      return h.copyWith(local: cells);
    });
  }

  /// Set the hexcrawl site-type on an existing hex; no-op for unknown cells.
  Future<void> setHexSite(int col, int row, String site) async {
    await _updateHex(col, row, (h) => h.copyWith(site: site));
  }

  /// Site crawl: append the next writeup line for the site at (col,row).
  /// No-op if the hex is absent, has no site, or already has 5 lines.
  Future<void> crawlSite(int col, int row, HexcrawlData data, Dice dice) async {
    await _updateHex(col, row, (h) {
      if (h.site == null || h.siteLines.length >= 5) return null;
      final line = rollSiteLine(data, h.siteLines.length, dice);
      return h.copyWith(siteLines: [...h.siteLines, line]);
    });
  }

  /// Site full: set the 4-line writeup for the site at (col,row).
  Future<void> generateSite(
      int col, int row, HexcrawlData data, Dice dice) async {
    await _updateHex(col, row, (h) {
      if (h.site == null) return null;
      return h.copyWith(siteLines: rollSiteDetail(data, dice));
    });
  }

  /// Site interior crawl: append one area to the site at (col,row).
  Future<void> crawlSiteArea(
      int col, int row, HexcrawlData data, Dice dice) async {
    await _updateHex(col, row, (h) {
      if (h.site == null) return null;
      final pos = nextSiteAreaPosition(h.siteAreas, dice);
      final area = SiteArea(x: pos.x, y: pos.y, name: rollSiteArea(data, dice));
      return h.copyWith(siteAreas: [...h.siteAreas, area]);
    });
  }

  /// Site interior full: generate a fresh [count]-area interior (clamp 3..12)
  /// for the site at (col,row).
  Future<void> generateSiteInterior(
      int col, int row, int count, HexcrawlData data, Dice dice) async {
    await _updateHex(col, row, (h) {
      if (h.site == null) return null;
      final n = count.clamp(3, 12);
      final areas = <SiteArea>[];
      for (var i = 0; i < n; i++) {
        final pos = nextSiteAreaPosition(areas, dice);
        areas.add(SiteArea(x: pos.x, y: pos.y, name: rollSiteArea(data, dice)));
      }
      return h.copyWith(siteAreas: areas);
    });
  }

  /// Set the Verdant terrain key on an existing hex; no-op for unknown cells.
  Future<void> setHexTerrain(int col, int row, String terrainKey) async {
    await _updateHex(col, row, (h) => h.copyWith(terrain: terrainKey));
  }

  /// Add a Point of Interest (1..12) to an existing hex; ignores duplicates.
  Future<void> addHexPoi(int col, int row, int poiN) async {
    await _updateHex(
        col,
        row,
        (h) => h.copyWith(
            pois: h.pois.contains(poiN) ? h.pois : [...h.pois, poiN]));
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

// -- AI enable (app-global; NOT per-campaign, NOT exported) -----------------
class AiEnabledNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.ai_enabled.v1';

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> setEnabled(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(_key, value);
    state = AsyncData(value);
  }
}

final aiEnabledProvider =
    AsyncNotifierProvider<AiEnabledNotifier, bool>(AiEnabledNotifier.new);

/// App-global saved-creature library (the bestiary). NOT session-scoped and NOT
/// part of campaign export — a bestiary is reusable across campaigns (same
/// posture as [aiEnabledProvider]).
class BestiaryNotifier extends AsyncNotifier<List<Creature>> {
  static const _key = 'juice.bestiary.v1';

  @override
  Future<List<Creature>> build() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List)
        .map(Creature.maybeFromJson)
        .whereType<Creature>()
        .toList();
  }

  Future<List<Creature>> get _ready async => state.valueOrNull ?? await future;

  Future<void> _save(List<Creature> list) async {
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(list.map((c) => c.toJson()).toList()));
    state = AsyncData(list);
  }

  Future<void> add(Creature c) async {
    await _save([...await _ready, c]);
  }

  Future<void> remove(String id) async {
    await _save((await _ready).where((c) => c.id != id).toList());
  }

  Future<void> replace(Creature c) async {
    await _save((await _ready).map((e) => e.id == c.id ? c : e).toList());
  }
}

final bestiaryProvider =
    AsyncNotifierProvider<BestiaryNotifier, List<Creature>>(
        BestiaryNotifier.new);

/// App-global store of user-authored random tables. Like [bestiaryProvider],
/// this is NOT session-scoped and NOT exported — tables are reusable across
/// campaigns and live per-device.
class CustomTablesNotifier extends AsyncNotifier<List<CustomTable>> {
  static const _key = 'juice.custom_tables.v1';

  @override
  Future<List<CustomTable>> build() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List)
        .map(CustomTable.maybeFromJson)
        .whereType<CustomTable>()
        .toList();
  }

  Future<List<CustomTable>> get _ready async =>
      state.valueOrNull ?? await future;

  Future<void> _save(List<CustomTable> list) async {
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(list.map((t) => t.toJson()).toList()));
    state = AsyncData(list);
  }

  Future<void> add(CustomTable t) async => _save([...await _ready, t]);

  /// Append [incoming] tables with fresh ids (import never clobbers existing).
  /// copyWith preserves id, so a new [CustomTable] is constructed per entry.
  Future<void> addAll(List<CustomTable> incoming) async {
    if (incoming.isEmpty) return;
    final base = DateTime.now().microsecondsSinceEpoch;
    final fresh = [
      for (var i = 0; i < incoming.length; i++)
        CustomTable(
          id: '${base + i}',
          name: incoming[i].name,
          mode: incoming[i].mode,
          dice: incoming[i].dice,
          rows: incoming[i].rows,
        ),
    ];
    await _save([...await _ready, ...fresh]);
  }

  Future<void> remove(String id) async =>
      _save((await _ready).where((t) => t.id != id).toList());
  Future<void> replace(CustomTable t) async =>
      _save((await _ready).map((e) => e.id == t.id ? t : e).toList());
}

final customTablesProvider =
    AsyncNotifierProvider<CustomTablesNotifier, List<CustomTable>>(
        CustomTablesNotifier.new);

/// App-global user-authored ref cards (reusable across campaigns; NOT
/// session-scoped, NOT in campaign export — mirrors [customTablesProvider]).
class UserRefCardsNotifier extends AsyncNotifier<List<UserRefCard>> {
  static const _key = 'juice.userrefcards.v1';

  @override
  Future<List<UserRefCard>> build() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List)
        .map(UserRefCard.maybeFromJson)
        .whereType<UserRefCard>()
        .toList();
  }

  Future<List<UserRefCard>> get _ready async =>
      state.valueOrNull ?? await future;

  Future<void> _save(List<UserRefCard> list) async {
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(list.map((c) => c.toJson()).toList()));
    state = AsyncData(list);
  }

  Future<void> add(UserRefCard c) async => _save([...await _ready, c]);

  /// Append [incoming] cards with fresh ids (import never clobbers existing).
  /// Mirrors CustomTablesNotifier.addAll.
  Future<void> addAll(List<UserRefCard> incoming) async {
    if (incoming.isEmpty) return;
    final base = DateTime.now().microsecondsSinceEpoch;
    final fresh = [
      for (var i = 0; i < incoming.length; i++)
        UserRefCard(
          id: '${base + i}',
          title: incoming[i].title,
          sections: incoming[i].sections,
        ),
    ];
    await _save([...await _ready, ...fresh]);
  }

  Future<void> remove(String id) async =>
      _save((await _ready).where((c) => c.id != id).toList());
  Future<void> replace(UserRefCard c) async =>
      _save((await _ready).map((e) => e.id == c.id ? c : e).toList());
}

final userRefCardsProvider =
    AsyncNotifierProvider<UserRefCardsNotifier, List<UserRefCard>>(
        UserRefCardsNotifier.new);

/// The bundled asset filenames for the seed loop kits (populated in a later
/// task). Adding a new seed kit means adding its filename here AND to
/// pubspec.yaml's assets list.
const kKitAssetPaths = <String>[
  'assets/kits/ironsworn-ash-and-embers.json',
  'assets/kits/ironsworn-salt-and-storm.json',
  'assets/kits/dnd-sunken-crypt.json',
  'assets/kits/dnd-market-of-masks.json',
  'assets/kits/cairn-lonely-road.json',
  'assets/kits/cairn-black-bramble.json',
];

/// Loads the bundled seed loop kits. Asset-loading glue (like
/// systemFoesProvider/systemSpellsProvider) — not unit-tested directly;
/// decodeLoopKit's tolerant-decode logic is what's actually under test.
final kitsProvider = FutureProvider<List<LoopKit>>((ref) async {
  final kits = <LoopKit>[];
  for (final path in kKitAssetPaths) {
    final raw = await rootBundle.loadString(path);
    final kit = decodeLoopKit(raw);
    if (kit != null) kits.add(kit);
  }
  return kits;
});

/// One-shot "the contextual AI-enable nudge has been seen/dismissed" flag.
/// App-global (NOT session-scoped, NOT exported) — same posture as
/// [aiEnabledProvider]: the nudge is a per-device first-run affordance.
class AiNudgeSeenNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.ai_nudge_seen.v1';

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> markSeen() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, true);
    state = const AsyncData(true);
  }
}

final aiNudgeSeenProvider =
    AsyncNotifierProvider<AiNudgeSeenNotifier, bool>(AiNudgeSeenNotifier.new);

/// App-global last-export timestamp (milliseconds since epoch, or null).
/// Stamped on every successful campaign export; per-device, NOT session-scoped.
class LastExportNotifier extends AsyncNotifier<int?> {
  static const _key = 'juice.last_export.v1';

  @override
  Future<int?> build() async =>
      (await SharedPreferences.getInstance()).getInt(_key);

  Future<void> stamp() async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await p.setInt(_key, now);
    state = AsyncData(now);
  }
}

final lastExportProvider =
    AsyncNotifierProvider<LastExportNotifier, int?>(LastExportNotifier.new);

/// App-global flag: the first-launch welcome card has been dismissed.
/// Same posture as [aiNudgeSeenProvider] — per-device, NOT session-scoped.
class WelcomeSeenNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.welcome_seen.v1';

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> markSeen() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, true);
    state = const AsyncData(true);
  }
}

final welcomeSeenProvider =
    AsyncNotifierProvider<WelcomeSeenNotifier, bool>(WelcomeSeenNotifier.new);

/// App-global flag: the first-run "turn on AI enhancements" offer dialog has
/// been shown once (accepted or dismissed). Same posture as
/// [welcomeSeenProvider] — per-device, NOT session-scoped, NOT exported. Keeps
/// the offer to a single appearance so it never nags.
class AiOfferSeenNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.ai_offer_seen.v1';

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> markSeen() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, true);
    state = const AsyncData(true);
  }
}

final aiOfferSeenProvider =
    AsyncNotifierProvider<AiOfferSeenNotifier, bool>(AiOfferSeenNotifier.new);

/// App-global flag: the Track-home orientation card has been dismissed.
/// Same posture as [welcomeSeenProvider] — per-device, NOT session-scoped.
class TrackHelpSeenNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.track_help_seen.v1';

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> markSeen() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, true);
    state = const AsyncData(true);
  }
}

final trackHelpSeenProvider =
    AsyncNotifierProvider<TrackHelpSeenNotifier, bool>(
        TrackHelpSeenNotifier.new);

/// App-global flag: the recap banner has been permanently suppressed ("Never").
/// Same posture as [welcomeSeenProvider] — per-device, NOT session-scoped.
class RecapSuppressedNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.recap_suppressed.v1';

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> markSeen() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, true);
    state = const AsyncData(true);
  }
}

final recapSuppressedProvider =
    AsyncNotifierProvider<RecapSuppressedNotifier, bool>(
        RecapSuppressedNotifier.new);

/// App-global sticky state for the assistant rail's open/collapsed position.
/// Default true (open) so new users see suggestion chips immediately.
class AssistantRailExpandedNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.assistant_rail_expanded.v1';

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? true;

  Future<void> setExpanded(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, value);
    state = AsyncData(value);
  }
}

final assistantRailExpandedProvider =
    AsyncNotifierProvider<AssistantRailExpandedNotifier, bool>(
        AssistantRailExpandedNotifier.new);

/// App-global sticky state for the Play screen's Solo-Loop bar (expanded vs
/// collapsed). Default false (collapsed) so the Play screen opens to the journal
/// feed — the loop bar's "Next beat" + Steps otherwise stack ~160px of chrome
/// above the feed and squeeze it. The always-visible "Solo Loop" header keeps it
/// one tap away. Per-device, NOT session-scoped — same posture as
/// [assistantRailExpandedProvider].
class LoopBarExpandedNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.loopbar_expanded.v1';

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> setExpanded(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, value);
    state = AsyncData(value);
  }
}

final loopBarExpandedProvider =
    AsyncNotifierProvider<LoopBarExpandedNotifier, bool>(
        LoopBarExpandedNotifier.new);

/// The interpreter's status as a reactive provider (the service exposes it as
/// a ValueListenable). Lets AI affordances rebuild as the phase flips.
final interpreterStatusProvider = StreamProvider<InterpreterStatus>((ref) {
  final vl = ref.watch(interpreterServiceProvider).status;
  final controller = StreamController<InterpreterStatus>();
  void listener() => controller.add(vl.value);
  vl.addListener(listener);
  controller.add(vl.value); // seed current value
  ref.onDispose(() {
    vl.removeListener(listener);
    controller.close();
  });
  return controller.stream;
});

/// The current phase, reactive via [interpreterStatusProvider] but falling back
/// to the service's synchronous value on the stream's first (loading) frame so
/// gates don't flicker through a null phase before the first emit.
InterpreterPhase _phase(Ref ref) =>
    ref.watch(interpreterStatusProvider).valueOrNull?.phase ??
    ref.watch(interpreterServiceProvider).status.value.phase;

/// Single source of truth every AI affordance watches.
/// ready => downloaded + loaded; enabled => opted in via Settings.
final aiReadyProvider = Provider<bool>((ref) {
  final enabled = ref.watch(aiEnabledProvider).valueOrNull ?? false;
  return enabled && _phase(ref) == InterpreterPhase.ready;
});

/// Settings-only: decides toggle vs "not available on this platform".
final aiSupportedProvider =
    Provider<bool>((ref) => _phase(ref) != InterpreterPhase.unsupported);

// -- Cloud interpretation (BYO Claude key; interpret() seam ONLY) -----------
// The API key is a real, billable secret -> secure storage, NOT the plaintext
// SharedPreferences every other setting uses. The toggle itself is a plain UI
// preference (not sensitive), so it DOES use SharedPreferences, matching
// aiEnabledProvider's pattern.
final cloudKeyStoreProvider =
    Provider<CloudKeyStore>((ref) => SecureCloudKeyStore());

final cloudApiKeyProvider =
    FutureProvider<String?>((ref) => ref.watch(cloudKeyStoreProvider).read());

class CloudInterpretEnabledNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.cloud_interpret_enabled.v1';

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> setEnabled(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(_key, value);
    state = AsyncData(value);
  }
}

final cloudInterpretEnabledProvider =
    AsyncNotifierProvider<CloudInterpretEnabledNotifier, bool>(
        CloudInterpretEnabledNotifier.new);

/// Scoped readiness for the interpret() seam ONLY — true when EITHER the
/// on-device model is ready OR the cloud toggle is on with a saved key.
/// Deliberately narrower than [aiReadyProvider]: every other AI seam
/// (voiceLine/summarize/gmChat/narrate/fleshOut/rankSuggestions) keeps
/// gating on [aiReadyProvider] unchanged, so enabling cloud does NOT unlock
/// their UI (which would fail — those seams still require on-device).
final interpretReadyProvider = Provider<bool>((ref) {
  if (ref.watch(aiReadyProvider)) return true;
  final cloudOn = ref.watch(cloudInterpretEnabledProvider).valueOrNull ?? false;
  final key = ref.watch(cloudApiKeyProvider).valueOrNull;
  return cloudOn && key != null && key.isNotEmpty;
});

// -- Sessions ---------------------------------------------------------------
/// Base keys holding per-session data; scoped as '<base>.<sessionId>'.
const sessionScopedKeys = [
  'juice.journal.v2',
  'juice.threads.v1',
  'juice.characters.v1',
  'juice.crawl.v1',
  'juice.encounter.v1',
  'juice.map.v1',
  'juice.dungeon_factions.v1',
  'juice.verdant.v1',
  'juice.rumors.v1',
  'juice.tracks.v1',
  'juice.inventory.v1',
  'juice.units.v1',
  'juice.settings.v1',
  'juice.context.v1',
  'juice.decks.v1',
  'juice.gmchat.v1',
  'juice.light.v1',
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

  Future<void> create(String name,
      {Set<String>? systems,
      CampaignMode mode = CampaignMode.party,
      String genre = '',
      String tone = ''}) async {
    final s = state.valueOrNull;
    if (s == null) return;
    final id = _newId();
    // Derive a per-campaign identity: a varied hue + the ruleset/mode icon.
    final resolvedSystems = systems ?? kAllSystems;
    final meta = SessionMeta(
      id: id,
      name: name,
      systems: systems?.toList(),
      mode: mode,
      identityColor: identityHueFor(id, s.sessions.length),
      identityIcon: identityIconKeyFor(resolvedSystems, mode),
      genre: genre.isEmpty ? null : genre,
    );
    if (genre.isNotEmpty || tone.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('juice.settings.v1.${meta.id}',
          jsonEncode(CampaignSettings(genre: genre, tone: tone).toJson()));
    }
    await _save(
        SessionsState(active: meta.id, sessions: [...s.sessions, meta]));
  }

  /// Rename session [id]; no-op for unknown ids or a blank name.
  Future<void> rename(String id, String name) async {
    final s = state.valueOrNull;
    if (s == null || name.trim().isEmpty) return;
    final updated = [
      for (final m in s.sessions)
        if (m.id == id) m.copyWith(name: name.trim()) else m,
    ];
    await _save(SessionsState(active: s.active, sessions: updated));
  }

  /// Replace the enabled optional systems for session [id].
  Future<void> editSystems(String id, Set<String> systems) async {
    final s = state.valueOrNull;
    if (s == null) return;
    final updated = [
      for (final m in s.sessions)
        if (m.id == id) m.copyWith(systems: systems.toList()) else m,
    ];
    await _save(SessionsState(active: s.active, sessions: updated));
  }

  /// Set the player-focus mode for session [id]. Preserves systems.
  Future<void> setMode(String id, CampaignMode mode) async {
    final s = state.valueOrNull;
    if (s == null) return;
    final updated = [
      for (final m in s.sessions)
        if (m.id == id) m.copyWith(mode: mode) else m,
    ];
    await _save(SessionsState(active: s.active, sessions: updated));
  }

  /// Set the per-campaign D&D SRD edition ("5.1" | "5.2") for session [id].
  Future<void> setDndEdition(String id, String edition) async {
    final s = state.valueOrNull;
    if (s == null) return;
    final updated = [
      for (final m in s.sessions)
        if (m.id == id) m.copyWith(dndEdition: edition) else m,
    ];
    await _save(SessionsState(active: s.active, sessions: updated));
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
      systems: s.activeMeta.systems,
      mode: s.activeMeta.mode,
    );
  }

  /// Export the active session as a file: a `.juice.zip` bundle when it
  /// references blob images (so annotations travel with it), else a plain
  /// `.juice.json` string. Returns the bytes + the file extension to use.
  Future<({List<int> bytes, String ext})> exportActiveFile() async {
    final json = await exportActive();
    final plain = (bytes: utf8.encode(json), ext: 'json');
    if (!ref.read(blobStoreAvailableProvider)) return plain;
    final s = state.valueOrNull ?? await future;
    final prefs = await SharedPreferences.getInstance();
    final journalRaw = prefs.getString('juice.journal.v2.${s.active}');
    final ids = referencedBlobIds(
        {if (journalRaw != null) 'juice.journal.v2': journalRaw});
    if (ids.isEmpty) return plain;
    final store = ref.read(blobStoreProvider);
    final blobs = <String, Uint8List>{};
    for (final id in ids) {
      final b = await store.get(id);
      if (b != null) blobs[id] = b;
    }
    if (blobs.isEmpty) return plain;
    return (bytes: encodeCampaignBundle(json, blobs), ext: 'zip');
  }

  /// Serialize the active session to a Lonelog `.md` document.
  Future<String> exportActiveAsLonelog() async {
    final s = state.valueOrNull ?? await future;
    final journal = await ref.read(journalProvider.future);
    final threads = await ref.read(threadsProvider.future);
    final characters = await ref.read(charactersProvider.future);
    final tracks = await ref.read(tracksProvider.future);
    final settings = await ref.read(settingsProvider.future);
    return campaignToLonelog(
      campaignName: s.activeMeta.name,
      genre: settings.genre,
      tone: settings.tone,
      threads: threads,
      characters: characters,
      tracks: tracks,
      entriesNewestFirst: journal,
      threadTitles: {for (final t in threads) t.id: t.title},
      exportedAt: DateTime.now(),
    );
  }

  /// Import a campaign file as a NEW session and switch to it.
  /// Throws [FormatException] on invalid files.
  Future<void> importCampaign(String fileContent) async {
    final parsed = parseCampaign(fileContent);
    final s = state.valueOrNull ?? await future;
    // Restore the campaign profile (enabled systems + GM/Party mode) from the
    // file; older files without these default to all-systems + party.
    final meta = SessionMeta(
      id: _newId(),
      name: parsed.name,
      systems: parsed.systems,
      mode: parsed.mode,
      genre: (parsed.genre?.isEmpty ?? true) ? null : parsed.genre,
    );
    final prefs = await SharedPreferences.getInstance();
    for (final e in parsed.rawByKey.entries) {
      await prefs.setString('${e.key}.${meta.id}', e.value);
    }
    await _save(
        SessionsState(active: meta.id, sessions: [...s.sessions, meta]));
  }

  /// Import campaign file [bytes]: a `.juice.zip` bundle (extracts its blobs into
  /// the blob store, then imports the JSON) or a plain `.juice.json` string.
  /// Throws [FormatException] on invalid files.
  Future<void> importCampaignData(List<int> bytes) async {
    final bundle = decodeCampaignBundle(bytes);
    if (bundle == null) {
      await importCampaign(utf8.decode(bytes)); // plain JSON
      return;
    }
    if (ref.read(blobStoreAvailableProvider)) {
      final store = ref.read(blobStoreProvider);
      for (final e in bundle.blobs.entries) {
        // Re-put under the same content-addressed id (same bytes + ext).
        await store.put(e.value, ext: blobExtFromId(e.key));
      }
    }
    await importCampaign(bundle.campaignJson);
  }

  /// Delete blobs no campaign references — orphans from cancelled image/PDF
  /// imports, re-annotation, or deleted sketches. Blobs are global (shared
  /// across campaigns), so this scans EVERY session's journal before deleting.
  /// Returns the number removed; a no-op when the blob store is unavailable.
  Future<int> gcBlobs() async {
    if (!ref.read(blobStoreAvailableProvider)) return 0;
    final store = ref.read(blobStoreProvider);
    final all = await store.list();
    if (all.isEmpty) return 0;
    final s = state.valueOrNull ?? await future;
    final prefs = await SharedPreferences.getInstance();
    final referenced = <String>{};
    for (final meta in s.sessions) {
      final j = prefs.getString('juice.journal.v2.${meta.id}');
      if (j != null) {
        referenced.addAll(referencedBlobIds({'juice.journal.v2': j}));
      }
    }
    var removed = 0;
    for (final id in all) {
      if (!referenced.contains(id)) {
        await store.delete(id);
        removed++;
      }
    }
    return removed;
  }

  /// Import a Lonelog `.md` document as a NEW session and switch to it.
  /// Throws [FormatException] when the content is not Lonelog-shaped.
  Future<void> importLonelog(String content) async {
    if (!content.trimLeft().startsWith('---') &&
        !content.contains('[STATE]') &&
        !content.contains('## Session log')) {
      throw const FormatException('Not a Lonelog file');
    }
    final doc = parseLonelog(content, importedAt: DateTime.now());
    final s = state.valueOrNull ?? await future;
    // Campaign files don't carry session mode; imported campaigns default to party.
    final meta = SessionMeta(
      id: _newId(),
      name: doc.campaignName,
      genre: doc.genre.isEmpty ? null : doc.genre,
    );
    final prefs = await SharedPreferences.getInstance();
    final rawByKey = <String, String>{
      'juice.journal.v2':
          jsonEncode(doc.entries.map((e) => e.toJson()).toList()),
      'juice.threads.v1':
          jsonEncode(doc.threads.map((t) => t.toJson()).toList()),
      'juice.characters.v1':
          jsonEncode(doc.characters.map((c) => c.toJson()).toList()),
      'juice.tracks.v1': jsonEncode(doc.tracks.map((t) => t.toJson()).toList()),
      'juice.settings.v1': jsonEncode(
          CampaignSettings(genre: doc.genre, tone: doc.tone).toJson()),
    };
    for (final e in rawByKey.entries) {
      await prefs.setString('${e.key}.${meta.id}', e.value);
    }
    await _save(
        SessionsState(active: meta.id, sessions: [...s.sessions, meta]));
  }
}

/// Transient launcher gate: shown on every cold start (in-memory, not
/// persisted). Any launcher entry action calls [dismiss] to enter the journal.
class LauncherGateNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void dismiss() => state = false;
}

final launcherGateProvider =
    NotifierProvider<LauncherGateNotifier, bool>(LauncherGateNotifier.new);

final sessionsProvider = AsyncNotifierProvider<SessionsNotifier, SessionsState>(
    SessionsNotifier.new);

final modeProvider = Provider<CampaignMode>((ref) =>
    ref.watch(sessionsProvider).valueOrNull?.activeMeta.mode ??
    CampaignMode.party);

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

/// The resolved facts-only system primer for the active campaign, or '' when
/// no covered TTRPG system is enabled. Fed into the oracle/voice prompts (see
/// lib/engine/system_primer.dart).
final systemPrimerProvider = Provider<String>((ref) {
  final systems =
      ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
          kAllSystems;
  final rulesets = ref.watch(rulesetsProvider).valueOrNull ?? const <String>{};
  return resolveSystemPrimer(systems, rulesets);
});

final resolvedSystemProvider = Provider<String>((ref) {
  final systems =
      ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
          kAllSystems;
  final rulesets = ref.watch(rulesetsProvider).valueOrNull ?? const <String>{};
  return resolveSystem(systems, rulesets);
});

final systemQuickRefProvider = Provider<QuickRefCard?>(
    (ref) => kSystemQuickRefs[ref.watch(resolvedSystemProvider)]);

// -- Split view (global layout preference, not session-scoped) ---------------
class SplitViewNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.splitview.v1';
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> toggle() async {
    final next = !(state.valueOrNull ?? false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, next);
    state = AsyncData(next);
  }
}

final splitViewProvider =
    AsyncNotifierProvider<SplitViewNotifier, bool>(SplitViewNotifier.new);

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

/// Foe collections from all enabled Ironsworn-family rulesets.
/// Empty when no ironsworn-family system is active or none have NPC data.
const _kIronswornRulesets = [
  'classic',
  'starforged',
  'delve',
  'sundered_isles'
];

final foesProvider = FutureProvider<List<FoeCollection>>((ref) async {
  final systems =
      ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
          kAllSystems;
  final enabled = _kIronswornRulesets.where(systems.contains).toList();
  final results = <FoeCollection>[];
  for (final id in enabled) {
    final data = await ref.watch(rulesetDataProvider(id).future);
    final colls = (data['npc_collections'] as List?)
            ?.map(FoeCollection.fromJson)
            .whereType<FoeCollection>()
            .where((c) => c.entries.isNotEmpty)
            .toList() ??
        const <FoeCollection>[];
    results.addAll(colls);
  }
  return results;
});

/// Loads a system-specific foe file (e.g. foes_cairn.json) as a Creature list.
/// Returns empty list when the file is absent or malformed.
final systemFoesProvider =
    FutureProvider.family<List<Creature>, String>((ref, system) async {
  try {
    final raw = await rootBundle.loadString('assets/foes_$system.json');
    final list = jsonDecode(raw) as List?;
    return list?.map(Creature.maybeFromJson).whereType<Creature>().toList() ??
        const <Creature>[];
  } catch (_) {
    return const <Creature>[];
  }
});

/// Systems that ship bundled content files (foes_/spells_). Drives aggregation.
const kContentSystemsWithFiles = [
  'dnd',
  'cairn',
  'ose',
  'argosa',
  'knave',
  'dcc',
];

/// Enabled systems that also have bundled content files.
final enabledContentSystemsProvider = Provider<List<String>>((ref) {
  final systems =
      ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
          kAllSystems;
  return kContentSystemsWithFiles.where(systems.contains).toList();
});

/// Loads a system-specific spell file (e.g. spells_dnd.json). Empty on absence.
final systemSpellsProvider =
    FutureProvider.family<List<SpellEntry>, String>((ref, system) async {
  try {
    final raw = await rootBundle.loadString('assets/spells_$system.json');
    final list = jsonDecode(raw) as List?;
    return list
            ?.map(SpellEntry.maybeFromJson)
            .whereType<SpellEntry>()
            .toList() ??
        const <SpellEntry>[];
  } catch (_) {
    return const <SpellEntry>[];
  }
});

/// Active campaign's D&D SRD edition preference ("5.1" | "5.2"); null → latest.
final dndEditionProvider = Provider<String>((ref) =>
    ref.watch(sessionsProvider).valueOrNull?.activeMeta.dndEdition ?? '5.2');

/// All monsters across enabled systems: bundled creature files + Ironsworn
/// npc_collections (adapted) + the user bestiary. De-duped by id. Edition-tagged
/// entries (D&D 5.1/5.2) are filtered to the active campaign edition.
final contentMonstersProvider = FutureProvider<List<Creature>>((ref) async {
  final systems = ref.watch(enabledContentSystemsProvider);
  final ed = ref.watch(dndEditionProvider);
  final out = <String, Creature>{};
  for (final sys in systems) {
    for (final c in await ref.watch(systemFoesProvider(sys).future)) {
      out.putIfAbsent(c.id, () => c);
    }
  }
  for (final coll in await ref.watch(foesProvider.future)) {
    for (final e in coll.entries) {
      final c = foeEntryToCreature(e);
      out.putIfAbsent(c.id, () => c);
    }
  }
  for (final c
      in ref.watch(bestiaryProvider).valueOrNull ?? const <Creature>[]) {
    out.putIfAbsent(c.id, () => c);
  }
  return [
    for (final c in out.values)
      if (c.edition == null || c.edition == ed) c,
  ];
});

/// All spells across enabled systems. Edition-tagged entries (D&D 5.1/5.2) are
/// filtered to the active campaign edition.
final contentSpellsProvider = FutureProvider<List<SpellEntry>>((ref) async {
  final systems = ref.watch(enabledContentSystemsProvider);
  final ed = ref.watch(dndEditionProvider);
  final out = <String, SpellEntry>{};
  for (final sys in systems) {
    for (final s in await ref.watch(systemSpellsProvider(sys).future)) {
      out.putIfAbsent(s.id, () => s);
    }
  }
  return [
    for (final s in out.values)
      if (s.edition == null || s.edition == ed) s,
  ];
});

/// Loads the party-emulator asset (Triple-O + Pettish tables) once. Like
/// [oracleProvider], the rootBundle loads live here so lib/engine/ stays
/// Flutter-free.
final emulatorDataProvider = FutureProvider<EmulatorData>((ref) async {
  final raw = await rootBundle.loadString('assets/emulator_data.json');
  return EmulatorData(jsonDecode(raw) as Map<String, dynamic>);
});

final verdantDataProvider = FutureProvider<VerdantData>((ref) async {
  final raw = await rootBundle.loadString('assets/verdant_data.json');
  return VerdantData(jsonDecode(raw) as Map<String, dynamic>);
});

final lonelogDataProvider = FutureProvider<LonelogData>((ref) async {
  final raw = await rootBundle.loadString('assets/lonelog_data.json');
  return LonelogData(jsonDecode(raw) as Map<String, dynamic>);
});

final hexcrawlDataProvider = FutureProvider<HexcrawlData>((ref) async {
  final raw = await rootBundle.loadString('assets/hexcrawl_data.json');
  return HexcrawlData(jsonDecode(raw) as Map<String, dynamic>);
});

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
