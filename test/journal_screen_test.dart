import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
