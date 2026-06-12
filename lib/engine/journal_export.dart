/// Pure renderers that turn a campaign journal into a shareable document.
/// No Flutter, no clock — `exportedAt` is passed in by the caller.
library;

import 'models.dart';

/// Renders the journal as Markdown, oldest entry first.
String journalToMarkdown({
  required String campaignName,
  required List<JournalEntry> entriesNewestFirst,
  required Map<String, String> threadTitles,
  required DateTime exportedAt,
}) {
  final buf = StringBuffer()
    ..writeln('# $campaignName')
    ..writeln()
    ..writeln('Exported ${_date(exportedAt)}');
  for (final block
      in _entryBlocks(entriesNewestFirst, threadTitles, html: false)) {
    buf
      ..writeln()
      ..writeln(block);
  }
  return buf.toString();
}

/// Renders the journal as one self-contained HTML page (inline style,
/// no external resources), oldest entry first. All user text is escaped.
String journalToHtml({
  required String campaignName,
  required List<JournalEntry> entriesNewestFirst,
  required Map<String, String> threadTitles,
  required DateTime exportedAt,
}) {
  final buf = StringBuffer()
    ..writeln('<!DOCTYPE html>')
    ..writeln('<html lang="en">')
    ..writeln('<head>')
    ..writeln('<meta charset="utf-8">')
    ..writeln('<title>${_esc(campaignName)}</title>')
    ..writeln(_style)
    ..writeln('</head>')
    ..writeln('<body>')
    ..writeln('<h1>${_esc(campaignName)}</h1>')
    ..writeln('<p class="exported">Exported ${_date(exportedAt)}</p>');
  for (final block
      in _entryBlocks(entriesNewestFirst, threadTitles, html: true)) {
    buf.writeln(block);
  }
  buf
    ..writeln('</body>')
    ..writeln('</html>');
  return buf.toString();
}

/// The single walk both renderers share: oldest-first entry blocks in the
/// requested format, or the "(empty journal)" placeholder.
Iterable<String> _entryBlocks(
  List<JournalEntry> entriesNewestFirst,
  Map<String, String> threadTitles, {
  required bool html,
}) sync* {
  if (entriesNewestFirst.isEmpty) {
    yield html ? '<p>(empty journal)</p>' : '(empty journal)';
    return;
  }
  for (final e in entriesNewestFirst.reversed) {
    yield _entryBlock(e, threadTitles, html: html);
  }
}

String _entryBlock(
  JournalEntry e,
  Map<String, String> threadTitles, {
  required bool html,
}) {
  final lines = <String>[];
  switch (e.kind) {
    case JournalKind.scene:
      final chaos = e.chaosFactor != null ? ' — Chaos ${e.chaosFactor}' : '';
      lines.add(html
          ? '<h2>${_esc(e.title)}$chaos</h2>'
          : '## ${e.title}$chaos');
    case JournalKind.result:
      if (html) {
        final body = e.body.isEmpty ? '' : '<br>${_escBody(e.body)}';
        lines.add('<p><strong>${_esc(e.title)}</strong>$body</p>');
      } else {
        lines.add('**${e.title}**');
        if (e.body.isNotEmpty) lines.add(e.body);
      }
    case JournalKind.text:
      lines.add(html ? '<p>${_escBody(e.body)}</p>' : e.body);
  }
  if (e.threadId != null) {
    final title = threadTitles[e.threadId] ?? '(closed thread)';
    lines.add(html
        ? '<p class="thread"><small><em>⤷ ${_esc(title)}</em></small></p>'
        : '⤷ $title');
  }
  return lines.join('\n');
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// Escapes, then turns newlines into `<br>` (escape first so the tag lives).
String _escBody(String s) => _esc(s).replaceAll('\n', '<br>');

const _style = '''
<style>
body {
  background: #fbf9f4;
  color: #2a2a28;
  font-family: Georgia, 'Times New Roman', serif;
  line-height: 1.6;
  max-width: 42rem;
  margin: 0 auto;
  padding: 2rem 1.25rem 4rem;
}
h1 { font-size: 1.7rem; margin-bottom: 0.25rem; }
h2 {
  font-size: 1.2rem;
  margin-top: 2rem;
  padding-bottom: 0.3rem;
  border-bottom: 1px solid #d9d4c8;
}
p { margin: 0.8rem 0; }
.exported { color: #8a8578; font-size: 0.85rem; margin-top: 0; }
.thread { color: #8a8578; margin: 0.15rem 0 0.8rem; }
@media print { body { background: #fff; } }
</style>''';
