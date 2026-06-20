import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A campaign export that bundles the JSON state plus the binary blobs it
/// references (annotation background images) into a single zip, so annotations
/// travel with the campaign instead of being left device-local. See
/// `docs/superpowers/specs/2026-06-19-pdf-annotation-blob-store-design.md` (B0b).
class CampaignBundle {
  const CampaignBundle({required this.campaignJson, required this.blobs});

  /// The campaign file JSON (same content as a plain `.juice.json` export).
  final String campaignJson;

  /// Referenced blobs, keyed by blob id (the id carries its extension).
  final Map<String, Uint8List> blobs;
}

const _campaignEntry = 'campaign.json';
const _blobDir = 'blobs/';

/// Zip the campaign JSON + its blobs into `.juice.zip` bytes.
Uint8List encodeCampaignBundle(
    String campaignJson, Map<String, Uint8List> blobs) {
  final archive = Archive()
    ..addFile(ArchiveFile.string(_campaignEntry, campaignJson));
  for (final e in blobs.entries) {
    archive.addFile(ArchiveFile.bytes('$_blobDir${e.key}', e.value));
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Decode `.juice.zip` bytes into a [CampaignBundle], or null when [bytes] is
/// not a campaign zip (no zip magic, undecodable, or missing `campaign.json`) —
/// callers fall back to treating the bytes as a plain `.juice.json` string.
CampaignBundle? decodeCampaignBundle(List<int> bytes) {
  // Zip local-file-header magic: 'PK\x03\x04'.
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) return null;
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return null;
  }
  String? json;
  final blobs = <String, Uint8List>{};
  for (final f in archive.files) {
    if (f.name.endsWith('/')) continue; // directory entry
    final content = f.readBytes();
    if (content == null) continue;
    if (f.name == _campaignEntry) {
      json = utf8.decode(content);
    } else if (f.name.startsWith(_blobDir)) {
      blobs[f.name.substring(_blobDir.length)] = content;
    }
  }
  if (json == null) return null;
  return CampaignBundle(campaignJson: json, blobs: blobs);
}

/// Blob ids a campaign's stores reference, so export/GC only touch blobs that
/// are actually used. Currently that is the journal sketches' background image
/// (`payload.sketch.bg`) and the source PDF of a PDF-page annotation
/// (`payload.sketch.pdf`); tolerant of any malformed shape (returns what it can).
Set<String> referencedBlobIds(Map<String, String> rawByKey) {
  final ids = <String>{};
  final journalRaw = rawByKey['juice.journal.v2'];
  if (journalRaw == null) return ids;
  try {
    final list = jsonDecode(journalRaw);
    if (list is! List) return ids;
    for (final e in list) {
      if (e is! Map) continue;
      final payload = e['payload'];
      if (payload is! Map) continue;
      final sketch = payload['sketch'];
      if (sketch is! Map) continue;
      final bg = sketch['bg'];
      if (bg is String && bg.isNotEmpty) ids.add(bg);
      final pdf = sketch['pdf']; // PDF-page annotation source (epic B2)
      if (pdf is String && pdf.isNotEmpty) ids.add(pdf);
    }
  } catch (_) {
    // Malformed journal JSON → no referenced blobs.
  }
  return ids;
}

/// The blob extension encoded in an id (after the last '.'), or null. Used on
/// import to re-`put` a bundled blob under its original content-addressed id.
String? blobExtFromId(String id) {
  final dot = id.lastIndexOf('.');
  return dot >= 0 ? id.substring(dot + 1) : null;
}
