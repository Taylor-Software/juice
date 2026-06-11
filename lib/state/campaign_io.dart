import 'dart:convert';

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
  return CampaignImport(
    name: (decoded['name'] as String?)?.trim().isNotEmpty == true
        ? (decoded['name'] as String).trim()
        : 'Imported campaign',
    rawByKey: {
      for (final key in sessionScopedKeys)
        if (data.containsKey(key)) key: jsonEncode(data[key]),
    },
  );
}
