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
}

final magicProvider =
    AsyncNotifierProvider<MagicController, pg.Library>(MagicController.new);
