import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Parsed view over assets/oracle_data.json (emitted by build_oracle.py).
class OracleData {
  OracleData(this._json);

  final Map<String, dynamic> _json;

  static Future<OracleData> load() async {
    final raw = await rootBundle.loadString('assets/oracle_data.json');
    return OracleData(jsonDecode(raw) as Map<String, dynamic>);
  }

  Map<String, dynamic> get _tables => _json['tables'] as Map<String, dynamic>;

  /// A simple d10 table (10 string entries) by key.
  List<String> table(String key) =>
      (_tables[key] as List).cast<String>();

  /// Intensity (6 entries).
  List<String> get intensity => table('intensity');

  // Treasure -------------------------------------------------------------
  List<String> get treasureCategories =>
      (_treasure['categories'] as List).cast<String>();
  Map<String, dynamic> get _treasure =>
      _json['treasure'] as Map<String, dynamic>;
  Map<String, dynamic> treasureSub(String category) =>
      (_treasure['sub'] as Map<String, dynamic>)[category]
          as Map<String, dynamic>;

  // Discover meaning -----------------------------------------------------
  List<String> get discoverVerb =>
      ((_json['discover'] as Map)['verb'] as List).cast<String>();
  List<String> get discoverSubject =>
      ((_json['discover'] as Map)['subject'] as List).cast<String>();

  // Name generator -------------------------------------------------------
  List<String> get nameStart =>
      ((_json['name'] as Map)['start'] as List).cast<String>();
  List<String> get nameMid =>
      ((_json['name'] as Map)['mid'] as List).cast<String>();
  List<String> get nameEnd =>
      ((_json['name'] as Map)['end'] as List).cast<String>();

  // Extended NPC d100 tables: list of [maxRoll, text] ---------------------
  List<List<dynamic>> ext(String key) =>
      ((_json['ext'] as Map)[key] as List)
          .map((e) => (e as List))
          .toList();

  // Monster encounter ------------------------------------------------------
  Map<String, dynamic> get _monster =>
      _json['monster_encounter'] as Map<String, dynamic>;

  /// Row key ('1'..'0', '*', '**') -> 5 cells (tracks, easy, medium, hard, boss).
  Map<String, List<String>> get monsterGrid =>
      (_monster['grid'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as List).cast<String>()));

  /// Env row '1'..'10' -> [modifier, skew].
  Map<String, List<int>> get monsterEnvFormula =>
      (_monster['env_formula'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as List).cast<int>()));

  // NPC dialog ---------------------------------------------------------------
  Map<String, dynamic> get _dialog => _json['dialog'] as Map<String, dynamic>;

  /// 5x5 fragment grid; rows 0-1 are past tense.
  List<List<String>> get dialogGrid => (_dialog['grid'] as List)
      .map((r) => (r as List).cast<String>())
      .toList();

  /// [maxRoll, tone, dRow, dCol] bands for die 1.
  List<List<dynamic>> get dialogDirection =>
      (_dialog['direction'] as List).map((e) => e as List).toList();

  /// [maxRoll, subject] bands for die 2.
  List<List<dynamic>> get dialogSubject =>
      (_dialog['subject'] as List).map((e) => e as List).toList();

  // Mythic GME 2e --------------------------------------------------------
  Map<String, dynamic> get _mythic => _json['mythic'] as Map<String, dynamic>;

  /// Odds labels, Certain..Impossible.
  List<String> get mythicOdds =>
      (_mythic['odds'] as List).cast<String>();

  /// 17-entry threshold ladder of [excYesMax, target, excNoMin]; cell for
  /// (oddsIndex, chaos) is index `9 - chaos + oddsIndex`.
  List<List<int>> get mythicBands => (_mythic['bands'] as List)
      .map((e) => (e as List).cast<int>())
      .toList();

  /// [maxRoll, label, listTarget|null] event focus ranges.
  List<List<dynamic>> get mythicEventFocus =>
      (_mythic['event_focus'] as List).map((e) => e as List).toList();

  /// All raw table keys (for the browse screen), sorted.
  List<String> get allTableKeys =>
      _tables.keys.where((k) => k != 'intensity').toList()..sort();
}
