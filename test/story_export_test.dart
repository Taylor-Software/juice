import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/journal_export.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';

import 'fake_interpreter.dart';

JournalEntry _e({
  required String id,
  String title = '',
  String body = '',
  JournalKind kind = JournalKind.result,
  String? sourceTool,
  int? chaosFactor,
  List<String> tags = const [],
}) =>
    JournalEntry(
      id: id,
      timestamp: DateTime(2026, 7, 11),
      title: title,
      body: body,
      kind: kind,
      sourceTool: sourceTool,
      chaosFactor: chaosFactor,
      tags: tags,
    );

void main() {
  group('journalToStory', () {
    String story(List<JournalEntry> newestFirst) => journalToStory(
          campaignName: 'The Long Road',
          entriesNewestFirst: newestFirst,
          exportedAt: DateTime(2026, 7, 12),
        );

    test('renders prose only, oldest first, mechanics omitted', () {
      final out = story([
        // Newest-first storage order:
        _e(id: '6', title: 'Fate Check', body: 'Yes, and…'), // mechanics
        _e(
            id: '5',
            title: 'Narration',
            body: 'The mill burns behind them.',
            sourceTool: 'narrate'),
        _e(id: '4', kind: JournalKind.sketch), // mechanics
        _e(
            id: '3',
            body: 'We ride at dawn with @[Kara](char:c1).',
            kind: JournalKind.text,
            tags: ['travel']),
        _e(
            id: '2',
            title: 'The Sealed Door',
            body: 'Dust and old wax.',
            kind: JournalKind.scene,
            chaosFactor: 5),
        _e(id: '1', title: 'Session 1', kind: JournalKind.session),
      ]);
      expect(
          out,
          '# The Long Road\n'
          '\n'
          'Exported 2026-07-12\n'
          '\n'
          '# Session 1\n'
          '\n'
          '## The Sealed Door\n'
          '\n'
          'Dust and old wax.\n'
          '\n'
          'We ride at dawn with Kara.\n'
          '\n'
          'The mill burns behind them.\n');
    });

    test('chaos, tags and roll results never leak into the story', () {
      final out = story([
        _e(id: '2', title: 'd20', body: '14', tags: ['rolls']),
        _e(id: '1', title: 'Ambush!', kind: JournalKind.scene, chaosFactor: 7),
      ]);
      expect(out, isNot(contains('Chaos')));
      expect(out, isNot(contains('14')));
      expect(out, isNot(contains('#rolls')));
      expect(out, contains('## Ambush!'));
    });

    test('empty journal renders a placeholder', () {
      expect(story(const []), contains('(empty journal)'));
    });
  });

  test('isStoryEntry classifies kinds and AI source tools', () {
    expect(isStoryEntry(_e(id: '1', kind: JournalKind.text)), isTrue);
    expect(isStoryEntry(_e(id: '2', kind: JournalKind.scene)), isTrue);
    expect(isStoryEntry(_e(id: '3', kind: JournalKind.session)), isTrue);
    expect(isStoryEntry(_e(id: '4', sourceTool: 'narrate')), isTrue);
    expect(isStoryEntry(_e(id: '5', sourceTool: 'interpret')), isTrue);
    expect(isStoryEntry(_e(id: '6', sourceTool: 'fate-check')), isFalse);
    expect(isStoryEntry(_e(id: '7')), isFalse);
    expect(isStoryEntry(_e(id: '8', kind: JournalKind.sketch)), isFalse);
  });

  testWidgets('reading mode hides mechanical entries and restores on toggle',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.ai_nudge_seen.v1': true,
      'juice.journal.v2.default':
          '[{"id":"2","timestamp":"2026-07-11T11:00:00.000","title":"Fate Check","body":"Yes, and…","kind":"result"},'
              '{"id":"1","timestamp":"2026-07-11T10:00:00.000","title":"","body":"The burned mill looms.","kind":"text"}]',
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: JournalScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Fate Check'), findsOneWidget);
    expect(find.text('The burned mill looms.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('journal-reading-mode')));
    await tester.pumpAndSettle();
    expect(find.text('Fate Check'), findsNothing);
    expect(find.text('The burned mill looms.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('journal-reading-mode')));
    await tester.pumpAndSettle();
    expect(find.text('Fate Check'), findsOneWidget);
  });
}
