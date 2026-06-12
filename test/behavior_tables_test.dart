import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/features/behavior_tables_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final data = EmulatorData(
      jsonDecode(File('assets/emulator_data.json').readAsStringSync())
          as Map<String, dynamic>);

  Future<ProviderContainer> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [emulatorDataProvider.overrideWith((ref) async => data)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: BehaviorTablesScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(BehaviorTablesScreen)));
  }

  testWidgets('all 13 table chips, combo chips, and attribution render',
      (tester) async {
    await pump(tester);
    expect(find.text('Spark'), findsOneWidget);
    expect(find.text('Specific'), findsOneWidget);
    for (final name in [...data.sparkNames, ...data.specificNames]) {
      expect(find.byKey(Key('bt-$name')), findsOneWidget, reason: name);
    }
    expect(find.byKey(const Key('bt-combo-action-focus')), findsOneWidget);
    expect(find.byKey(const Key('bt-combo-action-method')), findsOneWidget);
    expect(find.byKey(const Key('bt-combo-disposition-motivation')),
        findsOneWidget);
    expect(find.text('PET & Sidekick © Tam H (hedonic.ink), CC-BY 4.0'),
        findsOneWidget);
    expect(find.text('Triple-O © Cezar Capacle / Critical Kit, CC-BY-SA 4.0'),
        findsOneWidget);
  });

  testWidgets('tapping a table chip shows a result from that table',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('bt-combat')));
    await tester.pumpAndSettle();

    expect(find.text('Behavior: Combat'), findsOneWidget);
    expect(find.byKey(const Key('bt-roll-combat')), findsOneWidget);
    final shown = data
        .specificTable('combat')
        .values
        .where((v) => tester.any(find.text(v)))
        .toList();
    expect(shown, hasLength(1));
  });

  testWidgets('a combo chip rolls both tables', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('bt-combo-action-focus')));
    await tester.pumpAndSettle();

    expect(find.text('Behavior: Action + Focus'), findsOneWidget);
    expect(find.byKey(const Key('bt-roll-action')), findsOneWidget);
    expect(find.byKey(const Key('bt-roll-focus')), findsOneWidget);
  });

  testWidgets('add-to-journal writes an entry titled after the roll',
      (tester) async {
    final container = await pump(tester);
    await tester.tap(find.byKey(const Key('bt-combat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bt-log')));
    await tester.pumpAndSettle();

    var entries = container.read(journalProvider).valueOrNull ?? [];
    expect(entries, hasLength(1));
    expect(entries.single.title, 'Behavior: Combat');

    await tester.tap(find.byKey(const Key('bt-combo-action-focus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bt-log')));
    await tester.pumpAndSettle();

    entries = container.read(journalProvider).valueOrNull ?? [];
    expect(entries, hasLength(2));
    expect(entries.first.title, 'Behavior: Action + Focus');
  });
}
