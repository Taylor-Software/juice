import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/tool_host.dart';
import 'package:juice_oracle/shared/tool_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => TextButton(
      onPressed: () => setState(() => n++), child: Text('count $n'));
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
}
