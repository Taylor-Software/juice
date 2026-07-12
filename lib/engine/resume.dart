/// Pure content for the journal's "Previously on…" resume card.
/// No Flutter, no clock.
library;

import 'mention_parser.dart';
import 'models.dart';

/// What the resume card shows: the latest scene title (null when the
/// campaign has no scenes yet) and up to [max] one-line snippets of the
/// newest entries, oldest of the picked set first (reads chronologically).
({String? sceneTitle, List<String> lines}) resumeLines(
  List<JournalEntry> entriesNewestFirst, {
  int max = 3,
  int maxChars = 96,
}) {
  String? sceneTitle;
  for (final e in entriesNewestFirst) {
    if (e.kind == JournalKind.scene && e.title.trim().isNotEmpty) {
      sceneTitle = e.title.trim();
      break;
    }
  }
  final lines = <String>[];
  for (final e in entriesNewestFirst) {
    if (lines.length >= max) break;
    if (e.kind == JournalKind.sketch) continue;
    final body = mentionsToPlain(e.body).trim();
    final title = e.title.trim();
    // "Title — body" when both exist (a bare "Fate Check" says nothing);
    // otherwise whichever is present.
    var line = switch ((title.isNotEmpty, body.isNotEmpty)) {
      (true, true) => '$title — $body',
      (true, false) => title,
      (false, true) => body,
      _ => '',
    };
    if (line.isEmpty) continue;
    line = line.replaceAll('\n', ' ');
    if (line.length > maxChars) line = '${line.substring(0, maxChars - 1)}…';
    lines.add(line);
  }
  return (sceneTitle: sceneTitle, lines: lines.reversed.toList());
}
