import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
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
final _hex = HexcrawlData(
    jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'New Campaign Custom picker offers a Lonelog toggle (default off)',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        verdantDataProvider.overrideWith((ref) async => _verdant),
        emulatorDataProvider.overrideWith((ref) async => _emu),
        lonelogDataProvider.overrideWith((ref) async => _lonelog),
        hexcrawlDataProvider.overrideWith((ref) async => _hex),
      ],
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();

    // Open Campaigns -> New campaign -> wizard step 1 (has the chips).
    await t.tap(find.byTooltip('Campaigns'));
    await t.pumpAndSettle();
    await t.tap(find.text('New campaign'));
    await t.pumpAndSettle();
    // Step 0 has stance cards; advance to step 1 where addon chips live.
    await t.tap(find.byKey(const Key('wizard-next')));
    await t.pumpAndSettle();

    // Lonelog chip present and not selected (opt-in: default off).
    final lonelog = find.byKey(const Key('cat-lonelog'));
    expect(lonelog, findsOneWidget);
    final chip = t.widget<FilterChip>(lonelog);
    expect(chip.selected, isFalse);
  });

  testWidgets('Campaigns dialog offers Export as Lonelog', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        verdantDataProvider.overrideWith((ref) async => _verdant),
        emulatorDataProvider.overrideWith((ref) async => _emu),
        lonelogDataProvider.overrideWith((ref) async => _lonelog),
        hexcrawlDataProvider.overrideWith((ref) async => _hex),
      ],
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Campaigns'));
    await t.pumpAndSettle();
    expect(find.text('Export as Lonelog (.md)'), findsOneWidget);
  });

  testWidgets('Campaigns dialog offers Import Lonelog', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        verdantDataProvider.overrideWith((ref) async => _verdant),
        emulatorDataProvider.overrideWith((ref) async => _emu),
        lonelogDataProvider.overrideWith((ref) async => _lonelog),
        hexcrawlDataProvider.overrideWith((ref) async => _hex),
      ],
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Campaigns'));
    await t.pumpAndSettle();
    expect(find.text('Import Lonelog (.md)'), findsOneWidget);
  });

  testWidgets(
      'New Campaign Custom picker offers a Hexcrawl toggle (default off)',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        verdantDataProvider.overrideWith((ref) async => _verdant),
        emulatorDataProvider.overrideWith((ref) async => _emu),
        lonelogDataProvider.overrideWith((ref) async => _lonelog),
        hexcrawlDataProvider.overrideWith((ref) async => _hex),
      ],
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Campaigns'));
    await t.pumpAndSettle();
    await t.tap(find.text('New campaign'));
    await t.pumpAndSettle();
    // Step 0 has stance cards; advance to step 1 where addon chips live.
    await t.tap(find.byKey(const Key('wizard-next')));
    await t.pumpAndSettle();

    final hex = find.byKey(const Key('cat-hexcrawl'));
    expect(hex, findsOneWidget);
    expect(t.widget<FilterChip>(hex).selected, isFalse);
  });
}
