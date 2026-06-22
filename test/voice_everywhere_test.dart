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
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

OracleData _loadData() {
  final raw = File('assets/oracle_data.json').readAsStringSync();
  return OracleData(jsonDecode(raw) as Map<String, dynamic>);
}

const _sessionPrefs = {
  'juice.sessions.v1':
      '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
};

Future<({FakeInterpreterService fake, ProviderContainer container})> pumpVoice(
    WidgetTester tester, OracleData data,
    {FakeInterpreterService? fakeService,
    Map<String, Object>? prefs,
    List<JournalEntry>? initialEntries}) async {
  SharedPreferences.setMockInitialValues(
      {...(prefs ?? _sessionPrefs), 'juice.ai_enabled.v1': true});
  final fake = fakeService ??
      FakeInterpreterService(
          initial: const InterpreterStatus(InterpreterPhase.ready));
  final oracle = Oracle(data, Dice(Random(1)));
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
      interpreterServiceProvider.overrideWithValue(fake),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: JournalScreen()),
    ),
  ));
  await tester.pumpAndSettle();

  final container =
      ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));

  // Seed initial entries if provided
  if (initialEntries != null) {
    for (final e in initialEntries.reversed) {
      await container.read(journalProvider.notifier).addResult(
            e.title,
            e.body,
            sourceTool: e.sourceTool,
            payload: e.payload,
          );
    }
    await tester.pumpAndSettle();
  }

  return (fake: fake, container: container);
}

void main() {
  late OracleData data;
  setUpAll(() => data = _loadData());

  testWidgets(
      'a dialog-shaped entry (contains quote) shows Voice… in the entry menu',
      (tester) async {
    final (:fake, :container) = await pumpVoice(tester, data);

    // Add a dialog-shaped entry (contains a double quote)
    await container.read(journalProvider.notifier).addResult(
          'NPC says',
          '"Stand down." The guard steps forward.',
          sourceTool: 'fate-check',
        );
    await tester.pumpAndSettle();

    // Open the entry menu
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();

    expect(find.text('Voice…'), findsOneWidget);
  });

  testWidgets('invoking Voice… calls voiceLine and appends voiced line',
      (tester) async {
    final (:fake, :container) = await pumpVoice(tester, data);
    fake.queuedVoice.add('I will not.');

    await container.read(journalProvider.notifier).addResult(
          'NPC says',
          '"Stand down." The guard steps forward.',
          sourceTool: 'fate-check',
        );
    await tester.pumpAndSettle();

    // Open the entry menu and tap Voice…
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice…'));
    await tester.pumpAndSettle();

    // voiceLine was called
    expect(fake.voiceCalls, 1);
    // lastVoiceSeed.line carries the entry text
    expect(fake.lastVoiceSeed, isNotNull);
    expect(fake.lastVoiceSeed!.line, contains('Stand down'));

    // Entry body now contains the voiced line
    final entries = await container.read(journalProvider.future);
    expect(entries.first.body, contains('I will not.'));
  });

  testWidgets(
      'a non-dialog entry (no quotes, dice sourceTool) does NOT show Voice…',
      (tester) async {
    final (:fake, :container) = await pumpVoice(tester, data);

    await container.read(journalProvider.notifier).addResult(
          'Dice Roll',
          'Rolled 4 on d6.',
          sourceTool: 'dice',
        );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();

    expect(find.text('Voice…'), findsNothing);
  });

  testWidgets(
      'when interpreter is unsupported, Voice… is absent even on dialog entry',
      (tester) async {
    final unsupportedFake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.unsupported));
    final (:fake, :container) =
        await pumpVoice(tester, data, fakeService: unsupportedFake);

    await container.read(journalProvider.notifier).addResult(
          'NPC says',
          '"Stand down." The guard steps forward.',
          sourceTool: 'fate-check',
        );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();

    expect(find.text('Voice…'), findsNothing);
  });

  testWidgets('gen-npcs entry shows Voice… regardless of quotes',
      (tester) async {
    final (:fake, :container) = await pumpVoice(tester, data);

    await container.read(journalProvider.notifier).addResult(
          'NPC Generated',
          'A grizzled soldier with a scar across his cheek.',
          sourceTool: 'gen-npcs',
        );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();

    expect(find.text('Voice…'), findsOneWidget);
  });
}
