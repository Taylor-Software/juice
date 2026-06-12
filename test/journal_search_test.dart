import 'package:flutter_test/flutter_test.dart';

import 'package:juice_oracle/engine/journal_search.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  JournalEntry entry({
    required String id,
    String title = '',
    String body = '',
    List<String> tags = const [],
    DateTime? timestamp,
    JournalKind kind = JournalKind.result,
  }) =>
      JournalEntry(
        id: id,
        timestamp: timestamp ?? DateTime(2026, 6, 11),
        title: title,
        body: body,
        kind: kind,
        tags: tags,
      );

  final mill = entry(id: '1', title: 'The burned mill', body: 'Ash and beams.');
  final heir = entry(
      id: '2', title: 'Fate Check', body: 'The heir lives.', tags: ['omens']);
  final road = entry(id: '3', body: 'We took the long road.', tags: ['travel']);

  group('searchEntries', () {
    test('blank or whitespace query returns the input unchanged', () {
      final entries = [mill, heir];
      expect(searchEntries(entries, ''), same(entries));
      expect(searchEntries(entries, '   '), same(entries));
    });

    test('matches case-insensitively in the title', () {
      expect(searchEntries([mill, heir], 'MILL').map((e) => e.id), ['1']);
    });

    test('matches in the body', () {
      expect(searchEntries([mill, heir], 'lives').map((e) => e.id), ['2']);
    });

    test('matches in a tag', () {
      expect(searchEntries([mill, heir], 'Omens').map((e) => e.id), ['2']);
    });

    test('multi-term AND: terms may hit different fields of one entry', () {
      // 'fate' hits the title, 'omens' hits a tag — same entry matches.
      expect(searchEntries([mill, heir], 'fate omens').map((e) => e.id), ['2']);
      // Terms matching different entries do NOT combine.
      expect(searchEntries([mill, heir], 'fate ash'), isEmpty);
    });

    test('no match returns empty', () {
      expect(searchEntries([mill, heir], 'dragon'), isEmpty);
    });

    test('preserves input order', () {
      final entries = [road, mill, heir]; // all contain 'the'
      expect(searchEntries(entries, 'the').map((e) => e.id), ['3', '1', '2']);
    });

    test('empty input list', () {
      expect(searchEntries(const [], 'mill'), isEmpty);
    });
  });

  group('allTags', () {
    test('distinct tags in first-seen order', () {
      final entries = [
        entry(id: 'a', tags: ['omens', 'mill']),
        entry(id: 'b', tags: ['travel', 'omens']),
      ];
      expect(allTags(entries), ['omens', 'mill', 'travel']);
    });

    test('empty list yields no tags', () {
      expect(allTags(const []), isEmpty);
    });
  });

  group('relatedEntries', () {
    final target = entry(
      id: 't',
      title: 'Fate Check (Likely)',
      body: 'The Magistrate relents at the mill gate.',
      timestamp: DateTime(2026, 6, 11, 13),
    );
    // Terms of [target]: fate, check, likely, magistrate, relents, mill, gate.

    test('an entry sharing two terms outranks one sharing one', () {
      final two = entry(
          id: 'two',
          body: 'The Magistrate sealed the mill.',
          timestamp: DateTime(2026, 6, 11, 10));
      final one = entry(
          id: 'one',
          body: 'A gate stands open.',
          timestamp: DateTime(2026, 6, 11, 12));
      expect(relatedEntries([one, two, target], target).map((e) => e.id),
          ['two', 'one']);
    });

    test('a shared tag outweighs two shared body terms', () {
      final tagged = entry(
        id: 'tag',
        title: 'Fate Check (Likely)',
        body: 'The Magistrate relents at the mill gate.',
        tags: ['omens'],
        timestamp: DateTime(2026, 6, 11, 13),
      );
      final byTag = entry(
          id: 'byTag',
          body: 'Nothing here matches.',
          tags: ['omens'],
          timestamp: DateTime(2026, 6, 11, 10));
      final byTerms = entry(
          id: 'byTerms',
          body: 'The Magistrate guards the gate.',
          timestamp: DateTime(2026, 6, 11, 12));
      expect(relatedEntries([byTerms, byTag], tagged).map((e) => e.id),
          ['byTag', 'byTerms']);
    });

    test('the target itself is excluded by id', () {
      final other = entry(id: 'o', body: 'The Magistrate waits.');
      expect(relatedEntries([target, other], target).map((e) => e.id), ['o']);
    });

    test('scene entries are never candidates', () {
      final scene = entry(
          id: 's', title: 'The mill gate', kind: JournalKind.scene);
      expect(relatedEntries([scene], target), isEmpty);
    });

    test('zero-score entries are dropped even under the limit', () {
      final unrelated = entry(id: 'u', body: 'Rations run low.');
      expect(relatedEntries([unrelated], target), isEmpty);
    });

    test('ties break toward the more recent timestamp', () {
      final older = entry(
          id: 'old',
          body: 'The Magistrate frowns.',
          timestamp: DateTime(2026, 6, 11, 9));
      final newer = entry(
          id: 'new',
          body: 'The Magistrate smiles.',
          timestamp: DateTime(2026, 6, 11, 11));
      expect(relatedEntries([older, newer], target).map((e) => e.id),
          ['new', 'old']);
      expect(relatedEntries([newer, older], target).map((e) => e.id),
          ['new', 'old']);
    });

    test('limit caps the result count', () {
      final candidates = [
        for (var i = 0; i < 3; i++)
          entry(
              id: 'c$i',
              body: 'The Magistrate again.',
              timestamp: DateTime(2026, 6, 11, i)),
      ];
      expect(relatedEntries(candidates, target), hasLength(2));
      expect(relatedEntries(candidates, target, limit: 1).map((e) => e.id),
          ['c2']);
    });

    test('stopwords and short words never match', () {
      final stoppy = entry(
          id: 'st', title: 'Of an it', body: 'The of an to in is.');
      final shared = entry(id: 'sh', body: 'The of an it ox.');
      // Every word the two share is a stopword or under 3 letters -> score 0.
      expect(relatedEntries([shared], stoppy), isEmpty);
    });

    test('repeat calls return an identical order', () {
      final pool = [
        for (var i = 0; i < 4; i++)
          entry(
              id: 'p$i',
              body: 'mill gate magistrate'.split(' ').take(i + 1).join(' '),
              timestamp: DateTime(2026, 6, 11, i)),
      ];
      final first = relatedEntries(pool, target).map((e) => e.id).toList();
      final second = relatedEntries(pool, target).map((e) => e.id).toList();
      expect(second, first);
    });
  });

  test("leading '#' on a term is stripped (matches the chip display)", () {
    final tagged = JournalEntry(
        id: 't',
        timestamp: DateTime(2026),
        title: '',
        body: '',
        kind: JournalKind.text,
        tags: const ['omens']);
    expect(searchEntries([tagged], '#omens'), [tagged]);
    expect(searchEntries([tagged], '#'), [tagged]); // bare '#' -> no terms
  });
}
