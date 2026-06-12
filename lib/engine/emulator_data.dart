import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Parsed view over assets/emulator_data.json (emitted by build_emulator.py:
/// Triple-O spark/specific d66 tables + Pettish PET/Sidekick data).
class EmulatorData {
  EmulatorData(this._json);

  final Map<String, dynamic> _json;

  static Future<EmulatorData> load() async {
    final raw = await rootBundle.loadString('assets/emulator_data.json');
    return EmulatorData(jsonDecode(raw) as Map<String, dynamic>);
  }

  Map<String, dynamic> get _tripleO =>
      _json['triple_o'] as Map<String, dynamic>;

  /// Spark table names in zine order (action..dynamics).
  List<String> get sparkNames =>
      (_tripleO['spark_order'] as List).cast<String>();

  /// Specific table names in zine order (combat..planning).
  List<String> get specificNames =>
      (_tripleO['specific_order'] as List).cast<String>();

  Map<int, String> _d66(String section, String name) {
    final table = (_tripleO[section] as Map<String, dynamic>)[name];
    if (table == null) {
      throw ArgumentError('unknown $section table: $name');
    }
    return (table as Map<String, dynamic>)
        .map((k, v) => MapEntry(int.parse(k), v as String));
  }

  /// A spark d66 table by name; keys 11..66.
  Map<int, String> sparkTable(String name) => _d66('spark', name);

  /// A specific d66 table by name; keys 11..66.
  Map<int, String> specificTable(String name) => _d66('specific', name);

  /// Entry [key] (11..66) of the named spark or specific table.
  String d66Entry(String table, int key) {
    final cells =
        sparkNames.contains(table) ? sparkTable(table) : specificTable(table);
    final text = cells[key];
    if (text == null) {
      throw ArgumentError('bad d66 key for $table: $key');
    }
    return text;
  }

  /// License attribution lines, displayed in the Party tools.
  List<String> get attribution =>
      ((_json['meta'] as Map<String, dynamic>)['attribution'] as List)
          .cast<String>();
}
