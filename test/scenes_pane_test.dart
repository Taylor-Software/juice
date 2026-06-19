import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/scenes_pane.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists scenes and a New scene action', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    await c.read(journalProvider.notifier).addScene('The Crossing');
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ScenesPane())),
    ));
    await t.pumpAndSettle();
    expect(find.text('The Crossing'), findsOneWidget);
    expect(find.byKey(const Key('scenes-new')), findsOneWidget);
  });

  testWidgets('tapping a scene navigates to Journal', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    await c.read(journalProvider.notifier).addScene('The Crossing');
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ScenesPane())),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('The Crossing'));
    await t.pumpAndSettle();
    expect(c.read(shellRouteProvider).destination, Destination.journal);
  });

  testWidgets('Generate scene prefills the new-scene dialog', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
    });
    final oracle = Oracle(OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>));
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ScenesPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('generate-scene')));
    await tester.pumpAndSettle();
    // The new-scene dialog is open with a non-empty prefilled title field.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text.trim(), isNotEmpty);
  });

  testWidgets('scene dialog name-roll fills the title field', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
    });
    final oracle = Oracle(OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>));
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ScenesPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scenes-new')));
    await tester.pumpAndSettle();
    // Open with an empty field, then the in-dialog dice fills it.
    final empty = tester.widget<TextField>(find.byType(TextField));
    expect(empty.controller?.text, isEmpty);
    await tester.tap(find.byIcon(Icons.casino_outlined));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text.trim(), isNotEmpty);
  });
}
