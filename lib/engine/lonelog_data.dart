import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// One core symbol entry.
class LonelogSymbol {
  const LonelogSymbol(
      {required this.symbol,
      required this.name,
      required this.role,
      required this.example});
  final String symbol;
  final String name;
  final String role;
  final String example;

  static LonelogSymbol fromJson(Map<String, dynamic> j) => LonelogSymbol(
        symbol: j['symbol'] as String,
        name: j['name'] as String,
        role: j['role'] as String,
        example: j['example'] as String,
      );
}

/// One reserved tag prefix.
class LonelogPrefix {
  const LonelogPrefix(
      {required this.prefix,
      required this.name,
      required this.meaning,
      required this.source});
  final String prefix;
  final String name;
  final String meaning;
  final String source; // core | combat | dungeon | resource

  static LonelogPrefix fromJson(Map<String, dynamic> j) => LonelogPrefix(
        prefix: j['prefix'] as String,
        name: j['name'] as String,
        meaning: j['meaning'] as String,
        source: j['source'] as String,
      );
}

/// One structural block.
class LonelogBlock {
  const LonelogBlock(
      {required this.name,
      required this.openTag,
      required this.closeTag,
      required this.purpose});
  final String name;
  final String openTag;
  final String closeTag;
  final String purpose;

  static LonelogBlock fromJson(Map<String, dynamic> j) => LonelogBlock(
        name: j['name'] as String,
        openTag: j['openTag'] as String,
        closeTag: j['closeTag'] as String,
        purpose: j['purpose'] as String,
      );
}

/// One addon descriptor.
class LonelogAddon {
  const LonelogAddon(
      {required this.key,
      required this.title,
      required this.version,
      required this.summary,
      required this.status});
  final String key;
  final String title;
  final String version;
  final String summary;
  final String status; // documented | implemented

  static LonelogAddon fromJson(Map<String, dynamic> j) => LonelogAddon(
        key: j['key'] as String,
        title: j['title'] as String,
        version: j['version'] as String,
        summary: j['summary'] as String,
        status: j['status'] as String,
      );
}

/// One worked example (rendered live-highlighted).
class LonelogExample {
  const LonelogExample({required this.title, required this.lines});
  final String title;
  final List<String> lines;

  static LonelogExample fromJson(Map<String, dynamic> j) => LonelogExample(
        title: j['title'] as String,
        lines: (j['lines'] as List).cast<String>(),
      );
}

/// Typed wrapper over assets/lonelog_data.json (mirrors VerdantData).
class LonelogData {
  LonelogData(this._json);
  final Map<String, dynamic> _json;

  static Future<LonelogData> load() async {
    final raw = await rootBundle.loadString('assets/lonelog_data.json');
    return LonelogData(jsonDecode(raw) as Map<String, dynamic>);
  }

  String get version => _json['version'] as String;

  List<LonelogSymbol> get symbols => (_json['symbols'] as List)
      .map((e) => LonelogSymbol.fromJson(e as Map<String, dynamic>))
      .toList();

  List<LonelogPrefix> get tagPrefixes => (_json['tagPrefixes'] as List)
      .map((e) => LonelogPrefix.fromJson(e as Map<String, dynamic>))
      .toList();

  List<LonelogBlock> get blocks => (_json['blocks'] as List)
      .map((e) => LonelogBlock.fromJson(e as Map<String, dynamic>))
      .toList();

  List<LonelogAddon> get addons => (_json['addons'] as List)
      .map((e) => LonelogAddon.fromJson(e as Map<String, dynamic>))
      .toList();

  List<LonelogExample> get examples => (_json['examples'] as List)
      .map((e) => LonelogExample.fromJson(e as Map<String, dynamic>))
      .toList();
}
