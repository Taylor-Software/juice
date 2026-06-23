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
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Future<(ProviderContainer, FakeInterpreterService)> pumpJournal(
    WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.journal.v2.default':
        '[{"id":"1","timestamp":"2026-06-12T10:00:00.000","title":"Scene",'
            '"body":"At the gate.","kind":"scene"}]',
    'juice.ai_enabled.v1': true,
  });
  final fake = FakeInterpreterService(
      initial: const InterpreterStatus(InterpreterPhase.ready));
  final data = OracleData(
      jsonDecode(File('assets/oracle_data.json').readAsStringSync())
          as Map<String, dynamic>);
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      oracleProvider.overrideWith((ref) async => Oracle(data, Dice(Random(1)))),
      interpreterServiceProvider.overrideWithValue(fake),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: JournalScreen()),
    ),
  ));
  await tester.pumpAndSettle();
  final c =
      ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
  return (c, fake);
}

void main() {
  testWidgets('Continue the scene logs a Narration entry', (tester) async {
    final (c, _) = await pumpJournal(tester);
    await tester.tap(find.byKey(const Key('composer-narrate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('narrate-continue')));
    await tester.pumpAndSettle();
    final entries = c.read(journalProvider).valueOrNull ?? const [];
    final narr = entries.where((e) => e.sourceTool == 'narrate').toList();
    expect(narr, hasLength(1));
    expect(narr.single.title, 'Narration');
    expect(narr.single.body, 'A canned narration.');
  });

  testWidgets('Add a complication logs a Complication entry', (tester) async {
    final (c, _) = await pumpJournal(tester);
    await tester.tap(find.byKey(const Key('composer-narrate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('narrate-complication')));
    await tester.pumpAndSettle();
    final entries = c.read(journalProvider).valueOrNull ?? const [];
    final narr = entries.where((e) => e.sourceTool == 'narrate').toList();
    expect(narr, hasLength(1));
    expect(narr.single.title, 'Complication');
  });
}
