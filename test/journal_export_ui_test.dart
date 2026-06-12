import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
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
    // Use the real app theme: its FilledButton minimumSize once laid the
    // export options out wider than the screen, invisible to the user.
    await tester.pumpWidget(ProviderScope(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: JournalScreen()),
      ),
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
    // Guard against the regression where the format options were laid out
    // wider than the screen and rendered clipped/invisible: the option must
    // sit fully within the screen bounds, not just be findable by key.
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final optionRect = tester.getRect(find.byKey(Key(formatKey)));
    expect(optionRect.right, lessThanOrEqualTo(screenWidth),
        reason: 'export option "$formatKey" must be fully on screen');
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
