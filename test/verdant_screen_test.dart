import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/engine/verdant_data.dart';
import 'package:juice_oracle/features/verdant_screen.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:juice_oracle/state/verdant.dart';

void main() {
  final oracleData = OracleData(
      jsonDecode(File('assets/oracle_data.json').readAsStringSync())
          as Map<String, dynamic>);
  final verdantData = VerdantData(
      jsonDecode(File('assets/verdant_data.json').readAsStringSync())
          as Map<String, dynamic>);

  Future<ProviderContainer> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // Load verdant data from file (rootBundle override for tests).
        verdantDataProvider.overrideWith((ref) async => verdantData),
      ],
      child: MaterialApp(
        home: Scaffold(body: VerdantScreen(oracle: Oracle(oracleData))),
      ),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(VerdantScreen)));
  }

  testWidgets('ER updates with party; followers do not change ER',
      (tester) async {
    await pump(tester);
    expect(find.text('Encounter Risk: 4'), findsOneWidget); // party 1
    await tester.tap(find.byKey(const Key('party-plus'))); // party 2
    await tester.pumpAndSettle();
    expect(find.text('Encounter Risk: 5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('followers-plus'))); // followers 1
    await tester.pumpAndSettle();
    expect(find.text('Encounter Risk: 5'), findsOneWidget); // unchanged
  });

  testWidgets('Safer/Riskier move the dial', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byKey(const Key('verdant-safer')));
    await tester.pumpAndSettle();
    expect(c.read(verdantProvider).value!.safetyLevel, 2);
    await tester.tap(find.byKey(const Key('verdant-riskier')));
    await tester.pumpAndSettle();
    expect(c.read(verdantProvider).value!.safetyLevel, 1);
  });

  testWidgets('Travel reveals a hex; Danger! logs to the journal',
      (tester) async {
    final c = await pump(tester);
    await tester.scrollUntilVisible(
        find.byKey(const Key('verdant-travel')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('verdant-travel')));
    await tester.pumpAndSettle();
    expect(c.read(mapProvider).value!.hexes, isNotEmpty);

    await tester.scrollUntilVisible(
        find.byKey(const Key('verdant-danger')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('verdant-danger')));
    await tester.pumpAndSettle();
    final entries = c.read(journalProvider).value!;
    expect(entries.any((e) => e.title.startsWith('Verdant — Day 1')), true);
  });

  testWidgets('no layout exception under a tight Scaffold', (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('verdant-list')), findsOneWidget);
  });
}
