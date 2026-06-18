import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/oracles_tab.dart';
import 'package:juice_oracle/features/sheet_tab.dart';
import 'package:juice_oracle/features/tracker_screen.dart';
import 'package:juice_oracle/features/tracking_tab.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/play_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

final testOracle = Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

void main() {
  testWidgets('SheetTab with no family renders the roster only',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': '[]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: SheetTab(family: [])))));
    await tester.pumpAndSettle();
    expect(find.byType(CharactersPane), findsOneWidget);
    expect(find.text('Characters'), findsNothing); // no subtab bar
  });

  testWidgets('Track shows party subtabs only when party system is on',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["party"]}]}',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: TrackingTab(systems: {'party'})))));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Emulator'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Scenes'), findsOneWidget);
  });

  testWidgets('Ask defaults to Tables for D&D', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["dnd"]}]}',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
                body:
                    OraclesTab(oracle: testOracle, systems: const {'dnd'})))));
    await tester.pumpAndSettle();
    // Tables tab is selected: its pane content (the Dis/—/Adv skew control,
    // unique to TablesScreen) is the visible IndexedStack child.
    expect(find.widgetWithText(Tab, 'Tables'), findsOneWidget);
    expect(find.text('Dis'), findsOneWidget);
  });

  testWidgets('opening a character sets the active character in context',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"c1","name":"Ash","stats":[],"tracks":[],"tags":[]}]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    expect(c.read(playContextProvider).valueOrNull?.activeCharacterId, 'c1');
  });

  testWidgets('Sheet auto-opens the active character', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"c1","name":"Ash","stats":[],"tracks":[],"tags":[]},'
              '{"id":"c2","name":"Birch","stats":[],"tracks":[],"tags":[]}]',
      'juice.context.v1.default': '{"activeCharacterId":"c2"}',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    // c2 sheet should be open — the character list rows are not shown.
    expect(find.text('Ash'), findsNothing);
    // The sheet-back button is present (we're in sheet view).
    expect(find.byKey(const Key('sheet-back')), findsOneWidget);
  });

  testWidgets(
      'backing out of an auto-opened sheet returns to the list and stays',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"c1","name":"Ash","stats":[],"tracks":[],"tags":[]},'
              '{"id":"c2","name":"Birch","stats":[],"tracks":[],"tags":[]}]',
      'juice.context.v1.default': '{"activeCharacterId":"c2"}',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    // Verify we opened the sheet auto.
    expect(find.byKey(const Key('sheet-back')), findsOneWidget);
    // Tap back.
    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    // List is shown and does NOT immediately re-open.
    expect(find.text('Ash'), findsOneWidget);
    expect(find.byKey(const Key('sheet-back')), findsNothing);
  });
}
