import 'dart:convert';

import '../engine/models.dart';
import 'providers.dart' show sessionScopedKeys;

/// Campaign file format version this build writes and the max it reads.
const campaignSchemaVersion = 3;

const _appMarker = 'juice-oracle';

/// Parsed campaign file: session name + raw JSON string per base key,
/// ready to write into session-scoped SharedPreferences entries.
class CampaignImport {
  const CampaignImport({
    required this.name,
    required this.rawByKey,
    this.systems,
    this.mode = CampaignMode.party,
    this.genre,
  });
  final String name;
  final Map<String, String> rawByKey;

  /// Enabled optional systems; null means "all" (the default profile).
  final List<String>? systems;
  final CampaignMode mode;

  /// Display genre/mood mirrored from the campaign's settings store; null/empty
  /// when absent. The interpreter's source of truth stays CampaignSettings.
  final String? genre;
}

/// Encode a campaign to the .juice.json file content.
/// [rawByKey] holds the stores' persisted JSON strings by base key;
/// null/absent stores are omitted. [systems]/[mode] carry the campaign
/// profile so an import restores it (additive keys — older readers ignore them).
String encodeCampaign({
  required String name,
  required DateTime savedAt,
  required Map<String, String> rawByKey,
  List<String>? systems,
  CampaignMode mode = CampaignMode.party,
}) {
  return const JsonEncoder.withIndent('  ').convert({
    'app': _appMarker,
    'schemaVersion': campaignSchemaVersion,
    'savedAt': savedAt.toIso8601String(),
    'name': name,
    if (systems != null) 'systems': systems,
    'mode': mode.name,
    'data': {
      for (final e in rawByKey.entries) e.key: jsonDecode(e.value),
    },
  });
}

/// Parse and validate a campaign file. Throws [FormatException] with a
/// user-readable message on anything invalid.
CampaignImport parseCampaign(String raw) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw const FormatException('Not a JSON file');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Not a campaign file');
  }
  if (decoded['app'] != _appMarker) {
    throw const FormatException(
        "Not a Solo Adventurer's Journal campaign file");
  }
  final version = decoded['schemaVersion'];
  if (version is! int || version > campaignSchemaVersion) {
    throw FormatException(
        'Campaign file version $version is newer than this app supports');
  }
  final data = decoded['data'];
  if (data is! Map<String, dynamic>) {
    throw const FormatException('Campaign file has no data section');
  }
  final rawByKey = <String, String>{};
  String? genre;
  for (final key in sessionScopedKeys) {
    if (!data.containsKey(key)) continue;
    final value = data[key];
    try {
      if (key == 'juice.journal.v2') {
        (value as List)
            .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (key == 'juice.threads.v1') {
        (value as List)
            .map((e) => Thread.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (key == 'juice.characters.v1') {
        (value as List)
            .map((e) => Character.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (key == 'juice.crawl.v1') {
        CrawlState.fromJson(value as Map<String, dynamic>);
      } else if (key == 'juice.encounter.v1') {
        EncounterState.fromJson(value as Map<String, dynamic>);
      } else if (key == 'juice.map.v1') {
        MapState.fromJson(value as Map<String, dynamic>);
      } else if (key == 'juice.rumors.v1') {
        (value as List)
            .map((e) => Rumor.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (key == 'juice.tracks.v1') {
        (value as List)
            .map((e) => Track.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (key == 'juice.inventory.v1') {
        (value as List)
            .map((e) => InvItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (key == 'juice.units.v1') {
        (value as List)
            .map((e) => Unit.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (key == 'juice.settings.v1') {
        final settings =
            CampaignSettings.fromJson(value as Map<String, dynamic>);
        if (settings.genre.isNotEmpty) genre = settings.genre;
      }
    } catch (_) {
      throw const FormatException('Campaign file data is malformed');
    }
    rawByKey[key] = jsonEncode(value);
  }
  final rawName = decoded['name'];
  final rawSystems = decoded['systems'];
  return CampaignImport(
    name: rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : 'Imported campaign',
    rawByKey: rawByKey,
    systems:
        rawSystems is List ? rawSystems.whereType<String>().toList() : null,
    mode: decoded['mode'] == 'gm' ? CampaignMode.gm : CampaignMode.party,
    genre: genre,
  );
}
