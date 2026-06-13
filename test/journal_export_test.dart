import 'package:flutter_test/flutter_test.dart';

import 'package:juice_oracle/engine/journal_export.dart';
import 'package:juice_oracle/engine/mention_parser.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  final exportedAt = DateTime(2026, 6, 12);
  const threadTitles = {'t1': 'Find the heir'};

  JournalEntry entry({
    required String id,
    String title = '',
    String body = '',
    JournalKind kind = JournalKind.result,
    String? threadId,
    int? chaosFactor,
    List<String> tags = const [],
  }) =>
      JournalEntry(
        id: id,
        timestamp: DateTime(2026, 6, 11),
        title: title,
        body: body,
        kind: kind,
        threadId: threadId,
        chaosFactor: chaosFactor,
        tags: tags,
      );

  String md(List<JournalEntry> entriesNewestFirst) => journalToMarkdown(
        campaignName: 'The Long Road',
        entriesNewestFirst: entriesNewestFirst,
        threadTitles: threadTitles,
        exportedAt: exportedAt,
      );

  String html(List<JournalEntry> entriesNewestFirst) => journalToHtml(
        campaignName: 'The Long Road',
        entriesNewestFirst: entriesNewestFirst,
        threadTitles: threadTitles,
        exportedAt: exportedAt,
      );

  group('header', () {
    test('markdown has campaign name title and exported date', () {
      final out = md(const []);
      expect(out, contains('# The Long Road'));
      expect(out, contains('Exported 2026-06-12'));
    });

    test('html has campaign name and exported date', () {
      final out = html(const []);
      expect(out, contains('The Long Road'));
      expect(out, contains('Exported 2026-06-12'));
    });
  });

  group('ordering', () {
    test('newest-first input renders oldest-first in both formats', () {
      final entries = [
        entry(id: '2', title: 'Newest', kind: JournalKind.scene),
        entry(id: '1', title: 'Oldest', kind: JournalKind.scene),
      ];
      for (final out in [md(entries), html(entries)]) {
        expect(out.indexOf('Oldest'), lessThan(out.indexOf('Newest')));
      }
    });
  });

  group('scene entries', () {
    test('heading with chaos factor', () {
      final entries = [
        entry(
            id: '1',
            title: 'The burned mill',
            kind: JournalKind.scene,
            chaosFactor: 6),
      ];
      expect(md(entries), contains('## The burned mill — Chaos 6'));
      expect(html(entries), contains('<h2>The burned mill — Chaos 6</h2>'));
    });

    test('heading without chaos factor omits the suffix', () {
      final entries = [
        entry(id: '1', title: 'The burned mill', kind: JournalKind.scene),
      ];
      expect(md(entries), contains('## The burned mill\n'));
      expect(md(entries), isNot(contains('Chaos')));
      expect(html(entries), contains('<h2>The burned mill</h2>'));
    });
  });

  group('result entries', () {
    test('bold title then body', () {
      final entries = [
        entry(id: '1', title: 'Fate Check (Likely)', body: 'Yes, and…'),
      ];
      expect(md(entries), contains('**Fate Check (Likely)**\nYes, and…'));
      final h = html(entries);
      expect(h, contains('<strong>Fate Check (Likely)</strong>'));
      expect(h, contains('Yes, and…'));
    });

    test('multi-line body preserved; html uses <br>', () {
      final entries = [
        entry(id: '1', title: 'Location', body: 'Line one\nLine two'),
      ];
      expect(md(entries), contains('Line one\nLine two'));
      expect(html(entries), contains('Line one<br>Line two'));
    });

    test('empty body renders title alone without a stray blank body', () {
      final entries = [entry(id: '1', title: 'Fate Check')];
      expect(md(entries), contains('**Fate Check**'));
      expect(html(entries), contains('<strong>Fate Check</strong>'));
    });
  });

  group('text entries', () {
    test('plain paragraph of the body only', () {
      final entries = [
        entry(
            id: '1',
            body: 'We crossed the river at dawn.',
            kind: JournalKind.text),
      ];
      expect(md(entries), contains('We crossed the river at dawn.'));
      expect(md(entries), isNot(contains('**')));
      expect(html(entries), contains('We crossed the river at dawn.'));
      expect(html(entries), isNot(contains('<strong>')));
    });
  });

  group('thread links', () {
    test('known thread id appends its title', () {
      final entries = [
        entry(id: '1', title: 'Fate Check', body: 'No.', threadId: 't1'),
      ];
      expect(md(entries), contains('⤷ Find the heir'));
      expect(html(entries), contains('⤷ Find the heir'));
    });

    test('unknown thread id falls back to (closed thread)', () {
      final entries = [
        entry(id: '1', title: 'Fate Check', body: 'No.', threadId: 'gone'),
      ];
      expect(md(entries), contains('⤷ (closed thread)'));
      expect(html(entries), contains('⤷ (closed thread)'));
    });
  });

  group('tags', () {
    test('tagged entry gets a tag line after the thread line', () {
      final entries = [
        entry(
            id: '1',
            title: 'Fate Check',
            body: 'No.',
            threadId: 't1',
            tags: ['omens', 'mill']),
      ];
      expect(md(entries), contains('⤷ Find the heir\n`#omens` `#mill`'));
      final h = html(entries);
      expect(
          h,
          contains(
              '<p class="thread"><small><em>#omens #mill</em></small></p>'));
      expect(
          h.indexOf('#omens #mill'), greaterThan(h.indexOf('Find the heir')));
    });

    test('tagged entry without a thread still gets its tag line', () {
      final entries = [
        entry(id: '1', title: 'Fate Check', body: 'No.', tags: ['omens']),
      ];
      expect(md(entries), contains('No.\n`#omens`'));
      expect(html(entries), contains('<em>#omens</em>'));
    });

    test('untagged entries are unchanged (no tag line)', () {
      final entries = [entry(id: '1', title: 'Fate Check', body: 'No.')];
      expect(md(entries), isNot(contains('`#')));
      expect(html(entries), isNot(contains('<em>#')));
    });

    test('html escapes tag text', () {
      final entries = [
        entry(id: '1', title: 'Check', body: 'x', tags: ['<evil>']),
      ];
      final out = html(entries);
      expect(out, isNot(contains('<evil>')));
      expect(out, contains('#&lt;evil&gt;'));
    });
  });

  group('empty journal', () {
    test('header plus an (empty journal) line', () {
      expect(md(const []), contains('(empty journal)'));
      expect(html(const []), contains('(empty journal)'));
    });
  });

  group('html safety and self-containment', () {
    test('escapes user text everywhere it interpolates', () {
      final entries = [
        entry(id: '1', title: '<i>Sly</i>', body: '<b>"x" & \'y\'</b>'),
      ];
      final out = journalToHtml(
        campaignName: 'A & B <Campaign>',
        entriesNewestFirst: entries,
        threadTitles: threadTitles,
        exportedAt: exportedAt,
      );
      expect(out, isNot(contains('<b>"x" & \'y\'</b>')));
      expect(out, isNot(contains('<i>Sly</i>')));
      expect(out, isNot(contains('A & B <Campaign>')));
      expect(
          out, contains('&lt;b&gt;&quot;x&quot; &amp; &#39;y&#39;&lt;/b&gt;'));
      expect(out, contains('&lt;i&gt;Sly&lt;/i&gt;'));
      expect(out, contains('A &amp; B &lt;Campaign&gt;'));
    });

    test('escapes thread titles', () {
      final entries = [
        entry(id: '1', title: 'Check', body: 'x', threadId: 'evil'),
      ];
      final out = journalToHtml(
        campaignName: 'C',
        entriesNewestFirst: entries,
        threadTitles: const {'evil': '<script>boo</script>'},
        exportedAt: exportedAt,
      );
      expect(out, isNot(contains('<script>')));
      expect(out, contains('&lt;script&gt;boo&lt;/script&gt;'));
    });

    test('self-contained: inline style, no external resources', () {
      final out = html([entry(id: '1', title: 'T', body: 'b')]);
      expect(out, contains('<style>'));
      expect(out, isNot(contains('http')));
    });
  });

  group('mention tokens in exported bodies', () {
    test('result body: mention token renders as plain name in markdown', () {
      final entries = [
        entry(
            id: '1',
            title: 'NPC Result',
            body: 'Met @[Mara](char:c1) at the gate.'),
      ];
      final out = md(entries);
      expect(out, contains('Met Mara at the gate.'));
      expect(out, isNot(contains('@[')));
      expect(out, isNot(contains('char:c1')));
    });

    test('result body: mention token renders as plain name in html', () {
      final entries = [
        entry(
            id: '1',
            title: 'NPC Result',
            body: 'Met @[Mara](char:c1) at the gate.'),
      ];
      final out = html(entries);
      expect(out, contains('Met Mara at the gate.'));
      expect(out, isNot(contains('@[')));
      expect(out, isNot(contains('char:c1')));
    });

    test('text body: mention token renders as plain name in markdown', () {
      final entries = [
        entry(
            id: '1',
            body: 'Spoke with @[The Vow](thread:t9).',
            kind: JournalKind.text),
      ];
      final out = md(entries);
      expect(out, contains('Spoke with The Vow.'));
      expect(out, isNot(contains('@[')));
    });

    test('text body: mention token renders as plain name in html', () {
      final entries = [
        entry(
            id: '1',
            body: 'Spoke with @[The Vow](thread:t9).',
            kind: JournalKind.text),
      ];
      final out = html(entries);
      expect(out, contains('Spoke with The Vow.'));
      expect(out, isNot(contains('@[')));
    });

    test('plain body (no tokens) unchanged by mentionsToPlain', () {
      const plain = 'We crossed the river at dawn.';
      expect(mentionsToPlain(plain), plain);
    });
  });
}
