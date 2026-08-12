import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polarity_grammar/polarity_grammar.dart' as pg;
import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart' show sessionsProvider, prefsProvider;

/// [pg.PolarityStore] over [SharedPreferences], scoped to one campaign
/// session — mirrors the `<base>.<sessionId>` convention every other
/// per-campaign store in this app uses. The package's [pg.TextLibraryStore]
/// already owns JSON (de)serialization, corrupt-data quarantine, and
/// schema-too-new handling; this adapter only supplies raw string IO.
class JuiceMagicStore extends pg.TextLibraryStore {
  JuiceMagicStore(this._prefs, String sessionId)
      : _key = 'loreseer.magic.v1.$sessionId';

  final SharedPreferences _prefs;
  final String _key;

  String _quarantineKey(int i) => '$_key.quarantine.$i';

  @override
  Future<String?> readRaw() async => _prefs.getString(_key);

  @override
  Future<void> writeRaw(String data) async {
    await _prefs.setString(_key, data);
  }

  @override
  Future<void> quarantineRaw(String data) async {
    // Rotate the kQuarantineKeep (3) slots — oldest ages out, newest at [0]
    // — so a fresh corruption is always recoverable without unbounded growth.
    for (var i = pg.kQuarantineKeep - 1; i > 0; i--) {
      final prev = _prefs.getString(_quarantineKey(i - 1));
      if (prev != null) await _prefs.setString(_quarantineKey(i), prev);
    }
    await _prefs.setString(_quarantineKey(0), data);
  }
}

/// Riverpod front for the [pg.Library] — one instance per campaign session
/// (rebuilt on session switch since [build] watches [sessionsProvider]).
/// Owns core CRUD (this task); Task 5 adds casting/rest/hanging/running.
class MagicController extends AsyncNotifier<pg.Library> {
  late JuiceMagicStore _store;

  @override
  Future<pg.Library> build() async {
    final sessions = await ref.watch(sessionsProvider.future);
    final prefs = await ref.read(prefsProvider.future);
    _store = JuiceMagicStore(prefs, sessions.active);
    return _store.load();
  }

  pg.Library get _lib => state.valueOrNull ?? const pg.Library.empty();

  Future<void> _commit(pg.Library next) async {
    // Update in-memory state before the async persist so a rapid second
    // mutation (fired during this persist) reads the new library, not the
    // stale one — mirrors DecksNotifier._save.
    state = AsyncData(next);
    await _store.save(next);
  }

  /// Monotonic counter behind [_freshId] — a timestamp alone can collide if
  /// two ids are minted in the same microsecond.
  int _idSeq = 0;

  String _freshId(String kind, DateTime at) =>
      '$kind-${at.microsecondsSinceEpoch}-${_idSeq++}';

  /// The character list with [c] swapped in at its existing position
  /// (appended if new).
  List<pg.Character> _withCharacter(List<pg.Character> chars, pg.Character c) {
    final i = chars.indexWhere((x) => x.id == c.id);
    if (i < 0) return [...chars, c];
    final next = [...chars];
    next[i] = c;
    return next;
  }

  pg.Character? _byId(String id) {
    for (final c in _lib.characters) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> upsertCharacter(pg.Character c) async {
    await _commit(
        _lib.copyWith(characters: _withCharacter(_lib.characters, c)));
  }

  Future<void> deleteCharacter(String id) async {
    await _commit(_lib.copyWith(
      characters: _lib.characters.where((c) => c.id != id).toList(),
      spells: _lib.spells.where((s) => s.characterId != id).toList(),
      history: _lib.history.where((h) => h.characterId != id).toList(),
      hanging: _lib.hanging.where((h) => h.characterId != id).toList(),
      running: _lib.running.where((r) => r.characterId != id).toList(),
    ));
  }

  Future<void> setMana(String characterId, int value) async {
    final c = _byId(characterId);
    if (c == null) return;
    await upsertCharacter(
        c.copyWith(currentMana: value.clamp(0, c.availableMana)));
  }

  Future<void> upsertSpell(pg.Spell s) async {
    final rest = _lib.spells.where((x) => x.id != s.id).toList();
    await _commit(_lib.copyWith(spells: [...rest, s]));
  }

  Future<void> deleteSpell(String id) async {
    await _commit(
        _lib.copyWith(spells: _lib.spells.where((s) => s.id != id).toList()));
  }

  Future<void> toggleFavorite(pg.Spell s) =>
      upsertSpell(s.copyWith(favorite: !s.favorite, editedAt: DateTime.now()));

  Future<void> duplicateSpell(pg.Spell s) async {
    final now = DateTime.now();
    await upsertSpell(s.copyWith(
      id: _freshId('spell', now),
      name: '${s.name} (copy)',
      favorite: false,
      editedAt: now,
    ));
  }

  /// Copies the sample spellbook into [characterId] with fresh ids —
  /// additive and repeatable, mirrors the standalone app's "Load samples".
  Future<List<pg.Spell>> loadSamples(String characterId) async {
    final school = _byId(characterId)?.school;
    final source =
        school == null ? pg.kSampleSpells : pg.kSampleSpellsBySchool[school]!;
    final now = DateTime.now();
    final added = <pg.Spell>[
      for (final s in source)
        s.copyWith(
            id: _freshId('spell', now),
            characterId: characterId,
            editedAt: now),
    ];
    await _commit(_lib.copyWith(spells: [..._lib.spells, ...added]));
    return added;
  }

  /// Keep each character's cast log bounded (per character, not per
  /// library — a shared cap would let a busy caster evict someone else's
  /// log).
  static const _kMaxHistory = 200;
  static const _kMaxRunning = 30;

  List<pg.CastRecord> _capped(List<pg.CastRecord> history, String characterId) {
    final mine = [
      for (final h in history)
        if (h.characterId == characterId) h
    ];
    if (mine.length <= _kMaxHistory) return history;
    final drop = {for (final h in mine.take(mine.length - _kMaxHistory)) h.id};
    return [
      for (final h in history)
        if (!drop.contains(h.id)) h
    ];
  }

  List<pg.RunningSpell> _cappedRunning(
      List<pg.RunningSpell> running, String characterId) {
    final mine = [
      for (final r in running)
        if (r.characterId == characterId) r
    ];
    if (mine.length <= _kMaxRunning) return running;
    final drop = {for (final r in mine.take(mine.length - _kMaxRunning)) r.id};
    return [
      for (final r in running)
        if (!drop.contains(r.id)) r
    ];
  }

  /// Deducts cost and appends a history record of the spell AS CAST. A
  /// Triggered cast also hangs (oldest over the Spell Level cap silently
  /// defuses); a duration cast joins the running list. Returns what
  /// [undoCast] needs.
  Future<
      ({
        int refund,
        String recordId,
        String? hangingId,
        String? runningId,
        List<pg.HangingSpell> defused,
      })> cast(pg.Spell s, {String? trigger}) async {
    final c = _byId(s.characterId);
    if (c == null) {
      return (
        refund: 0,
        recordId: '',
        hangingId: null,
        runningId: null,
        defused: const <pg.HangingSpell>[],
      );
    }
    final before = c.currentMana;
    final now = DateTime.now();
    final record = pg.CastRecord(
      id: _freshId('cast', now),
      characterId: s.characterId,
      spellName: s.name,
      incantation: pg.incantation(s),
      cost: pg.spellCost(s),
      at: now,
      spellId: s.id,
      spell: s,
    );
    final history = _capped([..._lib.history, record], s.characterId);
    var hanging = _lib.hanging;
    String? hangingId;
    var defused = const <pg.HangingSpell>[];
    if (pg.requiresTrigger(s)) {
      final mine = [
        for (final h in hanging)
          if (h.characterId == s.characterId) h
      ];
      final overflow = mine.length - c.spellLevel + 1;
      if (overflow > 0) {
        defused = mine.take(overflow).toList();
        final drop = {for (final h in defused) h.id};
        hanging = [
          for (final h in hanging)
            if (!drop.contains(h.id)) h
        ];
      }
      hangingId = _freshId('hang', now);
      hanging = [
        ...hanging,
        pg.HangingSpell(
          id: hangingId,
          characterId: s.characterId,
          spellName: s.name,
          incantation: pg.incantation(s),
          cost: pg.spellCost(s),
          trigger: trigger ?? '',
          at: now,
          spell: s,
        ),
      ];
    }
    var running = _lib.running;
    String? runningId;
    if (pg.hasDuration(s)) {
      runningId = _freshId('run', now);
      running = _cappedRunning([
        ...running,
        pg.RunningSpell(
          id: runningId,
          characterId: s.characterId,
          spellName: s.name,
          incantation: pg.incantation(s),
          cost: pg.spellCost(s),
          timing: s.timing,
          at: now,
          spell: s,
        ),
      ], s.characterId);
    }
    final spells = [
      for (final t in _lib.spells)
        if (t.id == s.id) t.copyWith(castCount: t.castCount + 1) else t,
    ];
    final after = (before - pg.spellCost(s)).clamp(0, c.availableMana);
    await _commit(_lib.copyWith(
      characters:
          _withCharacter(_lib.characters, c.copyWith(currentMana: after)),
      spells: spells,
      history: history,
      hanging: hanging,
      running: running,
    ));
    return (
      refund: before - after,
      recordId: record.id,
      hangingId: hangingId,
      runningId: runningId,
      defused: defused,
    );
  }

  /// Undo a cast: refund what it deducted and drop its history record (plus
  /// un-hang/un-run/re-hang-defused as applicable).
  Future<void> undoCast(
    String characterId,
    int refund,
    String recordId, {
    String? hangingId,
    String? runningId,
    List<pg.HangingSpell> defused = const [],
  }) async {
    final c = _byId(characterId);
    if (c == null) return;
    final hanging = [
      for (final h in _lib.hanging)
        if (h.id != hangingId) h,
      ...defused,
    ]..sort((a, b) => a.at.compareTo(b.at));
    String? spellId;
    for (final h in _lib.history) {
      if (h.id == recordId) spellId = h.spellId;
    }
    final spells = [
      for (final t in _lib.spells)
        if (t.id == spellId && t.castCount > 0)
          t.copyWith(castCount: t.castCount - 1)
        else
          t,
    ];
    await _commit(_lib.copyWith(
      characters: _withCharacter(
          _lib.characters,
          c.copyWith(
              currentMana: (c.currentMana + refund).clamp(0, c.availableMana))),
      spells: spells,
      history: _lib.history.where((h) => h.id != recordId).toList(),
      hanging: hanging,
      running: _lib.running.where((r) => r.id != runningId).toList(),
    ));
  }

  /// Refills to max and logs a session-boundary marker. Returns what
  /// [undoRest] needs.
  Future<({int before, String recordId})> rest(String characterId) async {
    final c = _byId(characterId);
    if (c == null) return (before: 0, recordId: '');
    final now = DateTime.now();
    final record = pg.CastRecord(
      id: _freshId('rest', now),
      characterId: characterId,
      spellName: 'Rest',
      incantation: '',
      cost: 0,
      at: now,
      kind: pg.CastKind.rest,
    );
    final history = _capped([..._lib.history, record], characterId);
    await _commit(_lib.copyWith(
      characters: _withCharacter(
          _lib.characters, c.copyWith(currentMana: c.availableMana)),
      history: history,
    ));
    return (before: c.currentMana, recordId: record.id);
  }

  Future<void> undoRest(String characterId, int before, String recordId) async {
    final c = _byId(characterId);
    if (c == null) return;
    await _commit(_lib.copyWith(
      characters: _withCharacter(_lib.characters,
          c.copyWith(currentMana: before.clamp(0, c.availableMana))),
      history: _lib.history.where((h) => h.id != recordId).toList(),
    ));
  }

  Future<void> dismissHanging(String id) async {
    await _commit(
        _lib.copyWith(hanging: _lib.hanging.where((h) => h.id != id).toList()));
  }

  Future<void> restoreHanging(List<pg.HangingSpell> records) async {
    final merged = [..._lib.hanging, ...records]
      ..sort((a, b) => a.at.compareTo(b.at));
    await _commit(_lib.copyWith(hanging: merged));
  }

  Future<void> endRunning(String id) async {
    await _commit(
        _lib.copyWith(running: _lib.running.where((r) => r.id != id).toList()));
  }

  Future<void> restoreRunning(List<pg.RunningSpell> records) async {
    final merged = [..._lib.running, ...records]
      ..sort((a, b) => a.at.compareTo(b.at));
    await _commit(_lib.copyWith(running: merged));
  }

  Future<List<pg.CastRecord>> clearHistory(String characterId) async {
    final removed =
        _lib.history.where((h) => h.characterId == characterId).toList();
    await _commit(_lib.copyWith(
      history: _lib.history.where((h) => h.characterId != characterId).toList(),
    ));
    return removed;
  }

  Future<void> restoreHistory(List<pg.CastRecord> records) async {
    final merged = [..._lib.history, ...records]
      ..sort((a, b) => a.at.compareTo(b.at));
    await _commit(_lib.copyWith(history: merged));
  }

  Future<void> toggleAdjusted(String recordId) async {
    await _commit(_lib.copyWith(
      history: [
        for (final h in _lib.history)
          if (h.id == recordId) h.copyWith(adjusted: !h.adjusted) else h,
      ],
    ));
  }
}

final magicProvider =
    AsyncNotifierProvider<MagicController, pg.Library>(MagicController.new);
