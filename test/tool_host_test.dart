import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/engine/help_data.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/shared/tool_host.dart';
import 'package:juice_oracle/shared/tool_registry.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: () => setState(() => n++), child: Text('count $n'));
}

void main() {
  final tools = [
    ToolDef(
        id: 'counter',
        label: 'Counter',
        icon: Icons.add,
        group: 'Reference',
        builder: (_) => const _Counter()),
    ToolDef(
        id: 'other',
        label: 'Other Tool',
        icon: Icons.circle,
        group: 'Reference',
        builder: (_) => const Text('other tool body')),
  ];

  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: ToolHost(
                    tools: tools, child: const Text('journal home'))))));
    await tester.pumpAndSettle();
  }

  testWidgets('launcher opens, search filters, tool opens', (tester) async {
    await pump(tester);
    expect(find.text('journal home'), findsOneWidget);
    ToolHost.openLauncher(tester.element(find.text('journal home')));
    await tester.pumpAndSettle();
    expect(find.text('Counter'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tool-search')), 'other');
    await tester.pumpAndSettle();
    expect(find.text('Counter'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Other Tool'));
    await tester.pumpAndSettle();
    expect(find.text('other tool body'), findsOneWidget);
  });

  testWidgets('tool state survives close and reopen', (tester) async {
    await pump(tester);
    ToolHost.openLauncher(tester.element(find.text('journal home')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Counter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('count 0'));
    await tester.pump();
    expect(find.text('count 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tool-close')));
    await tester.pumpAndSettle();
    expect(find.text('journal home'), findsOneWidget);
    ToolHost.openLauncher(tester.element(find.text('journal home')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Counter'));
    await tester.pumpAndSettle();
    expect(find.text('count 1'), findsOneWidget); // state kept
  });

  testWidgets('opening a tool records it as most recently used',
      (tester) async {
    await pump(tester);
    ToolHost.openLauncher(tester.element(find.text('journal home')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Other Tool'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('juice.tools.mru.v1'), contains('other'));
  });

  testWidgets('cold-start record keeps previously persisted MRU',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.tools.mru.v1': '["counter"]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: ToolHost(
                    tools: tools, child: const Text('journal home'))))));
    await tester.pumpAndSettle();
    // First interaction is record() itself — provider not yet read anywhere.
    ToolHost.openLauncher(tester.element(find.text('journal home')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Other Tool'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('juice.tools.mru.v1')!;
    expect(raw, contains('other'));
    expect(raw, contains('counter')); // not clobbered
    expect(raw.indexOf('other'), lessThan(raw.indexOf('counter')));
  });

  testWidgets('recent row shows MRU chips; tapping one opens the tool',
      (tester) async {
    await pump(tester);
    ToolHost.openLauncher(tester.element(find.text('journal home')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mru-counter')), findsNothing); // no MRU yet
    await tester.tap(find.widgetWithText(ListTile, 'Counter'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tool-close')));
    await tester.pumpAndSettle();
    ToolHost.openLauncher(tester.element(find.text('journal home')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mru-counter')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mru-counter')));
    await tester.pumpAndSettle();
    expect(find.text('count 0'), findsOneWidget); // tool opened
  });

  testWidgets('system back closes the panel instead of popping the route',
      (tester) async {
    await pump(tester);
    ToolHost.openLauncher(tester.element(find.text('journal home')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tool-search')), findsOneWidget);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    // Panel closed (search field offstage), app still on its only route.
    expect(find.byKey(const Key('tool-search')), findsNothing);
    expect(find.text('journal home'), findsOneWidget);
  });

  testWidgets('corrupt persisted MRU JSON is discarded, not fatal',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.tools.mru.v1': 'not json',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: ToolHost(
                    tools: tools, child: const Text('journal home'))))));
    await tester.pumpAndSettle();
    ToolHost.openLauncher(tester.element(find.text('journal home')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Counter'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('juice.tools.mru.v1'), '["counter"]');
  });

  // -- Per-tool "?" help entry point -----------------------------------------

  final emulatorData = EmulatorData(
      jsonDecode(File('assets/emulator_data.json').readAsStringSync())
          as Map<String, dynamic>);
  final helpData = HelpData(
      jsonDecode(File('assets/help_data.json').readAsStringSync())
          as Map<String, dynamic>);

  Future<void> pumpReal(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        emulatorDataProvider.overrideWith((ref) async => emulatorData),
        helpDataProvider.overrideWith((ref) async => helpData),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
            body: ToolHost(
                tools: buildToolRegistry(family: []),
                child: const Text('journal home'))),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openFromLauncher(WidgetTester tester, String label) async {
    ToolHost.openLauncher(tester.element(find.text('journal home')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, label));
    await tester.pumpAndSettle();
  }

  testWidgets("the '?' on a mapped tool deep-links into its help page",
      (tester) async {
    await pumpReal(tester);
    await openFromLauncher(tester, 'Party Emulator');
    expect(find.byKey(const Key('tool-help')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tool-help')));
    await tester.pumpAndSettle();
    // The panel switched to the Help tool, open at the Party Emulator page.
    expect(find.byKey(const Key('help-back')), findsOneWidget);
    expect(find.text('Party Emulator'), findsOneWidget);
  });

  testWidgets("the '?' is absent on the Help tool itself", (tester) async {
    await pumpReal(tester);
    await openFromLauncher(tester, 'Help');
    expect(find.byKey(const Key('help-page-getting-started')), findsOneWidget);
    expect(find.byKey(const Key('tool-help')), findsNothing);
  });

  testWidgets("the '?' retargets an already-mounted Help instance",
      (tester) async {
    await pumpReal(tester);
    await openFromLauncher(tester, 'Help'); // instantiate Help at its index
    await tester.tap(find.byTooltip('All tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Party Emulator'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tool-help')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('help-back')), findsOneWidget);
    expect(find.text('Party Emulator'), findsOneWidget);
  });
}
