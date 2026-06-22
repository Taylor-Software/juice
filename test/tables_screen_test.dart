import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/tables_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _oracle = Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

Future<void> pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
  });
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: TablesScreen(oracle: _oracle)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders category section headers', (tester) async {
    await pump(tester);
    // Top-of-list groups are built; 'General' (pinned last) is off-screen and
    // lazily unbuilt — its placement is covered by table_groups_test.
    expect(find.text('Challenge'), findsOneWidget);
    expect(find.text('NPC'), findsOneWidget);
    expect(find.text('Quest'), findsOneWidget);
  });

  testWidgets('search filters to the matching group and hides the rest',
      (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byKey(const Key('tables-search')), 'settlement');
    await tester.pumpAndSettle();
    expect(find.text('Settlement'), findsOneWidget); // header still there
    expect(find.text('Settlement Name'), findsOneWidget); // a matching tile
    expect(find.text('Quest'), findsNothing); // non-matching group gone
    expect(find.text('NPC Need'), findsNothing); // non-matching tile gone
  });

  testWidgets('clearing the search restores all groups', (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byKey(const Key('tables-search')), 'settlement');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Quest'), findsOneWidget);
    expect(find.text('NPC'), findsOneWidget);
  });

  testWidgets('search expands a group the user had collapsed', (tester) async {
    await pump(tester);
    // Collapse the Challenge group (top of list, on-screen).
    await tester.tap(find.text('Challenge'));
    await tester.pumpAndSettle();
    expect(find.text('Challenge Physical'), findsNothing); // collapsed
    // Searching it must surface the match despite the prior collapse.
    await tester.enterText(find.byKey(const Key('tables-search')), 'challenge');
    await tester.pumpAndSettle();
    expect(find.text('Challenge Physical'), findsOneWidget);
  });

  testWidgets('tapping a table rolls and surfaces add-to-journal',
      (tester) async {
    await pump(tester);
    // Narrow to a single tile so it's on-screen and unambiguous.
    await tester.enterText(
        find.byKey(const Key('tables-search')), 'quest objective');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add to journal'), findsNothing); // not rolled yet
    await tester.tap(find.text('Quest Objective'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add to journal'), findsOneWidget);
  });
}
