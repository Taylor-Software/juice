import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/engine/lonelog_data.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/engine/verdant_data.dart';
import 'package:juice_oracle/shared/home_shell.dart';
import 'package:juice_oracle/state/providers.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));
final _verdant = VerdantData(
    jsonDecode(File('assets/verdant_data.json').readAsStringSync())
        as Map<String, dynamic>);
final _emu = EmulatorData(
    jsonDecode(File('assets/emulator_data.json').readAsStringSync())
        as Map<String, dynamic>);
final _lonelog = LonelogData(
    jsonDecode(File('assets/lonelog_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('New Campaign dialog offers a Lonelog toggle (default off)',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        verdantDataProvider.overrideWith((ref) async => _verdant),
        emulatorDataProvider.overrideWith((ref) async => _emu),
        lonelogDataProvider.overrideWith((ref) async => _lonelog),
      ],
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();

    // Open Campaigns -> New campaign.
    await t.tap(find.byTooltip('Campaigns'));
    await t.pumpAndSettle();
    await t.tap(find.text('New campaign'));
    await t.pumpAndSettle();

    final lonelog = find.byKey(const Key('sys-lonelog'));
    expect(lonelog, findsOneWidget);
    final tile = t.widget<CheckboxListTile>(lonelog);
    expect(tile.value, isFalse); // opt-in: default off
  });
}
