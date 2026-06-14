import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/engine/verdant_data.dart';
import 'package:juice_oracle/shared/home_shell.dart';
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shell shows five nav destinations and opens on Journal',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [_verdantOverride],
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
      overrides: [_verdantOverride],
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

  testWidgets('journal is home; launcher opens grouped tools', (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [_verdantOverride],
        child: MaterialApp(home: HomeShell(oracle: _oracle()))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
    // The tabbed shell now has a NavigationBar (narrow) in the tree.
    expect(find.byType(NavigationBar), findsOneWidget);
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
    await tester.pumpWidget(ProviderScope(
        overrides: [_verdantOverride],
        child: MaterialApp(home: HomeShell(oracle: _oracle()))));
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

  testWidgets('app pause disposes the interpreter service', (tester) async {
    final fake = FakeInterpreterService();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        _verdantOverride,
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
        overrides: [_verdantOverride],
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
