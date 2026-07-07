import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/tables_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _oracle = Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

Future<void> pump(WidgetTester tester, {String? customTablesJson}) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    if (customTablesJson != null) 'juice.custom_tables.v1': customTablesJson,
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

/// Pump under an [UncontrolledProviderScope] so the test can read
/// [journalProvider] to assert what a roll logged.
Future<ProviderContainer> pumpWithContainer(WidgetTester tester,
    {String? customTablesJson}) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.journal.v2.default': '[]',
    if (customTablesJson != null) 'juice.custom_tables.v1': customTablesJson,
  });
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await c.read(sessionsProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: TablesScreen(oracle: _oracle)),
    ),
  ));
  await tester.pumpAndSettle();
  return c;
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

  testWidgets('My Tables renders a seeded table and rolling it logs an entry',
      (tester) async {
    const seed = '[{"id":"t1","name":"My Loot","rows":["Gold","Gem"]}]';
    final c = await pumpWithContainer(tester, customTablesJson: seed);
    expect(find.byKey(const Key('tables-my-tables')), findsOneWidget);
    final row = find.byKey(const Key('my-table-t1'));
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    final entries = await c.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.sourceTool, 'custom-table');
  });

  testWidgets('tables-my-new opens the editor', (tester) async {
    await pumpWithContainer(tester);
    await tester.tap(find.byKey(const Key('tables-my-new')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('table-name')), findsOneWidget);
  });

  testWidgets('My Tables is hidden when the query matches nothing of mine',
      (tester) async {
    const seed = '[{"id":"t1","name":"My Loot","rows":["Gold"]}]';
    await pumpWithContainer(tester, customTablesJson: seed);
    expect(find.byKey(const Key('tables-my-tables')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('tables-search')), 'settlement');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tables-my-tables')), findsNothing);
  });

  testWidgets('library search matches a custom table by its source',
      (tester) async {
    const seed = '[{"id":"t1","name":"My Loot","rows":["Gold"],'
        '"src":"Big Book of Bars"},'
        '{"id":"t2","name":"Other","rows":["x"]}]';
    await pumpWithContainer(tester, customTablesJson: seed);
    await tester.enterText(
        find.byKey(const Key('tables-search')), 'book of bars');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tables-my-tables')), findsOneWidget);
    expect(find.byKey(const Key('my-table-t1')), findsOneWidget);
    expect(find.byKey(const Key('my-table-t2')), findsNothing);
  });

  testWidgets(
      'My Tables groups by category with headers and filters by genre chips',
      (tester) async {
    const seed = '[{"id":"t1","name":"Patrons","rows":["a"],'
        '"cat":"Characters & NPCs","genre":"Fantasy"},'
        '{"id":"t2","name":"Anomalies","rows":["b"],'
        '"cat":"Locations & Settings","genre":"Sci-fi"}]';
    await pumpWithContainer(tester, customTablesJson: seed);

    // Two categories → headers show, in taxonomy order.
    expect(find.byKey(const Key('tables-cat-Characters & NPCs')),
        findsOneWidget);
    expect(find.byKey(const Key('tables-cat-Locations & Settings')),
        findsOneWidget);
    // Row subtitle carries the genre.
    expect(find.text('Fantasy'), findsWidgets);

    // Two genres → filter chips; picking one hides the other's table.
    await tester.tap(find.byKey(const Key('tables-genre-Sci-fi')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my-table-t2')), findsOneWidget);
    expect(find.byKey(const Key('my-table-t1')), findsNothing);
    await tester.tap(find.byKey(const Key('tables-genre-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my-table-t1')), findsOneWidget);
  });

  testWidgets('editor saves genre/category/source onto the table',
      (tester) async {
    final c = await pumpWithContainer(tester);
    await tester.tap(find.byKey(const Key('tables-my-new')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('table-name')), 'Patrons');
    await tester.enterText(find.byKey(const Key('table-genre')), 'Fantasy');
    await tester.enterText(
        find.byKey(const Key('table-source')), 'Big Book of Bars');
    await tester.tap(find.byKey(const Key('table-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Characters & NPCs').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('table-rows')), 'Grim dwarf');
    await tester.tap(find.byKey(const Key('table-save')));
    await tester.pumpAndSettle();

    final saved =
        (await c.read(customTablesProvider.future)).single;
    expect(saved.name, 'Patrons');
    expect(saved.genre, 'Fantasy');
    expect(saved.category, 'Characters & NPCs');
    expect(saved.source, 'Big Book of Bars');
  });
}
