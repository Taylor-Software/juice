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

/// Sidekick dialogue mood ids in printed order; the mood-change d6 maps
/// 1..6 onto this list.
const List<String> kSidekickMoods = [
  'default',
  'taciturn',
  'savvy',
  'high_strung',
  'sassy',
  'selfish',
];

/// One sidekick.hexflower hex: axial coords plus the conversation topic and
/// context color ('gray' = history, 'red' = current events).
class HexInfo {
  const HexInfo({
    required this.index,
    required this.q,
    required this.r,
    required this.topic,
    required this.context,
  });

  final int index;
  final int q;
  final int r;
  final String topic;
  final String context;
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

  Map<String, dynamic> get _sidekick =>
      _json['sidekick'] as Map<String, dynamic>;

  /// Dialogue mood ids in printed order (see [kSidekickMoods]).
  List<String> get moods => kSidekickMoods;

  /// Dialogue line for [mood] at 2d6 [key] (2..12); ArgumentError outside.
  String dialogueLine(String mood, int key) {
    final table = (_sidekick['dialogue'] as Map<String, dynamic>)[mood];
    if (table == null) throw ArgumentError('unknown mood: $mood');
    final line = (table as Map<String, dynamic>)['$key'];
    if (line == null) throw ArgumentError('bad dialogue key: $key');
    return line as String;
  }

  List<String> _sidekickList(String key) =>
      (_sidekick[key] as List).cast<String>();

  /// The six tone chips (d6 order).
  List<String> get tones => _sidekickList('tone');

  /// The six topic chips (d6 order).
  List<String> get topics => _sidekickList('topic');

  /// The six "said how" first-word chips (d6 order).
  List<String> get saidHowA => _sidekickList('said_how_a');

  /// The six "said how" second-word chips (d6 order).
  List<String> get saidHowB => _sidekickList('said_how_b');

  Map<String, dynamic> get _hexflower =>
      _sidekick['hexflower'] as Map<String, dynamic>;

  List<Map<String, dynamic>> get _hexes =>
      (_hexflower['hexes'] as List).cast<Map<String, dynamic>>();

  /// Hexflower hex [index] (0..18); ArgumentError outside.
  HexInfo hex(int index) {
    final hexes = _hexes;
    if (index < 0 || index >= hexes.length) {
      throw ArgumentError('bad hex index: $index');
    }
    final h = hexes[index];
    return HexInfo(
      index: h['index'] as int,
      q: h['q'] as int,
      r: h['r'] as int,
      topic: h['topic'] as String,
      context: h['context'] as String,
    );
  }

  /// Neighbor indices of hex [index], from the asset's adjacency map.
  List<int> hexNeighbors(int index) {
    final adj = (_hexflower['adjacency'] as Map<String, dynamic>)['$index'];
    if (adj == null) throw ArgumentError('bad hex index: $index');
    return (adj as List).cast<int>();
  }

  /// Direction ('N'|'NE'|'SE'|'S'|'SW'|'NW') for a 2d6 sum (2..12), per the
  /// overlay rose around the flower.
  String hexDirection(int key2d6) {
    final dir = (_hexflower['directions'] as Map<String, dynamic>)['$key2d6'];
    if (dir == null) throw ArgumentError('bad direction key: $key2d6');
    return dir as String;
  }

  /// The hex one step from [from] toward [key2d6]'s direction (the asset's
  /// direction_deltas applied to axial q/r); null when the step leaves the
  /// flower (UI: stay put).
  int? hexStep(int from, int key2d6) {
    final delta = (_hexflower['direction_deltas']
        as Map<String, dynamic>)[hexDirection(key2d6)] as List;
    final h = hex(from);
    final q = h.q + (delta[0] as int);
    final r = h.r + (delta[1] as int);
    for (final cell in _hexes) {
      if (cell['q'] == q && cell['r'] == r) return cell['index'] as int;
    }
    return null;
  }

  /// License attribution lines, displayed in the Party tools.
  List<String> get attribution =>
      ((_json['meta'] as Map<String, dynamic>)['attribution'] as List)
          .cast<String>();
}
