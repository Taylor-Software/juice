import 'dart:convert';

import '../engine/models.dart';
import 'providers.dart' show sessionScopedKeys;

/// Campaign file format version this build writes and the max it reads.
const campaignSchemaVersion = 1;

const _appMarker = 'juice-oracle';

/// Parsed campaign file: session name + raw JSON string per base key,
/// ready to write into session-scoped SharedPreferences entries.
class CampaignImport {
  const CampaignImport({required this.name, required this.rawByKey});
  final String name;
  final Map<String, String> rawByKey;
}

/// Encode a campaign to the .juice.json file content.
/// [rawByKey] holds the stores' persisted JSON strings by base key;
/// null/absent stores are omitted.
String encodeCampaign({
  required String name,
  required DateTime savedAt,
  required Map<String, String> rawByKey,
}) {
  return const JsonEncoder.withIndent('  ').convert({
    'app': _appMarker,
    'schemaVersion': campaignSchemaVersion,
    'savedAt': savedAt.toIso8601String(),
    'name': name,
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
    throw const FormatException('Not a Juice Oracle campaign file');
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
  for (final key in sessionScopedKeys) {
    if (!data.containsKey(key)) continue;
    final value = data[key];
    try {
      if (key == 'juice.log.v1') {
        (value as List)
            .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
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
      }
    } catch (_) {
      throw const FormatException('Campaign file data is malformed');
    }
    rawByKey[key] = jsonEncode(value);
  }
  return CampaignImport(
    name: (decoded['name'] as String?)?.trim().isNotEmpty == true
        ? (decoded['name'] as String).trim()
        : 'Imported campaign',
    rawByKey: rawByKey,
  );
}
