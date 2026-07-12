/// Pure renderers that turn a campaign journal into a shareable document.
/// No Flutter, no clock — `exportedAt` is passed in by the caller.
library;

import 'mention_parser.dart';
import 'models.dart';

/// Lowercase, hyphenated filename slug for [name] (e.g. "My Game!" →
/// "my-game"); returns [fallback] when nothing usable remains.
String slugify(String name, {String fallback = 'campaign'}) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? fallback : slug;
}

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

/// True when [e] reads as narrative prose rather than mechanics: scenes,
/// session breaks, written entries, and the AI narration/interpretation
/// results. Dice/oracle results, readings, and sketches are mechanics.
/// Shared by the story export and the journal's reading-mode filter.
bool isStoryEntry(JournalEntry e) => switch (e.kind) {
      JournalKind.scene || JournalKind.session || JournalKind.text => true,
      JournalKind.result =>
        e.sourceTool == 'narrate' || e.sourceTool == 'interpret',
      JournalKind.sketch => false,
    };

/// Renders the journal as clean narrative Markdown ("story mode"), oldest
/// first: `#` session breaks, `##` scene headers with their descriptions,
/// and prose paragraphs. Mechanical results, sketches, chaos snapshots,
/// tags, and thread links are all omitted — this is the shareable story,
/// not the table transcript (that's [journalToMarkdown]).
String journalToStory({
  required String campaignName,
  required List<JournalEntry> entriesNewestFirst,
  required DateTime exportedAt,
}) {
  final buf = StringBuffer()
    ..writeln('# $campaignName')
    ..writeln()
    ..writeln('Exported ${_date(exportedAt)}');
  final story = entriesNewestFirst.reversed.where(isStoryEntry).toList();
  if (story.isEmpty) {
    buf
      ..writeln()
      ..writeln('(empty journal)');
    return buf.toString();
  }
  for (final e in story) {
    final body = mentionsToPlain(e.body).trim();
    buf.writeln();
    switch (e.kind) {
      case JournalKind.session:
        buf.writeln('# ${e.title}');
      case JournalKind.scene:
        buf.writeln('## ${e.title}');
        if (body.isNotEmpty) {
          buf
            ..writeln()
            ..writeln(body);
        }
      default:
        // Prose entries: body only — titles like "Narration" are chrome.
        buf.writeln(body.isNotEmpty ? body : e.title);
    }
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
  // Mentions export as their plain display names, not the raw markup token.
  final plainBody = mentionsToPlain(e.body);
  switch (e.kind) {
    case JournalKind.scene:
      final chaos = e.chaosFactor != null ? ' — Chaos ${e.chaosFactor}' : '';
      lines.add(
          html ? '<h2>${_esc(e.title)}$chaos</h2>' : '## ${e.title}$chaos');
    case JournalKind.result:
      if (html) {
        final body = plainBody.isEmpty ? '' : '<br>${_escBody(plainBody)}';
        lines.add('<p><strong>${_esc(e.title)}</strong>$body</p>');
      } else {
        lines.add('**${e.title}**');
        if (plainBody.isNotEmpty) lines.add(plainBody);
      }
    case JournalKind.text:
      lines.add(html ? '<p>${_escBody(plainBody)}</p>' : plainBody);
    case JournalKind.sketch:
      // Sketches are vector-only; export as a placeholder label.
      lines.add(html ? '<p><em>[Sketch]</em></p>' : '[Sketch]');
    case JournalKind.session:
      lines.add(html ? '<h1>${_esc(e.title)}</h1>' : '# ${e.title}');
  }
  if (e.threadId != null) {
    final title = threadTitles[e.threadId] ?? '(closed thread)';
    lines.add(html
        ? '<p class="thread"><small><em>⤷ ${_esc(title)}</em></small></p>'
        : '⤷ $title');
  }
  if (e.tags.isNotEmpty) {
    lines.add(html
        ? '<p class="thread"><small><em>'
            '${e.tags.map((t) => '#${_esc(t)}').join(' ')}</em></small></p>'
        : e.tags.map((t) => '`#$t`').join(' '));
  }
  return lines.join('\n');
}

String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
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
