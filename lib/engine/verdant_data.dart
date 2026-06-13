import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// One Journey Task row.
class VerdantTask {
  const VerdantTask({
    required this.name,
    required this.attribute,
    required this.types,
    required this.success,
    required this.failure,
    required this.easier,
    required this.harder,
    required this.dependency,
  });

  final String name;
  final String? attribute; // null for "Something Else"
  final List<String> types; // 'T' | 'S' | 'C'
  final String success;
  final String failure;
  final List<String> easier; // trait keys
  final List<String> harder; // trait keys
  final String? dependency;

  static VerdantTask fromJson(Map<String, dynamic> j) => VerdantTask(
        name: j['name'] as String,
        attribute: j['attribute'] as String?,
        types: (j['types'] as List).cast<String>(),
        success: j['success'] as String,
        failure: j['failure'] as String,
        easier: (j['easier'] as List).cast<String>(),
        harder: (j['harder'] as List).cast<String>(),
        dependency: j['dependency'] as String?,
      );
}

/// One terrain type.
class VerdantTerrain {
  const VerdantTerrain(
      {required this.key,
      required this.name,
      required this.traits,
      required this.special});

  final String key;
  final String name;
  final List<String> traits; // trait keys
  final String? special;

  static VerdantTerrain fromJson(Map<String, dynamic> j) => VerdantTerrain(
        key: j['key'] as String,
        name: j['name'] as String,
        traits: (j['traits'] as List).cast<String>(),
        special: j['special'] as String?,
      );
}

/// A numbered table row (Points of Interest, Quick Encounters).
class VerdantRow {
  const VerdantRow({required this.n, required this.name, required this.text});
  final int n;
  final String name;
  final String text;

  static VerdantRow fromJson(Map<String, dynamic> j) => VerdantRow(
      n: j['n'] as int, name: j['name'] as String, text: j['text'] as String);
}

/// A named text block (terrain features, transport modes).
class VerdantNote {
  const VerdantNote(
      {required this.key, required this.name, required this.text});
  final String key; // '' for terrain features
  final String name;
  final String text;
}

/// One watch in the day cycle.
class VerdantWatch {
  const VerdantWatch(
      {required this.n, required this.name, required this.night});
  final int n;
  final String name;
  final bool night;
}

/// Typed wrapper over assets/verdant_data.json (mirrors EmulatorData/OracleData).
class VerdantData {
  VerdantData(this._json);

  final Map<String, dynamic> _json;

  static Future<VerdantData> load() async {
    final raw = await rootBundle.loadString('assets/verdant_data.json');
    return VerdantData(jsonDecode(raw) as Map<String, dynamic>);
  }

  Map<String, dynamic> get _c => _json['constants'] as Map<String, dynamic>;

  Map<String, String> get traits =>
      (_json['traits'] as Map).cast<String, String>();
  String traitName(String key) => traits[key] ?? key;

  List<VerdantTask> get tasks => (_json['journey_tasks'] as List)
      .map((e) => VerdantTask.fromJson(e as Map<String, dynamic>))
      .toList();

  List<VerdantTerrain> get terrain => (_json['terrain'] as List)
      .map((e) => VerdantTerrain.fromJson(e as Map<String, dynamic>))
      .toList();

  List<VerdantRow> get pointsOfInterest => (_json['points_of_interest'] as List)
      .map((e) => VerdantRow.fromJson(e as Map<String, dynamic>))
      .toList();

  List<VerdantRow> get quickEncounters => (_json['quick_encounters'] as List)
      .map((e) => VerdantRow.fromJson(e as Map<String, dynamic>))
      .toList();

  List<VerdantNote> get terrainFeatures => (_json['terrain_features'] as List)
      .map((e) => VerdantNote(
          key: '',
          name: (e as Map)['name'] as String,
          text: e['text'] as String))
      .toList();

  List<VerdantNote> get transportModes => (_json['transport_modes'] as List)
      .map((e) => VerdantNote(
          key: (e as Map)['key'] as String,
          name: e['name'] as String,
          text: e['text'] as String))
      .toList();

  List<VerdantWatch> get watches => (_c['watches'] as List)
      .map((e) => VerdantWatch(
          n: (e as Map)['n'] as int,
          name: e['name'] as String,
          night: e['night'] as bool))
      .toList();

  int get erBase => _c['erBase'] as int;
  int get safer => _c['safer'] as int;
  int get riskier => _c['riskier'] as int;
  int get deadly => _c['deadly'] as int;
  int get paceSlow => (_c['pace'] as Map)['slow'] as int;
  int get paceFast => (_c['pace'] as Map)['fast'] as int;

  VerdantTerrain? terrainByKey(String key) {
    for (final t in terrain) {
      if (t.key == key) return t;
    }
    return null;
  }
}
