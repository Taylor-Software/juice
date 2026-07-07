import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A campaign session with no journal key → an empty journal.
const _emptyPrefs = {
  'juice.sessions.v1':
      '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
};

/// A non-empty journal: one prose entry.
const _nonEmptyPrefs = {
  'juice.sessions.v1':
      '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
  'juice.journal.v2.default': '[{'
      '"id":"e1","timestamp":"2026-06-12T10:00:00.000Z",'
      '"title":"","body":"A line already written.","kind":"text","tags":[]'
      '}]',
};

OracleData _loadData() {
  final raw = File('assets/oracle_data.json').readAsStringSync();
  return OracleData(jsonDecode(raw) as Map<String, dynamic>);
}

/// Pump JournalScreen with a real Oracle so the empty-state primary can roll.
Future<void> pumpJournal(WidgetTester tester, Map<String, Object> prefs) async {
  final oracle = Oracle(_loadData(), Dice(Random(1)));
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [oracleProvider.overrideWith((ref) async => oracle)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: JournalScreen()),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty journal shows the directive empty state', (tester) async {
    await pumpJournal(tester, _emptyPrefs);

    expect(find.byKey(const Key('empty-state-primary')), findsOneWidget);
    expect(find.text('A blank page.'), findsOneWidget);
    // The premise line (stranger-test audit S5).
    expect(find.textContaining("There's no DM here"), findsOneWidget);
    // The dock + composer stay visible beneath the empty state.
    expect(find.byKey(const Key('dock-roll-oracle')), findsOneWidget);
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
  });

  testWidgets('tapping the primary opens the ask-first oracle dialog',
      (tester) async {
    await pumpJournal(tester, _emptyPrefs);

    await tester.tap(find.byKey(const Key('empty-state-primary')));
    await tester.pumpAndSettle();

    // Ask-first (stranger-test audit S1/S2): the primary captures a question
    // instead of firing a blind fate check.
    expect(find.byKey(const Key('ask-oracle-dialog')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('ask-oracle-question')), 'Is anyone here?');
    await tester.tap(find.byKey(const Key('ask-oracle-roll')));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.length, 1);
    final e = entries.single;
    expect(e.kind, JournalKind.result);
    expect(e.sourceTool, 'solo-loop');
    expect(e.title, 'Is anyone here?');
  });

  testWidgets('a non-empty journal does not show the empty state',
      (tester) async {
    await pumpJournal(tester, _nonEmptyPrefs);

    expect(find.byKey(const Key('empty-state-primary')), findsNothing);
    expect(find.text('A blank page.'), findsNothing);
    expect(find.text('A line already written.'), findsOneWidget);
  });
}
