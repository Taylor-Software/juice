import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/engine/verdant_data.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/home_shell.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

// Load verdant data synchronously from file (avoids rootBundle which hangs in
// the headless test runner). MapsTab now embeds VerdantScreen (via IndexedStack,
// so it's always built), meaning all HomeShell tests need this override.
final _verdantData = VerdantData(
    jsonDecode(File('assets/verdant_data.json').readAsStringSync())
        as Map<String, dynamic>);
final _verdantOverride =
    verdantDataProvider.overrideWith((ref) async => _verdantData);

// Load emulator data synchronously from file (avoids rootBundle which hangs in
// the headless test runner). PartyTab now embeds the real party screens (via
// IndexedStack, so they are always built), meaning all HomeShell tests need
// this override.
final _emulatorData = EmulatorData(
    jsonDecode(File('assets/emulator_data.json').readAsStringSync())
        as Map<String, dynamic>);
final _emulatorOverride =
    emulatorDataProvider.overrideWith((ref) async => _emulatorData);

// Load ruleset data synchronously from files (avoids rootBundle which hangs in
// the headless test runner). OraclesTab now builds MovesScreen eagerly (via
// IndexedStack) when family is non-empty, so the rulesets toggle test needs
// these overrides when it enables Ironsworn classic.
Map<String, dynamic> _rulesetJson(String id) =>
    jsonDecode(File('assets/ruleset_$id.json').readAsStringSync())
        as Map<String, dynamic>;

final _rulesetOverrides = [
  for (final id in ['classic', 'delve', 'starforged', 'sundered_isles'])
    rulesetDataProvider(id).overrideWith((ref) async => _rulesetJson(id)),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shell shows five nav destinations and opens on Journal',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [_verdantOverride, _emulatorOverride],
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();
    for (final label in ['Journal', 'Maps', 'Party', 'Tracking', 'Oracles']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
  });

  testWidgets('tapping Maps switches the body', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [_verdantOverride, _emulatorOverride],
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Maps').first);
    await t.pumpAndSettle();
    // The Maps subtab bar is now visible (stub panes echo these labels too,
    // so assert presence, not a unique count).
    expect(find.text('World'), findsWidgets);
    expect(find.text('Journey'), findsWidgets);
  });

  testWidgets(
      'journal is home; search sheet opens grouped tools and a tap '
      'navigates', (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [_verdantOverride, _emulatorOverride],
        child: MaterialApp(home: HomeShell(oracle: _oracle()))));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
    // The tabbed shell now has a NavigationBar (narrow) in the tree.
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byTooltip('Search tools'));
    await tester.pumpAndSettle();
    // The search sheet is up with the grouped tool list.
    expect(find.byKey(const Key('tool-search')), findsOneWidget);
    expect(find.text('Ask the Oracle'), findsOneWidget);
    expect(find.text('Fate Check'), findsOneWidget);
    // Tapping a tool navigates to its destination (no overlay panel).
    await tester.tap(find.widgetWithText(ListTile, 'Fate Check'));
    await tester.pumpAndSettle();
    expect(container.read(shellRouteProvider).destination, Destination.oracles);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('rulesets toggle adds and removes the moves tool',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [_verdantOverride, _emulatorOverride, ..._rulesetOverrides],
        child: MaterialApp(home: HomeShell(oracle: _oracle()))));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    // Without the classic ruleset, the moves tool is absent from the sheet.
    await tester.tap(find.byTooltip('Search tools'));
    await tester.pumpAndSettle();
    expect(find.text('Ironsworn Moves & Oracles'), findsNothing);
    // Close the sheet (the tool list is captured when the sheet opens).
    Navigator.of(tester.element(find.byKey(const Key('tool-search')))).pop();
    await tester.pumpAndSettle();
    await container.read(rulesetsProvider.notifier).setRuleset('classic', true);
    await tester.pumpAndSettle();
    // Reopen: the moves tool now appears (below the fold — drag to reveal).
    await tester.tap(find.byTooltip('Search tools'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Ironsworn Moves & Oracles'),
      find.byKey(const Key('launcher-list')),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Ironsworn Moves & Oracles'),
        findsOneWidget);
    Navigator.of(tester.element(find.byKey(const Key('tool-search')))).pop();
    await tester.pumpAndSettle();
    await container
        .read(rulesetsProvider.notifier)
        .setRuleset('classic', false);
    await tester.pumpAndSettle();
    // Reopen: absent again.
    await tester.tap(find.byTooltip('Search tools'));
    await tester.pumpAndSettle();
    expect(find.text('Ironsworn Moves & Oracles'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app pause disposes the interpreter service', (tester) async {
    final fake = FakeInterpreterService();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        _verdantOverride,
        _emulatorOverride,
        interpreterServiceProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await tester.pumpAndSettle();
    expect(fake.disposeCalls, 0);
    // AppLifecycleListener asserts on legal transitions, so walk the chain.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(fake.disposeCalls, 1);
    // Restore so the lifecycle state doesn't leak into other tests.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets(
      'new campaign dialog shows system checkboxes; unchecking party excludes it',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [_verdantOverride, _emulatorOverride],
        child: MaterialApp(home: HomeShell(oracle: _oracle()))));
    await tester.pumpAndSettle();

    // Open campaigns dialog.
    await tester.tap(find.byTooltip('Campaigns'));
    await tester.pumpAndSettle();

    // Tap 'New campaign'.
    await tester.tap(find.widgetWithText(ListTile, 'New campaign'));
    await tester.pumpAndSettle();

    // All five system checkboxes are present and checked by default.
    expect(find.byKey(const Key('sys-juice')), findsOneWidget);
    expect(find.byKey(const Key('sys-mythic')), findsOneWidget);
    expect(find.byKey(const Key('sys-ironsworn')), findsOneWidget);
    expect(find.byKey(const Key('sys-party')), findsOneWidget);
    expect(find.byKey(const Key('sys-verdant')), findsOneWidget);

    // Uncheck party.
    await tester.tap(find.byKey(const Key('sys-party')));
    await tester.pumpAndSettle();

    // Enter a name (keyed — the journal composer also has a TextField).
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'No Party');
    await tester.pumpAndSettle();

    // Tap Create.
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    // The new campaign is active, excludes party, and includes verdant.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    final s = await container.read(sessionsProvider.future);
    expect(s.activeMeta.name, 'No Party');
    expect(s.activeMeta.enabledSystems, isNot(contains('party')));
    expect(s.activeMeta.enabledSystems,
        containsAll(['juice', 'mythic', 'ironsworn', 'verdant']));
  });
}
