import 'package:polarity_grammar/polarity_grammar.dart' as pg;
import 'package:shared_preferences/shared_preferences.dart';

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
