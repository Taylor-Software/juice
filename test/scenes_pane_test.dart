import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/scenes_pane.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/play_context.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists scenes and a New scene action', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    await c.read(journalProvider.notifier).addScene('The Crossing');
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ScenesPane())),
    ));
    await t.pumpAndSettle();
    expect(find.text('The Crossing'), findsOneWidget);
    expect(find.byKey(const Key('scenes-new')), findsOneWidget);
  });

  testWidgets('tapping a scene navigates to Journal', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    await c.read(journalProvider.notifier).addScene('The Crossing');
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ScenesPane())),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('The Crossing'));
    await t.pumpAndSettle();
    expect(c.read(shellRouteProvider).destination, Destination.journal);
  });

  testWidgets('Generate scene prefills the new-scene dialog', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
    });
    final oracle = Oracle(OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>));
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ScenesPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('generate-scene')));
    await tester.pumpAndSettle();
    // The new-scene dialog is open with a non-empty prefilled title field.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text.trim(), isNotEmpty);
  });

  testWidgets('scene dialog name-roll fills the title field', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
    });
    final oracle = Oracle(OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>));
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ScenesPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scenes-new')));
    await tester.pumpAndSettle();
    // Open with an empty field, then the in-dialog dice fills it.
    final empty = tester.widget<TextField>(find.byType(TextField));
    expect(empty.controller?.text, isEmpty);
    await tester.tap(find.byIcon(Icons.casino_outlined));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text.trim(), isNotEmpty);
  });

  // -- Mythic scene-test macro ------------------------------------------------

  Oracle loadOracle() => Oracle(OracleData(
      jsonDecode(File('assets/oracle_data.json').readAsStringSync())
          as Map<String, dynamic>));

  Future<ProviderContainer> pumpMythic(
    WidgetTester tester, {
    String systems = '', // e.g. ',"systems":["juice"]'
  }) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"$systems}]}',
      'juice.journal.v2.default': '[]',
    });
    final c = ProviderContainer(
        overrides: [oracleProvider.overrideWith((ref) async => loadOracle())]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await c.read(journalProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ScenesPane()))));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets(
      'New scene with the Scene Test checkbox logs a Mythic test '
      'result and points the spine at the new scene', (tester) async {
    final c = await pumpMythic(tester);
    await tester.tap(find.byKey(const Key('scenes-new')));
    await tester.pumpAndSettle();
    // Checkbox present and defaults on when Mythic is enabled.
    expect(find.byKey(const Key('scene-roll-test')), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'The Vault');
    await tester.tap(find.widgetWithText(FilledButton, 'Start scene'));
    await tester.pumpAndSettle();

    final entries = c.read(journalProvider).valueOrNull ?? [];
    final scene = entries.firstWhere((e) => e.kind == JournalKind.scene);
    expect(scene.title, 'The Vault');
    // The scene test was rolled and logged as a mythic result.
    expect(entries.where((e) => e.title == 'Mythic Scene Test').length, 1);
    expect(entries.firstWhere((e) => e.title == 'Mythic Scene Test').sourceTool,
        'mythic');
    // Spine now points at the created scene.
    expect(c.read(playContextProvider).valueOrNull?.activeSceneId, scene.id);
  });

  testWidgets('unchecking the Scene Test creates a plain scene only',
      (tester) async {
    final c = await pumpMythic(tester);
    await tester.tap(find.byKey(const Key('scenes-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scene-roll-test'))); // turn off
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Quiet Camp');
    await tester.tap(find.widgetWithText(FilledButton, 'Start scene'));
    await tester.pumpAndSettle();

    final entries = c.read(journalProvider).valueOrNull ?? [];
    expect(entries.where((e) => e.kind == JournalKind.scene).length, 1);
    expect(entries.where((e) => e.sourceTool == 'mythic'), isEmpty);
  });

  testWidgets('an interrupted scene test also rolls and logs a random event',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
      'juice.crawl.v1.default': '{"chaosFactor":9}',
    });
    // Seed 2 -> first d10 = 4; at chaos 9 (4 <= 9 and even) that is an
    // Interrupted Scene, which must trigger a follow-up random event.
    final oracle = Oracle(
      OracleData(jsonDecode(File('assets/oracle_data.json').readAsStringSync())
          as Map<String, dynamic>),
      Dice(Random(2)),
    );
    final c = ProviderContainer(
        overrides: [oracleProvider.overrideWith((ref) async => oracle)]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await c.read(journalProvider.future);
    await c.read(crawlProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ScenesPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scenes-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'The Breach');
    await tester.tap(find.widgetWithText(FilledButton, 'Start scene'));
    await tester.pumpAndSettle();

    final entries = c.read(journalProvider).valueOrNull ?? [];
    final sceneTest = entries.firstWhere((e) => e.title == 'Mythic Scene Test');
    expect(sceneTest.body, contains('Interrupted'));
    expect(entries.where((e) => e.title == 'Mythic Random Event').length, 1);
  });

  testWidgets('a non-Mythic campaign shows no Scene Test checkbox',
      (tester) async {
    final c = await pumpMythic(tester, systems: ',"systems":["juice"]');
    await tester.tap(find.byKey(const Key('scenes-new')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scene-roll-test')), findsNothing);
    // A plain scene still works.
    await tester.enterText(find.byType(TextField), 'Open Road');
    await tester.tap(find.widgetWithText(FilledButton, 'Start scene'));
    await tester.pumpAndSettle();
    final entries = c.read(journalProvider).valueOrNull ?? [];
    expect(entries.where((e) => e.kind == JournalKind.scene).length, 1);
    expect(entries.where((e) => e.sourceTool == 'mythic'), isEmpty);
  });
}
