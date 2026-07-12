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

/// Two text entries each mentioning 'Brannoc' → triggers suggestion.
const _sessionWithBrannoc = {
  'juice.sessions.v1':
      '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
  'juice.journal.v2.default':
      '[{"id":"2","timestamp":"2026-06-12T10:01:00.000","title":"","body":"Brannoc warned us about the road.","kind":"text"},'
          '{"id":"1","timestamp":"2026-06-12T10:00:00.000","title":"","body":"We met Brannoc by the well.","kind":"text"}]',
};

Future<void> pumpSuggestions(WidgetTester tester, OracleData data,
    {Map<String, Object>? prefs}) async {
  SharedPreferences.setMockInitialValues(prefs ?? _sessionWithBrannoc);
  // Use unsupported so the recap banner does NOT appear in these tests
  // (keeps assertions focused on suggestion chips only).
  final fake = FakeInterpreterService(
      initial: const InterpreterStatus(InterpreterPhase.unsupported));
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

  testWidgets('suggestion chip appears for repeated name Brannoc',
      (tester) async {
    await pumpSuggestions(tester, data);

    expect(find.byKey(const Key('suggest-character-brannoc')), findsOneWidget);
    expect(find.text('Track Brannoc?'), findsOneWidget);
  });

  testWidgets('tapping suggestion chip creates the character and chip vanishes',
      (tester) async {
    await pumpSuggestions(tester, data);

    expect(find.byKey(const Key('suggest-character-brannoc')), findsOneWidget);

    await tester.tap(find.byKey(const Key('suggest-character-brannoc')));
    await tester.pumpAndSettle();

    // Character was created
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final chars = await container.read(charactersProvider.future);
    expect(chars.map((c) => c.name.toLowerCase()), contains('brannoc'));

    // Chip gone (now an existing character)
    expect(find.byKey(const Key('suggest-character-brannoc')), findsNothing);
  });

  testWidgets(
      'dismiss icon persists dismissal and chip stays gone after repump',
      (tester) async {
    await pumpSuggestions(tester, data);

    expect(find.byKey(const Key('suggest-character-brannoc')), findsOneWidget);

    // Dismiss via the X icon
    await tester
        .tap(find.byKey(const Key('suggest-dismiss-character:brannoc')));
    await tester.pumpAndSettle();

    // Chip gone immediately
    expect(find.byKey(const Key('suggest-character-brannoc')), findsNothing);

    // Re-pump same prefs (dismissal is persisted): chip still absent
    await pumpSuggestions(tester, data, prefs: {
      ..._sessionWithBrannoc,
      'juice.suggestDismissed.default': '["character:brannoc"]',
    });
    expect(find.byKey(const Key('suggest-character-brannoc')), findsNothing);
  });

  testWidgets('one-time chip explainer shows and Got it dismisses for good',
      (tester) async {
    await pumpSuggestions(tester, data);
    expect(find.byKey(const Key('chip-help')), findsOneWidget);

    await tester.tap(find.byKey(const Key('chip-help-got-it')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chip-help')), findsNothing);
    // Chips themselves are unaffected.
    expect(find.byKey(const Key('suggest-character-brannoc')), findsOneWidget);

    // Persisted: a fresh pump with the flag set never shows the explainer.
    await pumpSuggestions(tester, data, prefs: {
      ..._sessionWithBrannoc,
      'juice.chip_help_seen.v1': true,
    });
    expect(find.byKey(const Key('chip-help')), findsNothing);
  });
}
