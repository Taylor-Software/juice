import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/lonelog_export.dart';
import 'package:loreseer/engine/models.dart';

String _export({
  String name = 'My Campaign',
  String genre = '',
  String tone = '',
  List<Thread> threads = const [],
  List<Character> characters = const [],
  List<JournalEntry> entries = const [],
}) =>
    campaignToLonelog(
      campaignName: name,
      genre: genre,
      tone: tone,
      threads: threads,
      characters: characters,
      entriesNewestFirst: entries,
      threadTitles: {for (final t in threads) t.id: t.title},
      exportedAt: DateTime(2026, 6, 14),
    );

JournalEntry _entry(JournalKind kind, String title, String body,
        {String? threadId, List<String> tags = const [], int? chaos}) =>
    JournalEntry(
      id: title,
      timestamp: DateTime(2026, 6, 14),
      title: title,
      body: body,
      kind: kind,
      threadId: threadId,
      tags: tags,
      chaosFactor: chaos,
    );

void main() {
  test('YAML front matter has title, tools, date; genre/tone only when set',
      () {
    final out = _export(name: 'West Marches', genre: 'sword & sorcery');
    expect(out, startsWith('---\n'));
    expect(out, contains('title: "West Marches"'));
    expect(out, contains('genre: "sword & sorcery"'));
    expect(out, isNot(contains('tone:')));
    expect(out, contains('tools: loreseer'));
    expect(out, contains('exported: 2026-06-14'));
  });

  test('sanitizes YAML and tag delimiter chars so output stays parseable', () {
    final out = _export(
      name: 'Camp: Alpha',
      threads: [
        Thread(
            id: 't1',
            title: 'Rescue | [the] prisoner',
            stage: ThreadStage.active),
      ],
      characters: [const Character(id: 'c1', name: 'Vance|ally')],
    );
    // Colon in the campaign name can't break the YAML key/value structure.
    expect(out, contains('title: "Camp: Alpha"'));
    // Pipe and brackets in a thread title are replaced, not emitted raw.
    expect(out, contains('[Thread:Rescue / (the) prisoner|Open]'));
    // Pipe in a character name can't fake an extra tag field.
    expect(out, contains('[N:Vance/ally]'));
  });

  test('STATE block lists threads and characters as tags', () {
    final out = _export(
      threads: [
        Thread(id: 't1', title: 'Slay the wyrm', stage: ThreadStage.active),
        Thread(id: 't2', title: 'Find the heir', stage: ThreadStage.done),
      ],
      characters: [
        const Character(id: 'c1', name: 'Vance', tags: ['gruff', 'ally']),
        const Character(id: 'c2', name: 'Mute'),
      ],
    );
    expect(out, contains('[STATE]'));
    expect(out, contains('[Thread:Slay the wyrm|Open]'));
    expect(out, contains('[Thread:Find the heir|Closed]'));
    expect(out, contains('[N:Vance|gruff, ally]'));
    expect(out, contains('[N:Mute]'));
    expect(out, contains('[/STATE]'));
  });

  test('a thread with progress emits both [Thread:] and [Track:] lines', () {
    final out = _export(
      threads: [
        Thread(
            id: 't1',
            title: 'Main quest',
            stage: ThreadStage.active,
            progress: 3,
            progressMax: 6),
      ],
    );
    expect(out, contains('[Thread:Main quest|Open]'));
    expect(out, contains('[Track:Main quest 3/6]'));
  });

  test('a plain thread (progress 0) emits only its [Thread:] line', () {
    final out = _export(
      threads: [
        Thread(id: 't1', title: 'Side quest', stage: ThreadStage.active)
      ],
    );
    expect(out, contains('[Thread:Side quest|Open]'));
    expect(out, isNot(contains('[Track:')));
  });

  test('scene numbering increments and renders chaos note', () {
    final out = _export(entries: [
      _entry(JournalKind.scene, 'Second', '', chaos: 5),
      _entry(JournalKind.scene, 'First', ''),
    ]); // newest-first input -> oldest-first output
    final firstIdx = out.indexOf('### S1 *First*');
    final secondIdx = out.indexOf('### S2 *Second*');
    expect(firstIdx, isNonNegative);
    expect(secondIdx, greaterThan(firstIdx));
    expect(out, contains('(note: Chaos 5)'));
  });

  test('result beat renders as d: title -> first body line', () {
    final out = _export(entries: [
      _entry(JournalKind.result, 'Fate Check — Likely', 'Yes, but...\nextra'),
    ]);
    expect(out, contains('d: Fate Check — Likely -> Yes, but...'));
    expect(out, isNot(contains('extra')));
  });

  test('result with empty body renders bare d: title', () {
    final out =
        _export(entries: [_entry(JournalKind.result, 'Rolled d20=17', '')]);
    expect(out, contains('d: Rolled d20=17'));
    expect(out, isNot(contains('d: Rolled d20=17 ->')));
  });

  test('text beat renders prose; threadId and tags render as trailers', () {
    final out = _export(
      threads: [
        Thread(id: 't1', title: 'Rescue Jonah', stage: ThreadStage.active)
      ],
      entries: [
        _entry(JournalKind.text, 'note', 'The door creaks open.',
            threadId: 't1', tags: ['quiet', 'night']),
      ],
    );
    expect(out, contains('The door creaks open.'));
    expect(out, contains('=> [#Thread:Rescue Jonah]'));
    expect(out, contains('(note: #quiet #night)'));
  });

  test('empty journal yields a placeholder under the log heading', () {
    final out = _export();
    expect(out, contains('## Session log'));
    expect(out, contains('(note: empty journal)'));
  });
}
