import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/shared/home_shell.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('journal is home; launcher opens grouped tools',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final data = OracleData(jsonDecode(
            File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: HomeShell(oracle: Oracle(data)))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('Tools'));
    await tester.pumpAndSettle();
    expect(find.text('Ask the Oracle'), findsOneWidget);
    expect(find.text('Fate Check'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Fate Check'));
    await tester.pumpAndSettle();
    expect(find.text('Roll Fate Check'), findsOneWidget);
  });

  testWidgets('rulesets toggle adds and removes the moves tool',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final data = OracleData(jsonDecode(
            File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: HomeShell(oracle: Oracle(data)))));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    await tester.tap(find.byTooltip('Tools'));
    await tester.pumpAndSettle();
    expect(find.text('Ironsworn Moves & Oracles'), findsNothing);
    await container.read(rulesetsProvider.notifier).setRuleset('classic', true);
    await tester.pumpAndSettle();
    // The Reference group sits below the fold of the launcher list.
    await tester.dragUntilVisible(
      find.text('Ironsworn Moves & Oracles'),
      find.byKey(const Key('launcher-list')),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Ironsworn Moves & Oracles'),
        findsOneWidget);
    await container
        .read(rulesetsProvider.notifier)
        .setRuleset('classic', false);
    await tester.pumpAndSettle();
    expect(find.text('Ironsworn Moves & Oracles'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
