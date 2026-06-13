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

// Prefs with a character 'Mara' (id c1) and an open thread 'The Vow' (t9).
Map<String, Object> _prefsWithEntities() => {
      'juice.sessions.v1':
          '{"active":"$_sid","sessions":[{"id":"$_sid","name":"C1"}]}',
      'juice.characters.v1.$_sid':
          '[{"id":"c1","name":"Mara","note":"","stats":[],"tracks":[],"tags":[]}]',
      'juice.threads.v1.$_sid': '[{"id":"t9","title":"The Vow","open":true}]',
    };

Future<void> pumpComposer(WidgetTester tester, OracleData data,
    {Map<String, Object>? prefs}) async {
  SharedPreferences.setMockInitialValues(prefs ?? _prefsWithEntities());
  final fake = FakeInterpreterService();
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
}

void main() {
  late OracleData data;
  setUpAll(() => data = _loadData());

  testWidgets('@ma shows Mara suggestion', (tester) async {
    await pumpComposer(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '@ma');
    await tester.pump();

    expect(find.byKey(const Key('mention-char-c1')), findsOneWidget);
    // Slash palette must NOT be visible.
    expect(find.byKey(const Key('slash-palette')), findsNothing);
  });

  testWidgets('tapping Mara suggestion inserts the token', (tester) async {
    await pumpComposer(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '@ma');
    await tester.pump();

    await tester.tap(find.byKey(const Key('mention-char-c1')));
    await tester.pump();

    final composerField =
        tester.widget<TextField>(find.byKey(const Key('journal-composer')));
    expect(composerField.controller?.text, '@[Mara](char:c1) ');
    // Panel dismissed after tap.
    expect(find.byKey(const Key('mention-char-c1')), findsNothing);
  });

  testWidgets('@the shows The Vow thread suggestion', (tester) async {
    await pumpComposer(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '@the');
    await tester.pump();

    expect(find.byKey(const Key('mention-thread-t9')), findsOneWidget);
  });

  testWidgets('tapping thread suggestion inserts the thread token',
      (tester) async {
    await pumpComposer(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '@the');
    await tester.pump();

    await tester.tap(find.byKey(const Key('mention-thread-t9')));
    await tester.pump();

    final composerField =
        tester.widget<TextField>(find.byKey(const Key('journal-composer')));
    expect(composerField.controller?.text, '@[The Vow](thread:t9) ');
  });

  testWidgets('bare @ with no query shows both char and thread sections',
      (tester) async {
    await pumpComposer(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '@');
    await tester.pump();

    expect(find.byKey(const Key('mention-char-c1')), findsOneWidget);
    expect(find.byKey(const Key('mention-thread-t9')), findsOneWidget);
  });

  testWidgets('slash still works after @ test (no duplication)',
      (tester) async {
    await pumpComposer(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '/');
    await tester.pump();

    expect(find.byKey(const Key('slash-palette')), findsOneWidget);
    expect(find.byKey(const Key('mention-char-c1')), findsNothing);
  });

  testWidgets('clearing composer hides the mention panel', (tester) async {
    await pumpComposer(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '@ma');
    await tester.pump();
    expect(find.byKey(const Key('mention-char-c1')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('journal-composer')), '');
    await tester.pump();
    expect(find.byKey(const Key('mention-char-c1')), findsNothing);
  });
}
