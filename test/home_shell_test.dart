import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/engine/verdant_data.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/features/sheet_tab.dart';
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
    for (final label in ['Journal', 'Sheet', 'Ask', 'Map', 'Track']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
  });

  testWidgets('tapping Map switches the body', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [_verdantOverride, _emulatorOverride],
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Map').first);
    await t.pumpAndSettle();
    // The Map subtab bar is now visible (stub panes echo these labels too,
    // so assert presence, not a unique count).
    expect(find.text('World'), findsWidgets);
    expect(find.text('Journey'), findsWidgets);
  });

  testWidgets('settings gear opens the Settings sheet', (t) async {
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.needsDownload));
    await t.pumpWidget(ProviderScope(
      overrides: [
        _verdantOverride,
        _emulatorOverride,
        interpreterServiceProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('shell-settings')));
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byKey(const Key('settings-ai-toggle')), findsOneWidget);
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
    await tester.tap(find.byTooltip('Find tools & rolls'));
    await tester.pumpAndSettle();
    // The search sheet is up with the grouped tool list.
    expect(find.byKey(const Key('tool-search')), findsOneWidget);
    expect(find.text('Ask the Oracle'), findsOneWidget);
    expect(find.text('Fate Check'), findsOneWidget);
    // Tapping a tool navigates to its destination (no overlay panel).
    await tester.tap(find.widgetWithText(ListTile, 'Fate Check'));
    await tester.pumpAndSettle();
    expect(container.read(shellRouteProvider).destination, Destination.ask);
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
    await tester.tap(find.byTooltip('Find tools & rolls'));
    await tester.pumpAndSettle();
    expect(find.text('Ironsworn Moves & Oracles'), findsNothing);
    // Close the sheet (the tool list is captured when the sheet opens).
    Navigator.of(tester.element(find.byKey(const Key('tool-search')))).pop();
    await tester.pumpAndSettle();
    await container.read(rulesetsProvider.notifier).setRuleset('classic', true);
    await tester.pumpAndSettle();
    // Reopen: the moves tool now appears (below the fold — drag to reveal).
    await tester.tap(find.byTooltip('Find tools & rolls'));
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
    await tester.tap(find.byTooltip('Find tools & rolls'));
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
      'new campaign dialog Custom picker: excluding party and including verdant',
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

    // Preset rows are shown; open Custom picker (it's the dashed row below the
    // taller preset rows — scroll it into view first).
    expect(find.byKey(const Key('preset-solo-ironsworn')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('preset-custom')));
    await tester.tap(find.byKey(const Key('preset-custom')));
    await tester.pumpAndSettle();

    // Custom picker is now visible: ruleset + addon chips. (The scroll offset
    // carried over from scrolling to the dashed row, so ensure visibility.)
    // Pick ironsworn as ruleset.
    await tester.ensureVisible(find.byKey(const Key('ruleset-ironsworn')));
    await tester.tap(find.byKey(const Key('ruleset-ironsworn')));
    await tester.pumpAndSettle();
    // Add oracle defaults (juice is pre-selected in _addons).
    // Add verdant exploration.
    await tester.ensureVisible(find.byKey(const Key('cat-verdant')));
    await tester.tap(find.byKey(const Key('cat-verdant')));
    await tester.pumpAndSettle();
    // Party is pre-checked in _addons; remove it.
    await tester.ensureVisible(find.byKey(const Key('cat-party')));
    await tester.tap(find.byKey(const Key('cat-party')));
    await tester.pumpAndSettle();
    // Also add mythic.
    await tester.ensureVisible(find.byKey(const Key('cat-mythic')));
    await tester.tap(find.byKey(const Key('cat-mythic')));
    await tester.pumpAndSettle();

    // Enter a name (keyed — the journal composer also has a TextField).
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'No Party');

    // Tap Create.
    final create = find.widgetWithText(FilledButton, 'Create');
    await tester.tap(create);
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

  testWidgets('split view shows a tool pane + Journal side by side (wide)',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(
        {'flutter.juice.splitview.v1': true});
    await tester.pumpWidget(ProviderScope(
        overrides: [_verdantOverride, _emulatorOverride],
        child: MaterialApp(home: HomeShell(oracle: _oracle()))));
    await tester.pumpAndSettle();
    // The pinned journal panel (its key exists ONLY in the split branch — the
    // single-pane IndexedStack builds JournalScreen too, so byType is not a
    // discriminating check). The default-selected left pane is now Sheet.
    expect(find.byKey(const Key('split-journal')), findsOneWidget);
    expect(find.byType(SheetTab), findsOneWidget);
    expect(find.byType(JournalScreen), findsOneWidget);
    expect(find.byKey(const Key('split-toggle')), findsOneWidget);
  });

  testWidgets('wide screen with split off shows a single pane', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({}); // split defaults off
    await tester.pumpWidget(ProviderScope(
        overrides: [_verdantOverride, _emulatorOverride],
        child: MaterialApp(home: HomeShell(oracle: _oracle()))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('split-journal')), findsNothing);
    expect(find.byKey(const Key('split-toggle')),
        findsOneWidget); // still offerable
  });

  testWidgets('no split toggle on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
        overrides: [_verdantOverride, _emulatorOverride],
        child: MaterialApp(home: HomeShell(oracle: _oracle()))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('split-toggle')), findsNothing);
  });

  testWidgets('new campaign dialog preset solo-dnd selects dnd system',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [_verdantOverride, _emulatorOverride],
        child: MaterialApp(home: HomeShell(oracle: _oracle()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Campaigns'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'New campaign'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Dungeon');
    await tester.tap(find.byKey(const Key('preset-solo-dnd')));
    await tester.pumpAndSettle();
    final create = find.widgetWithText(FilledButton, 'Create');
    await tester.tap(create);
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    final s = await container.read(sessionsProvider.future);
    expect(s.activeMeta.name, 'Dungeon');
    expect(s.activeMeta.enabledSystems, contains('dnd'));
  });

  testWidgets('new campaign dialog preset solo-shadowdark selects shadowdark',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [_verdantOverride, _emulatorOverride],
        child: MaterialApp(home: HomeShell(oracle: _oracle()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Campaigns'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'New campaign'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Gloomhold');
    await tester.tap(find.byKey(const Key('preset-solo-shadowdark')));
    await tester.pumpAndSettle();
    final create = find.widgetWithText(FilledButton, 'Create');
    await tester.tap(create);
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    final s = await container.read(sessionsProvider.future);
    expect(s.activeMeta.enabledSystems, contains('shadowdark'));
  });

  testWidgets('campaign list rows render the identity spine + icon',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1': '{"active":"default","sessions":['
          '{"id":"default","name":"Indigo Run",'
          '"identityColor":${0xFF4A5A8A},"identityIcon":"castle"}]}',
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [_verdantOverride, _emulatorOverride],
        child: MaterialApp(home: HomeShell(oracle: _oracle()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Campaigns'));
    await tester.pumpAndSettle();
    // The identity spine + the resolved castle icon render in the row.
    expect(find.byKey(const Key('campaign-spine')), findsWidgets);
    expect(find.widgetWithIcon(SizedBox, Icons.castle), findsWidgets);
  });

  testWidgets('mode toggle flips and persists the campaign mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [_verdantOverride, _emulatorOverride],
        child: MaterialApp(home: HomeShell(oracle: _oracle()))));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    // The toggle is now a labeled segmented control with both modes shown.
    final toggle = find.byKey(const Key('mode-toggle'));
    expect(toggle, findsOneWidget);
    expect(find.descendant(of: toggle, matching: find.text('Party')),
        findsOneWidget);
    expect(
        find.descendant(of: toggle, matching: find.text('GM')), findsOneWidget);
    // Default mode is party.
    expect(container.read(modeProvider), CampaignMode.party);
    // Selecting the GM segment flips and persists the mode.
    await tester.tap(find.descendant(of: toggle, matching: find.text('GM')));
    await tester.pumpAndSettle();
    expect(container.read(modeProvider), CampaignMode.gm);
  });
}
