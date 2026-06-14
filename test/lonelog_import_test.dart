import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/lonelog_export.dart';
import 'package:juice_oracle/engine/lonelog_import.dart';
import 'package:juice_oracle/engine/models.dart';

final _t = DateTime(2026, 6, 14);

void main() {
  test('parses YAML header (quoted) and falls back when title missing', () {
    final a = parseLonelog('---\ntitle: "West Marches"\ngenre: "noir"\n---\n',
        importedAt: _t);
    expect(a.campaignName, 'West Marches');
    expect(a.genre, 'noir');
    final b = parseLonelog('## Session log\n', importedAt: _t);
    expect(b.campaignName, 'Imported Lonelog');
  });

  test('parses the STATE block into threads, characters, tracks', () {
    const md = '---\ntitle: "C"\n---\n\n[STATE]\n'
        '[Thread:Slay the wyrm|Open]\n'
        '[Thread:Find the heir|Closed]\n'
        '[N:Vance|gruff, ally]\n'
        '[N:Mute]\n'
        '[Track:Ritual 3/6]\n'
        '[/STATE]\n';
    final imp = parseLonelog(md, importedAt: _t);
    expect(imp.threads.map((t) => t.title), ['Slay the wyrm', 'Find the heir']);
    expect(imp.threads[0].open, isTrue);
    expect(imp.threads[1].open, isFalse);
    expect(imp.characters[0].name, 'Vance');
    expect(imp.characters[0].tags, ['gruff', 'ally']);
    expect(imp.characters[1].name, 'Mute');
    expect(imp.characters[1].tags, isEmpty);
    expect(imp.tracks.single.name, 'Ritual');
    expect(imp.tracks.single.filled, 3);
    expect(imp.tracks.single.max, 6);
  });

  test('scene header becomes a scene entry; chaos note attaches', () {
    const md = '## Session log\n\n### S1 *the ambush*\n(note: Chaos 5)\n';
    final imp = parseLonelog(md, importedAt: _t);
    final scene = imp.entries.single;
    expect(scene.kind, JournalKind.scene);
    expect(scene.title, 'the ambush');
    expect(scene.chaosFactor, 5);
  });

  test('a blank-separated group becomes one text entry (joined body)', () {
    const md = '## Session log\n\n'
        'd: Fate Check -> Yes\n=> The gate opens.\n\n'
        'A quiet moment.\n';
    final imp = parseLonelog(md, importedAt: _t);
    expect(imp.entries.length, 2);
    // Newest-first: 'A quiet moment.' is the last group -> first entry.
    expect(imp.entries[0].body, 'A quiet moment.');
    expect(imp.entries[0].kind, JournalKind.text);
    expect(imp.entries[1].body, 'd: Fate Check -> Yes\n=> The gate opens.');
  });

  test('empty-journal placeholder yields no entries; garbage tolerated', () {
    final a = parseLonelog('## Session log\n\n(note: empty journal)\n',
        importedAt: _t);
    expect(a.entries, isEmpty);
    // Non-Lonelog junk in the body does not throw.
    final b =
        parseLonelog('## Session log\n\n~~~ random !!!\n', importedAt: _t);
    expect(b.entries.single.body, '~~~ random !!!');
  });

  test('round-trips a campaignToLonelog export', () {
    final exported = campaignToLonelog(
      campaignName: 'Round Trip',
      threads: [
        const Thread(id: 'a', title: 'Open quest', open: true),
        const Thread(id: 'b', title: 'Done quest', open: false),
      ],
      characters: [
        const Character(id: 'c', name: 'Bob', tags: ['friendly'])
      ],
      tracks: [const Track(id: 'd', name: 'Doom', filled: 2, max: 8)],
      entriesNewestFirst: [
        JournalEntry(
            id: '3',
            timestamp: _t,
            title: 'note',
            body: 'A quiet moment.',
            kind: JournalKind.text),
        JournalEntry(
            id: '2',
            timestamp: _t,
            title: 'Fate',
            body: 'Yes',
            kind: JournalKind.result),
        JournalEntry(
            id: '1',
            timestamp: _t,
            title: 'The Start',
            body: '',
            kind: JournalKind.scene),
      ],
      threadTitles: const {'a': 'Open quest', 'b': 'Done quest'},
      exportedAt: _t,
    );
    final imp = parseLonelog(exported, importedAt: _t);
    expect(imp.campaignName, 'Round Trip');
    expect(imp.threads.length, 2);
    expect(imp.threads.firstWhere((t) => t.title == 'Open quest').open, isTrue);
    expect(
        imp.threads.firstWhere((t) => t.title == 'Done quest').open, isFalse);
    expect(imp.tracks.single.name, 'Doom');
    expect(imp.tracks.single.filled, 2);
    expect(imp.characters.single.name, 'Bob');
    expect(imp.entries.length, 3); // scene + result-as-text + text
    final scenes =
        imp.entries.where((e) => e.kind == JournalKind.scene).toList();
    expect(scenes.single.title, 'The Start');
  });
}
