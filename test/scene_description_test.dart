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
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
          '[{"id":"s1","timestamp":"2026-06-12T10:00:00.000","title":"At the gate","body":"A cold mist clings.","kind":"scene"}]',
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [oracleProvider.overrideWith((ref) async => _oracle())],
      child: MaterialApp(
          theme: AppTheme.light(), home: const Scaffold(body: JournalScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scene-body-s1')), findsOneWidget);
    expect(find.text('A cold mist clings.'), findsOneWidget);
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
}
