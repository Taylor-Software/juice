// lib/engine/loop_kit.dart
/// Pure model + pack codec for shareable "loop kits" — a bundle of custom
/// tables + user ref cards + one starter scene. No Flutter imports — unit
/// tested without a widget harness. Mirrors the table-pack pattern in
/// custom_table.dart exactly (same tolerant-decode contract).
library;

import 'dart:convert';

import 'custom_table.dart';
import 'quick_ref.dart';

/// A shareable bundle: tables + ref cards + a starter scene. Importing one
/// appends its tables/refCards to the app-global stores and creates+activates
/// its scene as a new journal entry (see `applyLoopKit` in providers.dart).
class LoopKit {
  const LoopKit({
    required this.name,
    this.system,
    this.tables = const [],
    this.refCards = const [],
    this.sceneTitle = '',
    this.sceneBody = '',
  });

  final String name;
  final String? system;
  final List<CustomTable> tables;
  final List<UserRefCard> refCards;
  final String sceneTitle;
  final String sceneBody;
}

/// Stable marker for an exported loop-kit file.
const kLoopKitKind = 'juice-loop-kit';

String encodeLoopKit(LoopKit kit) => jsonEncode({
      'kind': kLoopKitKind,
      'v': 1,
      'name': kit.name,
      if (kit.system != null) 'system': kit.system,
      'tables': kit.tables.map((t) => t.toJson()).toList(),
      'refCards': kit.refCards.map((c) => c.toJson()).toList(),
      'scene': {'title': kit.sceneTitle, 'body': kit.sceneBody},
    });

/// Tolerant decode: null when the payload isn't a recognizable loop kit
/// (wrong/missing 'kind', missing 'name'). Individual bad table/refCard
/// entries are dropped, not fatal. Throws [FormatException] only when the
/// top-level JSON itself is unparseable — same contract as decodeTablePack.
LoopKit? decodeLoopKit(String raw) {
  final dynamic root = jsonDecode(raw); // may throw FormatException
  if (root is! Map) return null;
  if (root['kind'] != kLoopKitKind) return null;
  final name = root['name'];
  if (name is! String) return null;
  final tablesRaw = root['tables'];
  final refCardsRaw = root['refCards'];
  final sceneRaw = root['scene'];
  final scene = sceneRaw is Map ? sceneRaw.cast<String, dynamic>() : const {};
  return LoopKit(
    name: name,
    system: root['system'] is String ? root['system'] as String : null,
    tables: tablesRaw is List
        ? tablesRaw
            .map(CustomTable.maybeFromJson)
            .whereType<CustomTable>()
            .toList()
        : const [],
    refCards: refCardsRaw is List
        ? refCardsRaw
            .map(UserRefCard.maybeFromJson)
            .whereType<UserRefCard>()
            .toList()
        : const [],
    sceneTitle: (scene['title'] as String?) ?? '',
    sceneBody: (scene['body'] as String?) ?? '',
  );
}
