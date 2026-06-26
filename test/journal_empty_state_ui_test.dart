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
    expect(
        find.text('Roll the oracle or write your first line.'), findsOneWidget);
    // The dock + composer stay visible beneath the empty state.
    expect(find.byKey(const Key('dock-roll-oracle')), findsOneWidget);
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
  });

  testWidgets('tapping the primary rolls through the shared pipeline',
      (tester) async {
    await pumpJournal(tester, _emptyPrefs);

    await tester.tap(find.byKey(const Key('empty-state-primary')));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    // A single result entry was appended via rollInlineSuggestion.
    expect(entries.length, 1);
    final e = entries.single;
    expect(e.kind, JournalKind.result);
    expect(e.sourceTool, 'fate-check');
  });

  testWidgets('a non-empty journal does not show the empty state',
      (tester) async {
    await pumpJournal(tester, _nonEmptyPrefs);

    expect(find.byKey(const Key('empty-state-primary')), findsNothing);
    expect(find.text('A blank page.'), findsNothing);
    expect(find.text('A line already written.'), findsOneWidget);
  });
}
