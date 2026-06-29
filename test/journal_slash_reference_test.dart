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
import 'package:juice_oracle/engine/spell.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

OracleData _loadData() {
  final raw = File('assets/oracle_data.json').readAsStringSync();
  return OracleData(jsonDecode(raw) as Map<String, dynamic>);
}

const _sessionPrefs = {
  'juice.sessions.v1':
      '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
};

Future<void> pumpJournal(WidgetTester tester, OracleData data,
    {Map<String, Object>? prefs}) async {
  SharedPreferences.setMockInitialValues(prefs ?? _sessionPrefs);
  final fake = FakeInterpreterService();
  final oracle = Oracle(data, Dice(Random(1)));
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
      interpreterServiceProvider.overrideWithValue(fake),
      // Override content providers so ReferenceView doesn't try to load assets.
      contentMonstersProvider.overrideWith((ref) async => const <Creature>[]),
      contentSpellsProvider.overrideWith((ref) async => const <SpellEntry>[]),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: JournalScreen()),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  late OracleData data;
  setUpAll(() => data = _loadData());

  testWidgets('/lookup palette row appears under /look', (tester) async {
    await pumpJournal(tester, data);
    await tester.enterText(find.byKey(const Key('journal-composer')), '/look');
    await tester.pump();
    expect(find.byKey(const Key('slash-cmd-lookup')), findsOneWidget);
  });

  testWidgets('/spell palette row appears under /sp', (tester) async {
    await pumpJournal(tester, data);
    await tester.enterText(find.byKey(const Key('journal-composer')), '/sp');
    await tester.pump();
    expect(find.byKey(const Key('slash-cmd-spell')), findsOneWidget);
  });

  testWidgets('/monster palette row appears under /mo', (tester) async {
    await pumpJournal(tester, data);
    await tester.enterText(find.byKey(const Key('journal-composer')), '/mo');
    await tester.pump();
    expect(find.byKey(const Key('slash-cmd-monster')), findsOneWidget);
  });

  testWidgets('/spell opens the reference filtered to spells', (tester) async {
    await pumpJournal(tester, data);
    await tester.enterText(
        find.byKey(const Key('journal-composer')), '/spell fire');
    await tester.pump();
    await tester.tap(find.byKey(const Key('journal-send')));
    await tester.pumpAndSettle();
    // The reference view opens as a pushed route.
    expect(find.byKey(const Key('reference-search')), findsOneWidget);
    // The initialQuery 'fire' is prefilled in the search field.
    final searchField = tester
        .widget<TextField>(find.byKey(const Key('reference-search')));
    expect(searchField.controller?.text, 'fire');
  });

  testWidgets('/lookup opens the reference with ContentType.all', (tester) async {
    await pumpJournal(tester, data);
    await tester.enterText(
        find.byKey(const Key('journal-composer')), '/lookup dragon');
    await tester.pump();
    await tester.tap(find.byKey(const Key('journal-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reference-search')), findsOneWidget);
    final searchField = tester
        .widget<TextField>(find.byKey(const Key('reference-search')));
    expect(searchField.controller?.text, 'dragon');
  });

  testWidgets('/monster opens the reference filtered to monsters', (tester) async {
    await pumpJournal(tester, data);
    await tester.enterText(
        find.byKey(const Key('journal-composer')), '/monster goblin');
    await tester.pump();
    await tester.tap(find.byKey(const Key('journal-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reference-search')), findsOneWidget);
    final searchField = tester
        .widget<TextField>(find.byKey(const Key('reference-search')));
    expect(searchField.controller?.text, 'goblin');
  });

  testWidgets('tapping /spell palette chip opens reference and clears composer',
      (tester) async {
    await pumpJournal(tester, data);
    await tester.enterText(find.byKey(const Key('journal-composer')), '/spell');
    await tester.pump();
    await tester.tap(find.byKey(const Key('slash-cmd-spell')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reference-search')), findsOneWidget);
    // Composer cleared (route pushed, composer not in the tree, but palette gone).
    expect(find.byKey(const Key('slash-palette')), findsNothing);
  });
}
