import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';
import 'package:juice_oracle/features/oracle_interpretation_sheet.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';

import 'fake_interpreter.dart';

/// settingsProvider stand-in whose load always fails.
class _ThrowingSettingsNotifier extends SettingsNotifier {
  @override
  Future<CampaignSettings> build() async => throw StateError('settings boom');
}

void main() {
  const seed = OracleSeed(resultText: 'Fate Check (Likely) — Yes…');

  Future<FakeInterpreterService> pump(WidgetTester tester,
      {InterpreterStatus? initial,
      void Function(OracleInterpretation)? onAccept}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final fake = FakeInterpreterService(initial: initial);
    await tester.pumpWidget(ProviderScope(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        home: Scaffold(
          body: OracleInterpretationSheet(
            seed: seed,
            onAccept: onAccept ?? (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('needsDownload shows consent with size; download warms up',
      (tester) async {
    final fake = await pump(tester);
    expect(fake.refreshCalls, 1);
    expect(find.textContaining('~123 MB'), findsWidgets);
    await tester.tap(find.byKey(const Key('interp-download')));
    await tester.pumpAndSettle();
    expect(fake.warmUpCalls, 1);
    // warmUp flips the fake to ready -> generation starts.
    expect(fake.interpretCalls, 1);
  });

  testWidgets('installing shows progress', (tester) async {
    await pump(tester,
        initial: const InterpreterStatus(InterpreterPhase.installing,
            progress: 42));
    expect(find.textContaining('42%'), findsOneWidget);
  });

  testWidgets('ready generates and renders cards; accept passes the card',
      (tester) async {
    OracleInterpretation? accepted;
    final fake = await pump(tester,
        initial: const InterpreterStatus(InterpreterPhase.ready),
        onAccept: (c) => accepted = c);
    fake.queuedResults.add(const [
      OracleInterpretation(lens: 'literal', reading: 'Wolves at the gate'),
      OracleInterpretation(lens: 'symbolic', reading: 'The road closes'),
    ]);
    // pump() already triggered generation with the fallback card; regenerate
    // to consume the queued pair.
    await tester.tap(find.byKey(const Key('interp-regenerate')));
    await tester.pumpAndSettle();
    expect(find.text('Wolves at the gate'), findsOneWidget);
    expect(find.text('LITERAL'), findsOneWidget);
    await tester.tap(find.byKey(const Key('interp-accept-0')));
    expect(accepted?.reading, 'Wolves at the gate');
  });

  testWidgets('swipe dismisses a card; all dismissed offers reroll',
      (tester) async {
    final fake = await pump(tester,
        initial: const InterpreterStatus(InterpreterPhase.ready));
    expect(fake.interpretCalls, 1);
    // One fallback card rendered. Swipe it away.
    await tester.drag(
        find.byKey(const Key('interp-card-0')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('interp-card-0')), findsNothing);
    expect(find.byKey(const Key('interp-reroll')), findsOneWidget);
    await tester.tap(find.byKey(const Key('interp-reroll')));
    await tester.pumpAndSettle();
    expect(fake.interpretCalls, 2);
  });

  testWidgets('double-tapped regenerate runs one generation', (tester) async {
    final fake = await pump(tester,
        initial: const InterpreterStatus(InterpreterPhase.ready));
    expect(fake.interpretCalls, 1);
    // Hold the next generation in flight and tap Regenerate twice in the
    // same frame: the second tap must hit the _generating guard.
    fake.interpretGate = Completer<void>();
    await tester.tap(find.byKey(const Key('interp-regenerate')));
    await tester.tap(find.byKey(const Key('interp-regenerate')));
    fake.interpretGate!.complete();
    fake.interpretGate = null;
    await tester.pumpAndSettle();
    expect(fake.interpretCalls, 2);
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('interpret error shows retry', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    fake.interpretError = StateError('boom');
    await tester.pumpWidget(ProviderScope(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        home: Scaffold(
            body: OracleInterpretationSheet(seed: seed, onAccept: (_) {})),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('interp-retry')), findsOneWidget);
    fake.interpretError = null;
    await tester.tap(find.byKey(const Key('interp-retry')));
    await tester.pumpAndSettle();
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('settings load failure shows retry, not a stuck spinner',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        interpreterServiceProvider.overrideWithValue(fake),
        settingsProvider.overrideWith(_ThrowingSettingsNotifier.new),
      ],
      child: MaterialApp(
        home: Scaffold(
            body: OracleInterpretationSheet(seed: seed, onAccept: (_) {})),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('interp-retry')), findsOneWidget);
    expect(find.textContaining('settings boom'), findsOneWidget);
    expect(fake.interpretCalls, 0);
  });

  testWidgets('genre/tone editable from header and persisted',
      (tester) async {
    await pump(tester,
        initial: const InterpreterStatus(InterpreterPhase.ready));
    await tester.tap(find.byKey(const Key('interp-tone-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('interp-genre-field')), 'grimdark');
    await tester.enterText(
        find.byKey(const Key('interp-tone-field')), 'tense');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('grimdark'), findsOneWidget);
    final el = tester.element(find.byType(OracleInterpretationSheet));
    final container = ProviderScope.containerOf(el);
    final s = await container.read(settingsProvider.future);
    expect(s.genre, 'grimdark');
    expect(s.tone, 'tense');
  });

  testWidgets('unsupported phase explains itself', (tester) async {
    await pump(tester,
        initial: const InterpreterStatus(InterpreterPhase.unsupported,
            message: 'This browser has no WebGPU support.'));
    expect(find.textContaining('WebGPU'), findsOneWidget);
  });
}
