/// Pure renderer that turns a campaign into a faithful Lonelog `.md` document
/// (YAML front matter + a juice-defined [STATE] block + journal beats). No
/// Flutter, no clock — `exportedAt` is passed in. Mirrors journal_export.dart.
/// Export only; Lonelog import is P2b.
library;

import 'mention_parser.dart';
import 'models.dart';

String campaignToLonelog({
  required String campaignName,
  String genre = '',
  String tone = '',
  required List<Thread> threads,
  required List<Character> characters,
  required List<Track> tracks,
  required List<JournalEntry> entriesNewestFirst,
  required Map<String, String> threadTitles,
  required DateTime exportedAt,
}) {
  final buf = StringBuffer()
    ..writeln('---')
    ..writeln('title: ${_yaml(campaignName)}');
  if (genre.isNotEmpty) buf.writeln('genre: ${_yaml(genre)}');
  if (tone.isNotEmpty) buf.writeln('tone: ${_yaml(tone)}');
  buf
    ..writeln('tools: juice-oracle')
    ..writeln('exported: ${_date(exportedAt)}')
    ..writeln('---')
    ..writeln()
    ..writeln('[STATE]');
  for (final t in threads) {
    buf.writeln('[Thread:${_tag(t.title)}|${t.open ? 'Open' : 'Closed'}]');
  }
  for (final c in characters) {
    final tags = c.tags.where((s) => s.trim().isNotEmpty).map(_tag).join(', ');
    final name = _tag(c.name);
    buf.writeln(tags.isEmpty ? '[N:$name]' : '[N:$name|$tags]');
  }
  for (final k in tracks) {
    buf.writeln('[Track:${_tag(k.name)} ${k.filled}/${k.max}]');
  }
  buf
    ..writeln('[/STATE]')
    ..writeln()
    ..writeln('## Session log');

  if (entriesNewestFirst.isEmpty) {
    buf
      ..writeln()
      ..writeln('(note: empty journal)');
    return buf.toString();
  }

  var scene = 0;
  for (final e in entriesNewestFirst.reversed) {
    final lines = _beatLines(e, threadTitles, () => ++scene);
    if (lines.isEmpty) continue;
    buf.writeln();
    for (final line in lines) {
      buf.writeln(line);
    }
  }
  return buf.toString();
}

List<String> _beatLines(
  JournalEntry e,
  Map<String, String> threadTitles,
  int Function() nextScene,
) {
  final lines = <String>[];
  final body = mentionsToPlain(e.body);
  switch (e.kind) {
    case JournalKind.scene:
      lines.add('### S${nextScene()} *${_inline(e.title)}*');
      if (e.chaosFactor != null) lines.add('(note: Chaos ${e.chaosFactor})');
    case JournalKind.result:
      final first = body.isEmpty ? '' : body.split('\n').first;
      final title = _inline(e.title);
      lines.add(first.isEmpty ? 'd: $title' : 'd: $title -> $first');
    case JournalKind.text:
      if (body.isNotEmpty) lines.add(body);
    case JournalKind.sketch:
      // Sketches are vector-only; export as a freeform note placeholder.
      lines.add('(note: [Sketch])');
    case JournalKind.session:
      // Lonelog has no session concept; emit a plain line so it round-trips
      // cleanly as a text beat (no literal markdown markup on re-import).
      lines.add(_inline(e.title));
  }
  if (e.threadId != null) {
    final title = threadTitles[e.threadId] ?? '(closed thread)';
    lines.add('=> [#Thread:${_tag(title)}]');
  }
  if (e.tags.isNotEmpty) {
    lines.add('(note: ${e.tags.map((t) => '#$t').join(' ')})');
  }
  return lines;
}

String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Collapse internal newlines/runs of whitespace so a value stays on its one
/// output line.
String _inline(String s) => s.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();

/// A YAML scalar value: always double-quoted with `"`/`\` escaped, so colons,
/// `#`, leading dashes, etc. can never break the front-matter structure.
String _yaml(String s) =>
    '"${_inline(s).replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

/// A value safe inside a `[Prefix:…|…]` tag: the `[` `]` brackets and `|`
/// field delimiter cannot appear in a value, so replace them with look-alikes.
String _tag(String s) =>
    _inline(s).replaceAll('[', '(').replaceAll(']', ')').replaceAll('|', '/');
