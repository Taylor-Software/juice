import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('JournalEntry.pinned defaults false and round-trips through JSON', () {
    final e = JournalEntry(
      id: 'e1',
      timestamp: DateTime.parse('2026-06-25T12:00:00.000'),
      title: 'Oracle',
      body: 'Yes, and...',
    );
    expect(e.pinned, isFalse);
    final back = JournalEntry.fromJson(e.copyWith(pinned: true).toJson());
    expect(back.pinned, isTrue);
  });
}
