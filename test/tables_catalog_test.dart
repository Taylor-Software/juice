import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/custom_table.dart';
import 'package:loreseer/engine/oracle.dart';
import 'package:loreseer/engine/oracle_data.dart';
import 'package:loreseer/features/tables_screen.dart';
import 'package:loreseer/shared/theme.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _oracle = Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

const _starterFixture = [
  CustomTable(
    id: 'starter-0',
    name: 'Rumors',
    category: 'Hooks & Rumors',
    rows: [CustomRow('A stranger asks after you by name')],
  ),
];

/// Pump under an [UncontrolledProviderScope] so the test can read
/// [journalProvider] to assert what a roll logged.
Future<ProviderContainer> pumpWithContainer(
  WidgetTester tester, {
  String? customTablesJson,
  List<CustomTable> starters = _starterFixture,
}) async {
  SharedPreferences.setMockInitialValues({
    'loreseer.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'loreseer.journal.v2.default': '[]',
    if (customTablesJson != null) 'loreseer.custom_tables.v1': customTablesJson,
  });
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = ProviderContainer(overrides: [
    starterTablesProvider.overrideWith((ref) async => starters),
  ]);
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
  testWidgets(
      'Generators section lists flavor generators; tapping Word Oracle logs '
      'a gen-story entry', (tester) async {
    final c = await pumpWithContainer(tester);
    // The header's PageStorageKey isn't a plain ValueKey, so tap it by text
    // (mirrors how the built-in oracle table groups are expanded in tests).
    await tester.tap(find.text('Generators'));
    await tester.pumpAndSettle();
    final row = find.byKey(const Key('gen-roll-gen-word-oracle'));
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    final entries = await c.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.sourceTool, 'gen-story');
  });

  testWidgets(
      'Starter tables section lists the fixture starter with no edit '
      'affordance; tapping it logs a custom-table entry', (tester) async {
    final c = await pumpWithContainer(tester);
    expect(find.text('Starter tables'), findsOneWidget);
    await tester.tap(find.text('Starter tables'));
    await tester.pumpAndSettle();
    final row = find.byKey(const Key('starter-roll-starter-0'));
    expect(row, findsOneWidget);
    expect(find.byKey(const Key('my-table-edit-starter-0')), findsNothing);
    await tester.tap(row);
    await tester.pumpAndSettle();
    final entries = await c.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.sourceTool, 'custom-table');
  });

  testWidgets(
      "searching 'rumor' keeps the starter row and drops non-matching "
      'generators', (tester) async {
    await pumpWithContainer(tester);
    await tester.enterText(find.byKey(const Key('tables-search')), 'rumor');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('starter-roll-starter-0')), findsOneWidget);
    expect(find.byKey(const Key('gen-roll-gen-word-oracle')), findsNothing);
  });

  testWidgets("searching 'word' keeps the Word Oracle generator row",
      (tester) async {
    await pumpWithContainer(tester);
    await tester.enterText(find.byKey(const Key('tables-search')), 'word');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gen-roll-gen-word-oracle')), findsOneWidget);
    expect(find.byKey(const Key('starter-roll-starter-0')), findsNothing);
  });

  testWidgets('tables-starter-pack is gone even with an empty user library',
      (tester) async {
    await pumpWithContainer(tester);
    expect(find.byKey(const Key('tables-starter-pack')), findsNothing);
  });

  testWidgets(
      'a user table sourced from the starter pack hides the bundled '
      'duplicate', (tester) async {
    const seed = '[{"id":"t1","name":"Rumors","rows":["x"],'
        '"src":"Starter set"}]';
    await pumpWithContainer(tester, customTablesJson: seed);
    expect(find.byKey(const Key('starter-roll-starter-0')), findsNothing);
    expect(find.byKey(const Key('my-table-t1')), findsOneWidget);
  });
}
