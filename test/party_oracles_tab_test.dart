import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/party_tab.dart';
import 'package:juice_oracle/features/oracles_tab.dart';
import 'package:juice_oracle/state/providers.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

final _emu = EmulatorData(
    jsonDecode(File('assets/emulator_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Party tab shows the three party subtabs', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [emulatorDataProvider.overrideWith((ref) async => _emu)],
      child: const MaterialApp(home: Scaffold(body: PartyTab())),
    ));
    await t.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Emulator'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Sidekick'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Behavior'), findsOneWidget);
  });

  testWidgets(
      'Oracles tab shows Oracle/Generators/Tables; Moves hidden with empty family',
      (t) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
          home:
              Scaffold(body: OraclesTab(oracle: _oracle(), family: const []))),
    ));
    await t.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Oracle'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Generators'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Tables'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Moves'), findsNothing);
    // The Generators surface shows ALL sections, not just Story. With
    // section==null the pane header reads 'Generators'; a section-locked
    // build would read 'Story & Scenes'. Switch to the subtab and check.
    await t.tap(find.widgetWithText(Tab, 'Generators'));
    await t.pumpAndSettle();
    expect(find.text('Story & Scenes'), findsNothing);
    expect(find.text('Settlement'), findsOneWidget); // an Exploration generator
  });
}
