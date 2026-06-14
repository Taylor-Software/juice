import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
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

// The initial default session has ALL systems, so the shell eagerly builds
// VerdantScreen + party screens on first frame — both need file overrides to
// avoid the headless rootBundle hang.
List<Override> _overrides() => [
      verdantDataProvider.overrideWith((ref) async => _verdant),
      emulatorDataProvider.overrideWith((ref) async => _emu),
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Party destination hidden when party system disabled', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: _overrides(),
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();
    expect(find.text('Party'), findsWidgets); // default session has party
    final container =
        ProviderScope.containerOf(t.element(find.byType(HomeShell)));
    await container.read(sessionsProvider.notifier).create('No party',
        systems: {'juice', 'mythic', 'ironsworn', 'verdant'});
    await t.pumpAndSettle();
    expect(find.text('Party'), findsNothing);
    expect(find.text('Journal'), findsWidgets);
  });

  testWidgets('Maps Journey subtab hidden when verdant disabled', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: _overrides(),
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();
    final container =
        ProviderScope.containerOf(t.element(find.byType(HomeShell)));
    await container.read(sessionsProvider.notifier).create('No verdant',
        systems: {'juice', 'mythic', 'ironsworn', 'party'});
    await t.pumpAndSettle();
    await t.tap(find.text('Maps').first);
    await t.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'World'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Journey'), findsNothing);
  });
}
