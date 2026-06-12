import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// One pet.agenda row (keys 2..12): a named agenda in one of six groups,
/// with the Ask question ACT poses and the zine's flavor text.
class AgendaEntry {
  const AgendaEntry({
    required this.key,
    required this.group,
    required this.name,
    required this.ask,
    required this.flavor,
  });

  final int key;
  final String group;
  final String name;
  final String ask;
  final String flavor;
}

/// One pet.focus row (keys 2..12): a focus name and its description.
class FocusEntry {
  const FocusEntry(
      {required this.key, required this.name, required this.blurb});

  final int key;
  final String name;
  final String blurb;
}

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

  Map<String, dynamic> get _pet => _json['pet'] as Map<String, dynamic>;

  Map<String, dynamic> _petRow(String table, int key) {
    final row = (_pet[table] as Map<String, dynamic>)['$key'];
    if (row == null) throw ArgumentError('bad $table key: $key');
    return row as Map<String, dynamic>;
  }

  /// Agenda row [key] (2..12); ArgumentError outside.
  AgendaEntry agendaEntry(int key) {
    final row = _petRow('agenda', key);
    return AgendaEntry(
      key: key,
      group: row['group'] as String,
      name: row['name'] as String,
      ask: row['ask'] as String,
      flavor: row['flavor'] as String,
    );
  }

  /// Focus row [key] (2..12); ArgumentError outside.
  FocusEntry focusEntry(int key) {
    final row = _petRow('focus', key);
    return FocusEntry(
      key: key,
      name: row['name'] as String,
      blurb: row['blurb'] as String,
    );
  }

  /// The 36 PET personality tags (column-major zine order).
  List<String> get personalityTags =>
      (_pet['personality_tags'] as List).cast<String>();

  /// The six PET consequences / GM moves (d6 order).
  List<String> get consequences =>
      (_pet['consequences'] as List).cast<String>();

  /// The six PET real-life events for session start (d6 order).
  List<String> get realLife => (_pet['real_life'] as List).cast<String>();

  /// License attribution lines, displayed in the Party tools.
  List<String> get attribution =>
      ((_json['meta'] as Map<String, dynamic>)['attribution'] as List)
          .cast<String>();
}
