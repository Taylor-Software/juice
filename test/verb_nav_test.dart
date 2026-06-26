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
import 'package:juice_oracle/state/providers.dart';
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

  testWidgets('the active PC renders as a lead card in the roster list',
      (tester) async {
    // The active character no longer auto-opens its sheet: it surfaces as a
    // rich lead card *in the list* (vitals + quick actions read without a sheet
    // round-trip), while the others stay compact rows.
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"c1","name":"Ash","stats":[],"tracks":[],"tags":[]},'
              '{"id":"c2","name":"Birch","stats":[],'
              '"tracks":[{"label":"HP","current":3,"max":6}],"tags":[]}]',
      'juice.context.v1.default': '{"activeCharacterId":"c2"}',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    // The roster list is shown (not a sheet) — both rows present.
    expect(find.byKey(const Key('sheet-back')), findsNothing);
    expect(find.text('Ash'), findsOneWidget);
    expect(find.text('Birch'), findsOneWidget);
    // The active PC (c2) is the lead card → quick actions present.
    expect(find.byKey(const Key('lead-roll-move')), findsOneWidget);
    expect(find.byKey(const Key('lead-hp-dec')), findsOneWidget);
  });

  testWidgets('tapping the lead card opens the full sheet; back returns',
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
    // Starts on the list (lead card), not the sheet.
    expect(find.byKey(const Key('sheet-back')), findsNothing);
    // Tapping the lead card's name opens the full sheet.
    await tester.tap(find.text('Birch'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sheet-back')), findsOneWidget);
    // Back returns to the list and does NOT immediately re-open.
    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    expect(find.text('Ash'), findsOneWidget);
    expect(find.byKey(const Key('sheet-back')), findsNothing);
  });

  testWidgets('Sheet shows Moves only in party mode', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1","mode":"gm"}]}',
      'juice.characters.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: SheetTab(family: ['classic'])))));
    await tester.pumpAndSettle();
    // GM mode + family non-empty: Moves hidden → bare roster (no Moves tab).
    expect(find.text('Moves'), findsNothing);
    expect(find.byType(CharactersPane), findsOneWidget);
  });

  testWidgets('Sheet shows Moves in party mode (positive case)',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': '[]',
    });
    final fixture = {
      'meta': {
        'title': 'Ironsworn',
        'authors': ['Shawn Tomkin'],
        'license': 'https://creativecommons.org/licenses/by/4.0',
      },
      'move_categories': <dynamic>[],
      'oracle_collections': <dynamic>[],
      'asset_collections': <dynamic>[],
    };
    final c = ProviderContainer(overrides: [
      rulesetDataProvider('classic').overrideWith((ref) async => fixture),
    ]);
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: SheetTab(family: ['classic'])))));
    await tester.pumpAndSettle();
    // Party mode (default) + family non-empty: Characters + Moves subtabs shown.
    expect(find.text('Moves'), findsOneWidget);
  });
}
