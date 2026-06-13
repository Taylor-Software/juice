import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/entity_suggestions.dart';
import 'package:juice_oracle/engine/models.dart';

JournalEntry _e(String id, String body,
        {JournalKind kind = JournalKind.text,
        String? sourceTool,
        Map<String, dynamic>? payload}) =>
    JournalEntry(
        id: id,
        timestamp: DateTime.utc(2026, 6, 12),
        title: '',
        body: body,
        kind: kind,
        sourceTool: sourceTool,
        payload: payload);

void main() {
  test('suggests an NPC result by its summary name', () {
    final s = suggestEntities(
      [
        _e('1', 'Name: Kestrel\nRole: Scout',
            kind: JournalKind.result,
            sourceTool: 'gen-npcs',
            payload: {'v': 1, 'summary': 'Kestrel', 'rolls': const []}),
      ],
      existingCharNames: const {},
      existingThreadTitles: const {},
      dismissed: const {},
    );
    expect(s.map((x) => x.name), contains('Kestrel'));
    expect(s.firstWhere((x) => x.name == 'Kestrel').kind,
        SuggestionKind.character);
  });

  test('suggests a capitalized name that recurs at least twice', () {
    final s = suggestEntities(
      [
        _e('1', 'We met Brannoc by the well.'),
        _e('2', 'Brannoc warned us about the road.'),
      ],
      existingCharNames: const {},
      existingThreadTitles: const {},
      dismissed: const {},
    );
    expect(s.map((x) => x.name), contains('Brannoc'));
  });

  test('a name appearing once is not suggested', () {
    final s = suggestEntities(
      [_e('1', 'A lone traveller named Sessaly passed by.')],
      existingCharNames: const {},
      existingThreadTitles: const {},
      dismissed: const {},
    );
    expect(s.map((x) => x.name), isNot(contains('Sessaly')));
  });

  test('existing characters and dismissed names are not suggested', () {
    final entries = [
      _e('1', 'Brannoc again.'),
      _e('2', 'Brannoc once more.'),
      _e('3', 'Kara and Kara.'),
    ];
    final s = suggestEntities(
      entries,
      existingCharNames: {'brannoc'},
      existingThreadTitles: const {},
      dismissed: {'character:kara'},
    );
    final names = s.map((x) => x.name).toList();
    expect(names, isNot(contains('Brannoc'))); // already tracked
    expect(names, isNot(contains('Kara'))); // dismissed
  });

  test('sentence-initial common words are not mistaken for names', () {
    final s = suggestEntities(
      [_e('1', 'The door opened. The room was dark.')],
      existingCharNames: const {},
      existingThreadTitles: const {},
      dismissed: const {},
    );
    expect(s, isEmpty);
  });

  test('suggestionKey is stable kind:lowername', () {
    expect(suggestionKey(SuggestionKind.character, 'Mara'), 'character:mara');
    expect(suggestionKey(SuggestionKind.thread, 'The Vow'), 'thread:the vow');
  });
}
