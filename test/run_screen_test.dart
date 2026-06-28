import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/run_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'fake_interpreter.dart';

const _sid = 'default';

OracleData _loadData() =>
    OracleData(jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>);

Map<String, Object> _prefs({
  String? journalJson,
  String? charsJson,
  String? encounterJson,
  String? crawlJson,
  String? contextJson,
}) =>
    {
      'juice.sessions.v1':
          '{"active":"$_sid","sessions":[{"id":"$_sid","name":"C1"}]}',
      if (journalJson != null) 'juice.journal.v2.$_sid': journalJson,
      if (charsJson != null) 'juice.characters.v1.$_sid': charsJson,
      if (encounterJson != null) 'juice.encounter.v1.$_sid': encounterJson,
      if (crawlJson != null) 'juice.crawl.v1.$_sid': crawlJson,
      if (contextJson != null) 'juice.context.v1.$_sid': contextJson,
    };

Future<ProviderContainer> _pump(
  WidgetTester tester,
  OracleData data,
  Map<String, Object> prefs, {
  Size size = const Size(1000, 2200),
  bool aiReady = false,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final oracle = Oracle(data, Dice(Random(1)));
  final container = ProviderContainer(overrides: [
    oracleProvider.overrideWith((ref) async => oracle),
    interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: RunScreen())),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  late OracleData data;
  setUpAll(() => data = _loadData());

  testWidgets('run-screen renders the four panel headers', (tester) async {
    await _pump(tester, data, _prefs());
    expect(find.byKey(const Key('run-screen')), findsOneWidget);
    expect(find.byKey(const Key('run-panel-initiative')), findsOneWidget);
    expect(find.byKey(const Key('run-panel-party')), findsOneWidget);
    expect(find.byKey(const Key('run-panel-scene')), findsOneWidget);
    expect(find.byKey(const Key('run-panel-dice')), findsOneWidget);
    expect(find.byKey(const Key('run-panel-capture')), findsOneWidget);
  });
}
