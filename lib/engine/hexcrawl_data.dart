import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class HexTerrain {
  const HexTerrain(
      {required this.key,
      required this.name,
      required this.climates,
      required this.difficulty,
      required this.travelNote,
      required this.features});
  final String key;
  final String name;
  final List<String> climates;
  final int difficulty;
  final String travelNote;
  final List<String> features;

  static HexTerrain fromJson(Map<String, dynamic> j) => HexTerrain(
        key: j['key'] as String,
        name: j['name'] as String,
        climates: (j['climates'] as List).cast<String>(),
        difficulty: j['difficulty'] as int,
        travelNote: (j['travelNote'] as String?) ?? '',
        features: (j['features'] as List).cast<String>(),
      );
}

/// A weighted terrain row in a climate/neighbouring table.
class WeightedTerrain {
  const WeightedTerrain(this.terrain, this.weight);
  final String terrain;
  final int weight;

  static WeightedTerrain fromJson(Map<String, dynamic> j) =>
      WeightedTerrain(j['terrain'] as String, j['weight'] as int);
}

/// Typed wrapper over assets/hexcrawl_data.json (mirrors VerdantData).
class HexcrawlData {
  HexcrawlData(this._json);
  final Map<String, dynamic> _json;

  static Future<HexcrawlData> load() async {
    final raw = await rootBundle.loadString('assets/hexcrawl_data.json');
    return HexcrawlData(jsonDecode(raw) as Map<String, dynamic>);
  }

  List<String> get climates => (_json['climates'] as List).cast<String>();

  List<HexTerrain> get terrains => (_json['terrains'] as List)
      .map((e) => HexTerrain.fromJson(e as Map<String, dynamic>))
      .toList();

  HexTerrain? terrainByKey(String key) {
    for (final t in terrains) {
      if (t.key == key) return t;
    }
    return null;
  }

  Map<String, List<WeightedTerrain>> _weightedMap(String field) =>
      (_json[field] as Map).map((k, v) => MapEntry(
            k as String,
            (v as List)
                .map((e) => WeightedTerrain.fromJson(e as Map<String, dynamic>))
                .toList(),
          ));

  Map<String, List<WeightedTerrain>> get climateToTerrain =>
      _weightedMap('climateToTerrain');
  Map<String, List<WeightedTerrain>> get neighbouringTerrain =>
      _weightedMap('neighbouringTerrain');

  List<String> _flat(String field) => (_json[field] as List).cast<String>();
  List<String> get weather => _flat('weather');
  List<String> get hazards => _flat('hazards');
  List<String> get siteTypes => _flat('siteTypes');
  List<String> get regionFeatures => _flat('regionFeatures');
  List<String> get encounterCategories => _flat('encounterCategories');
}
