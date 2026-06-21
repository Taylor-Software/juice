import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/moves_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('move result offers an Ask-oracle action that logs a yes/no',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
    });
    final fixture = {
      'meta': {
        'title': 'Ironsworn',
        'authors': ['Shawn Tomkin'],
        'license': 'https://creativecommons.org/licenses/by/4.0',
      },
      'move_categories': [
        {
          'name': 'Adventure',
          'moves': [
            {
              'name': 'Face Danger',
              'trigger': 'When you act',
              'text': 'When you act, roll +stat.',
              'rollType': 'action_roll',
            }
          ],
        }
      ],
      'oracle_collections': <dynamic>[],
      'asset_collections': <dynamic>[],
    };
    final oracle = Oracle(
        OracleData(
            jsonDecode(File('assets/oracle_data.json').readAsStringSync())
                as Map<String, dynamic>),
        Dice());
    final c = ProviderContainer(overrides: [
      rulesetDataProvider('classic').overrideWith((ref) async => fixture),
      oracleProvider.overrideWith((ref) async => oracle),
    ]);
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    await c.read(oracleProvider.future);
    await c.read(journalProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: MovesScreen(rulesetIds: ['classic'])))));
    await tester.pumpAndSettle();

    // Roll the move: expand the category, open the move, roll.
    await tester.tap(find.text('Adventure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Face Danger'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Roll'));
    await tester.pumpAndSettle();

    // The move result card now offers the Ask-oracle action.
    final action = find.byKey(const Key('result-action-Ask oracle'));
    expect(action, findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();

    // A 50/50 Fate Check was logged as a follow-up (await the latest state so
    // the assertion can't race the fire-and-forget log).
    final entries = await c.read(journalProvider.future);
    expect(entries.where((e) => e.sourceTool == 'fate-check'), hasLength(1));
  });
}
