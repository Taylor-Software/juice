import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/features/scenes_pane.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fake_interpreter.dart';

Oracle _oracle() => Oracle(
    OracleData(jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>),
    Dice(Random(1)));

void main() {
  testWidgets('journal renders a scene body when present', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default':
          '[{"id":"s1","timestamp":"2026-06-12T10:00:00.000","title":"At the gate","body":"A cold mist clings.","kind":"scene"},'
              '{"id":"s2","timestamp":"2026-06-12T10:01:00.000","title":"Empty","body":"","kind":"scene"}]',
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [oracleProvider.overrideWith((ref) async => _oracle())],
      child: MaterialApp(
          theme: AppTheme.light(), home: const Scaffold(body: JournalScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scene-body-s1')), findsOneWidget);
    expect(find.text('A cold mist clings.'), findsOneWidget);
    // Empty-body scene renders no description widget.
    expect(find.byKey(const Key('scene-body-s2')), findsNothing);
  });

  testWidgets('scenes pane shows the description in the row', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    final id = await c.read(journalProvider.notifier).addScene('At the gate');
    final scene = c.read(journalProvider).value!.firstWhere((e) => e.id == id);
    await c
        .read(journalProvider.notifier)
        .replace(scene.copyWith(body: 'A cold mist clings.'));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ScenesPane())),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('A cold mist clings.'), findsOneWidget);
  });

  testWidgets('bare scene (no chaos, no body) has no subtitle', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    await c.read(journalProvider.notifier).addScene('Bare');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ScenesPane())),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.byType(ListTile)).subtitle, isNull);
  });

  Future<ProviderContainer> pumpScenes(WidgetTester tester,
      {required bool aiReady}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      if (aiReady) 'juice.ai_enabled.v1': true,
    });
    final fake = FakeInterpreterService(
        initial: InterpreterStatus(
            aiReady ? InterpreterPhase.ready : InterpreterPhase.unsupported));
    final c = ProviderContainer(
        overrides: [interpreterServiceProvider.overrideWithValue(fake)]);
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    await c.read(journalProvider.notifier).addScene('At the gate');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ScenesPane())),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('flesh-out appends generated detail to the scene body',
      (tester) async {
    final c = await pumpScenes(tester, aiReady: true);
    final id = c.read(journalProvider).value!.first.id;
    await tester.tap(find.byKey(Key('flesh-out-scene-$id')));
    await tester.pumpAndSettle(); // fleshOut() + review dialog
    await tester.tap(find.byKey(const Key('flesh-out-append')));
    await tester.pumpAndSettle();
    final scene = c.read(journalProvider).value!.firstWhere((e) => e.id == id);
    expect(scene.body, contains('Fleshed-out detail.'));
  });

  testWidgets('flesh-out button hidden when AI not ready', (tester) async {
    final c = await pumpScenes(tester, aiReady: false);
    final id = c.read(journalProvider).value!.first.id;
    expect(find.byKey(Key('flesh-out-scene-$id')), findsNothing);
  });

  testWidgets('manual edit sets the scene description', (tester) async {
    final c = await pumpScenes(tester, aiReady: false);
    final id = c.read(journalProvider).value!.first.id;
    await tester.tap(find.byKey(Key('scene-edit-$id')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('scene-edit-body')), 'Hand-written detail.');
    await tester.tap(find.byKey(const Key('scene-edit-save')));
    await tester.pumpAndSettle();
    final scene = c.read(journalProvider).value!.firstWhere((e) => e.id == id);
    expect(scene.body, 'Hand-written detail.');
  });
}
