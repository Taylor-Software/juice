import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  group('JournalEntry payload fields', () {
    final entry = JournalEntry(
      id: 'e1',
      timestamp: DateTime.utc(2026, 6, 12),
      title: 'Fate Check (Likely)',
      body: 'Answer: Yes (+04)',
      sourceTool: 'fate-check',
      payload: {
        'v': 1,
        'command': 'fate-juice',
        'args': {'odds': 'likely'},
        'summary': 'Yes',
        'rolls': [
          {'label': 'Answer', 'display': 'Yes (+04)'}
        ],
        'rerollable': true,
      },
    );

    test('payload and sourceTool round-trip through JSON', () {
      final back = JournalEntry.fromJson(entry.toJson());
      expect(back.sourceTool, 'fate-check');
      expect(back.payload!['command'], 'fate-juice');
      expect((back.payload!['rolls'] as List).single['display'], 'Yes (+04)');
    });

    test('null payload/sourceTool are omitted from JSON (byte-stable legacy)',
        () {
      final plain = JournalEntry(
          id: 'e2', timestamp: DateTime.utc(2026), title: 't', body: 'b');
      final json = plain.toJson();
      expect(json.containsKey('payload'), isFalse);
      expect(json.containsKey('sourceTool'), isFalse);
    });

    test('old JSON without the new keys still parses', () {
      final old = JournalEntry.fromJson({
        'id': 'e3',
        'timestamp': '2026-06-12T00:00:00.000Z',
        'title': 't',
        'body': 'b',
        'kind': 'result',
        'tags': <String>[],
      });
      expect(old.payload, isNull);
      expect(old.sourceTool, isNull);
    });

    test('copyWith preserves payload and sourceTool', () {
      final edited = entry.copyWith(body: 'Answer: Yes (+04)\n\n— note');
      expect(edited.payload, isNotNull);
      expect(edited.sourceTool, 'fate-check');
    });
  });

  group('GenResult.toPayload', () {
    test('maps summary and roll displays', () {
      const g = GenResult(
        title: 'NPC',
        summary: 'Grim hunter',
        rolls: [Roll(label: 'Trait', value: 'Grim', detail: 'd10 4')],
      );
      final p = g.toPayload();
      expect(p['v'], 1);
      expect(p['summary'], 'Grim hunter');
      expect((p['rolls'] as List).single,
          {'label': 'Trait', 'display': 'Grim (d10 4)'});
    });

    test('omits summary when null', () {
      const g = GenResult(title: 'T', rolls: [Roll(label: 'A', value: 'x')]);
      expect(g.toPayload().containsKey('summary'), isFalse);
    });
  });
}
