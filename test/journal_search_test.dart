import 'package:flutter_test/flutter_test.dart';

import 'package:juice_oracle/engine/journal_search.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  JournalEntry entry({
    required String id,
    String title = '',
    String body = '',
    List<String> tags = const [],
  }) =>
      JournalEntry(
        id: id,
        timestamp: DateTime(2026, 6, 11),
        title: title,
        body: body,
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
