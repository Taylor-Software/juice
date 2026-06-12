import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/state/interpreter.dart';

import 'fake_interpreter.dart';

void main() {
  const journalJson =
      '[{"id":"2","timestamp":"2026-06-11T12:00:00.000","title":"Fate Check (Likely)","body":"Yes, and…","kind":"result","threadId":"t1"},'
      '{"id":"1","timestamp":"2026-06-11T11:00:00.000","title":"The burned mill","body":"","kind":"scene","chaosFactor":5}]';
  const threadsJson = '[{"id":"t1","title":"Find the heir","open":false}]';

  Future<void> pump(WidgetTester tester, {bool emptyJournal = false}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      if (!emptyJournal) 'juice.journal.v2.default': journalJson,
      'juice.threads.v1.default': threadsJson,
    });
    final fake = FakeInterpreterService();
    await tester.pumpWidget(ProviderScope(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)],
      child: const MaterialApp(home: Scaffold(body: JournalScreen())),
    ));
    await tester.pumpAndSettle();
  }

  late List<(String, List<int>)> saved;
  setUp(() {
    saved = [];
    JournalScreen.saveFile = (fileName, bytes) async {
      saved.add((fileName, bytes));
    };
  });
  tearDown(() => JournalScreen.saveFile = JournalScreen.defaultSaveFile);

  Future<void> export(WidgetTester tester, String formatKey) async {
    await tester.tap(find.byKey(const Key('journal-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(formatKey)));
    await tester.pumpAndSettle();
  }

  testWidgets('export as markdown saves a .md with the journal content',
      (tester) async {
    await pump(tester);
    await export(tester, 'export-markdown');
    expect(saved, hasLength(1));
    final (fileName, bytes) = saved.single;
    expect(fileName, 'c1-journal.md');
    final content = utf8.decode(bytes);
    expect(content, contains('Fate Check (Likely)'));
    expect(content, contains('# C1'));
    // Closed threads still resolve to their real title.
    expect(content, contains('⤷ Find the heir'));
  });

  testWidgets('export as HTML saves a styled .html with the journal content',
      (tester) async {
    await pump(tester);
    await export(tester, 'export-html');
    expect(saved, hasLength(1));
    final (fileName, bytes) = saved.single;
    expect(fileName, 'c1-journal.html');
    final content = utf8.decode(bytes);
    expect(content, contains('Fate Check (Likely)'));
    expect(content, contains('<style>'));
    expect(content, contains('⤷ Find the heir'));
  });

  testWidgets('cancelling the format dialog saves nothing', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('journal-export')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5)); // barrier dismiss
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
  });

  testWidgets('export button absent when the journal is empty',
      (tester) async {
    await pump(tester, emptyJournal: true);
    expect(find.byKey(const Key('journal-export')), findsNothing);
  });
}
