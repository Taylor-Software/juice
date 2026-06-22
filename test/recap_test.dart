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

OracleData _loadData() {
  final raw = File('assets/oracle_data.json').readAsStringSync();
  return OracleData(jsonDecode(raw) as Map<String, dynamic>);
}

const _sid = 'default';
const _twoEntries = {
  'juice.sessions.v1':
      '{"active":"$_sid","sessions":[{"id":"$_sid","name":"C1"}]}',
  'juice.journal.v2.$_sid':
      '[{"id":"2","timestamp":"2026-06-12T10:01:00.000","title":"","body":"We fled the keep.","kind":"text"},'
          '{"id":"1","timestamp":"2026-06-12T10:00:00.000","title":"","body":"The alarm sounded.","kind":"text"}]',
};

Future<FakeInterpreterService> pumpRecap(
  WidgetTester tester,
  OracleData data, {
  Map<String, Object>? prefs,
  InterpreterPhase phase = InterpreterPhase.ready,
  String? queued,
}) async {
  SharedPreferences.setMockInitialValues(
      {...(prefs ?? _twoEntries), 'juice.ai_enabled.v1': true});
  final fake = FakeInterpreterService(initial: InterpreterStatus(phase));
  if (queued != null) fake.queuedSummary.add(queued);
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
  return fake;
}

void main() {
  late OracleData data;
  setUpAll(() => data = _loadData());

  testWidgets('Previously-on banner appears when entries are unseen',
      (tester) async {
    await pumpRecap(tester, data, queued: 'The party fled the keep.');
    expect(find.byKey(const Key('recap-banner')), findsOneWidget);
  });

  testWidgets('tapping Recap runs summarize and shows the result',
      (tester) async {
    final fake =
        await pumpRecap(tester, data, queued: 'The party fled the keep.');

    await tester.tap(find.byKey(const Key('recap-action')));
    await tester.pumpAndSettle();

    expect(fake.summaryCalls, 1);
    expect(fake.lastSummaryEntries, isNotEmpty);
    // Oldest-first ordering into the summarizer.
    expect(fake.lastSummaryEntries!.first, contains('The alarm sounded'));
    expect(find.text('The party fled the keep.'), findsOneWidget);
  });

  testWidgets('saving the recap persists it as a journal entry',
      (tester) async {
    await pumpRecap(tester, data, queued: 'The party fled the keep.');
    await tester.tap(find.byKey(const Key('recap-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recap-save')));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    final recap = entries.where((e) => e.title == 'Recap');
    expect(recap, hasLength(1));
    expect(recap.first.body, 'The party fled the keep.');
  });

  testWidgets('dismissing the banner persists last-seen (gone after repump)',
      (tester) async {
    await pumpRecap(tester, data, queued: 'x');
    expect(find.byKey(const Key('recap-banner')), findsOneWidget);

    await tester.tap(find.byKey(const Key('recap-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recap-banner')), findsNothing);

    // Re-pump with the persisted last-seen pointing at the newest entry id.
    await pumpRecap(tester, data, prefs: {
      ..._twoEntries,
      'juice.recap.$_sid': '{"lastSeenId":"2"}',
    });
    expect(find.byKey(const Key('recap-banner')), findsNothing);
  });

  testWidgets('no banner and /recap snackbars when the model is unsupported',
      (tester) async {
    await pumpRecap(tester, data, phase: InterpreterPhase.unsupported);
    // Banner gated on interpreter support.
    expect(find.byKey(const Key('recap-banner')), findsNothing);

    // /recap typed + Enter surfaces the needs-model snackbar, no crash.
    await tester.enterText(find.byKey(const Key('journal-composer')), '/recap');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Recap needs the on-device model.'), findsOneWidget);
  });

  testWidgets('/recap via the palette runs summarize when supported',
      (tester) async {
    final fake = await pumpRecap(tester, data, queued: 'A tidy recap.');

    await tester.enterText(find.byKey(const Key('journal-composer')), '/recap');
    await tester.pump();
    expect(find.byKey(const Key('slash-cmd-recap')), findsOneWidget);
    await tester.tap(find.byKey(const Key('slash-cmd-recap')));
    await tester.pumpAndSettle();

    expect(fake.summaryCalls, 1);
    expect(find.text('A tidy recap.'), findsOneWidget);
  });
}
