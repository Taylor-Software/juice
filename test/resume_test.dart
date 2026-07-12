import 'package:flutter_test/flutter_test.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/resume.dart';

JournalEntry _e({
  required String id,
  String title = '',
  String body = '',
  JournalKind kind = JournalKind.result,
}) =>
    JournalEntry(
      id: id,
      timestamp: DateTime(2026, 7, 11),
      title: title,
      body: body,
      kind: kind,
    );

void main() {
  test('picks the latest scene title and newest snippets, chronological', () {
    final r = resumeLines([
      _e(id: '5', title: 'Fate Check', body: 'Yes, and…'),
      _e(id: '4', body: 'We flee the mill.', kind: JournalKind.text),
      _e(id: '3', title: 'The Mill', kind: JournalKind.scene),
      _e(id: '2', title: 'Old Scene', kind: JournalKind.scene),
      _e(id: '1', body: 'Long ago.', kind: JournalKind.text),
    ]);
    expect(r.sceneTitle, 'The Mill');
    // Newest 3 (scene divider counts as a line), oldest of the set first.
    expect(r.lines, [
      'The Mill',
      'We flee the mill.',
      'Fate Check — Yes, and…',
    ]);
  });

  test('skips sketches and empty entries; truncates long lines', () {
    final long = 'x' * 200;
    final r = resumeLines([
      _e(id: '3', kind: JournalKind.sketch),
      _e(id: '2', body: long, kind: JournalKind.text),
      _e(id: '1'),
    ]);
    expect(r.sceneTitle, isNull);
    expect(r.lines, hasLength(1));
    expect(r.lines.single.length, 96);
    expect(r.lines.single, endsWith('…'));
  });

  test('mentions flatten to plain names', () {
    final r = resumeLines([
      _e(id: '1', body: 'Met @[Kara](char:c1).', kind: JournalKind.text),
    ]);
    expect(r.lines.single, 'Met Kara.');
  });

  test('empty journal yields nothing', () {
    final r = resumeLines(const []);
    expect(r.sceneTitle, isNull);
    expect(r.lines, isEmpty);
  });
}
