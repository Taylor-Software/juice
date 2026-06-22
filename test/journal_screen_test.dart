import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpJournal(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: JournalScreen()))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('composer adds a text entry; scene divider renders chaos',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: JournalScreen()))));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('journal-composer')), 'We slip inside.');
    await tester.tap(find.byKey(const Key('journal-send')));
    await tester.pumpAndSettle();
    expect(find.text('We slip inside.'), findsOneWidget);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    await container
        .read(journalProvider.notifier)
        .addScene('The gatehouse', chaosFactor: 6);
    await tester.pumpAndSettle();
    expect(find.text('The gatehouse'), findsWidgets);
    // 'Chaos 6' appears in both the scene divider and the campaign header.
    expect(find.text('Chaos 6'), findsWidgets);
  });

  testWidgets('New session adds and renders a session divider', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default':
          '[{"id":"a","timestamp":"2026-06-11T09:00:00.000","title":"","body":"First","kind":"text"}]',
    });
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: JournalScreen()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('journal-new-session')));
    await tester.pumpAndSettle();
    expect(find.text('Session 1'), findsOneWidget);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.where((e) => e.kind == JournalKind.session), hasLength(1));
  });

  testWidgets('entries display oldest first (reverse of storage)',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default':
          '[{"id":"b","timestamp":"2026-06-11T10:00:00.000","title":"","body":"Second","kind":"text"},'
              '{"id":"a","timestamp":"2026-06-11T09:00:00.000","title":"","body":"First","kind":"text"}]',
    });
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: JournalScreen()))));
    await tester.pumpAndSettle();
    final firstY = tester.getTopLeft(find.text('First')).dy;
    final secondY = tester.getTopLeft(find.text('Second')).dy;
    expect(firstY, lessThan(secondY));
  });

  testWidgets('whitespace-only send adds no entry', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: JournalScreen()))));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('journal-composer')), '   ');
    await tester.tap(find.byKey(const Key('journal-send')));
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsNothing);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    expect(container.read(journalProvider).valueOrNull, isEmpty);
  });

  testWidgets('editing a text entry body persists', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: JournalScreen()))));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    await container.read(journalProvider.notifier).addText('Original note');
    await tester.pumpAndSettle();
    expect(find.text('Original note'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit note…'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Note'), 'Edited note');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Edited note'), findsOneWidget);
    expect(find.text('Original note'), findsNothing);
    expect(container.read(journalProvider).valueOrNull?.single.body,
        'Edited note');
  });

  testWidgets('a sketch entry renders a CustomPaint thumbnail', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default':
          '[{"id":"s1","timestamp":"2026-06-18T00:00:00.000","title":"Sketch",'
              '"body":"","kind":"sketch","tags":[],'
              '"payload":{"v":1,"sketch":{"v":1,"w":300,"h":200,"strokes":'
              '[{"c":4278190080,"w":3,"p":[[10,10],[40,40]]}]}}}]',
    });
    await pumpJournal(tester);
    expect(find.byKey(const Key('sketch-thumb-s1')), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('composer has a draw button', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
    });
    await pumpJournal(tester);
    expect(find.byKey(const Key('composer-draw')), findsOneWidget);
  });
}
