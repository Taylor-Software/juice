// Device integration test for the launcher → Session Resume flow, driven
// end-to-end through the REAL launcher-gate wiring (LauncherScreen ⇄ HomeShell,
// the same switch app.dart performs) with real rootBundle assets and the fake
// interpreter.
//
// This exercises the actual `_resume`/`_switch` paths — the launcher gate
// dismiss that the isolated SessionResumeScreen unit tests never drove, where
// the resume route was silently dropped because the launcher's context/ref were
// disposed before it pushed (the bug this test guards).
//
// Run: flutter test integration_test/resume_flow_test.dart -d macos

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/launcher_screen.dart';
import 'package:juice_oracle/features/session_resume_screen.dart';
import 'package:juice_oracle/shared/home_shell.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';

import '../test/fake_interpreter.dart';

Future<Oracle> _oracle() async {
  final raw = await rootBundle.loadString('assets/oracle_data.json');
  return Oracle(
      OracleData(jsonDecode(raw) as Map<String, dynamic>), Dice(Random(1)));
}

/// Pump the real launcher-gate wiring: while [launcherGateProvider] is true the
/// app shows [LauncherScreen]; dismissing it reveals [HomeShell] — exactly the
/// `home:` switch in app.dart. This is what makes the test drive the real
/// `_resume`/`_switch` (not SessionResumeScreen in isolation).
Future<ProviderContainer> _pumpLauncher(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'juice.ai_enabled.v1': true,
    ...prefs,
  });
  final fake = FakeInterpreterService(
      initial: const InterpreterStatus(InterpreterPhase.ready));
  final oracle = await _oracle();
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  late ProviderContainer container;
  await tester.pumpWidget(ProviderScope(
    overrides: [interpreterServiceProvider.overrideWithValue(fake)],
    child: Consumer(builder: (context, ref, _) {
      container = ProviderScope.containerOf(context);
      return MaterialApp(
        theme: AppTheme.light(),
        home: ref.watch(launcherGateProvider)
            ? const LauncherScreen()
            : HomeShell(oracle: oracle),
      );
    }),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const sid = 'default';
  // A scene + a prose entry (newest-first) + an open thread, so the resume
  // screen has real content to show.
  const sceneJson =
      '{"id":"e1","timestamp":"2026-01-01T10:00:00.000Z","title":"At the gate","body":"","kind":"scene","tags":[]}';
  const lastEntryJson =
      '{"id":"e2","timestamp":"2026-01-01T11:00:00.000Z","title":"","body":"I draw my sword.","kind":"text","tags":[]}';
  const threadJson =
      '[{"id":"t1","title":"Find the Relic","open":true,"pinned":true,"progress":3}]';

  testWidgets('Continue on a campaign WITH entries shows Session Resume',
      (tester) async {
    await _pumpLauncher(tester, prefs: {
      'juice.sessions.v1':
          '{"active":"$sid","sessions":[{"id":"$sid","name":"C1"}]}',
      'juice.journal.v2.$sid': '[$lastEntryJson,$sceneJson]',
      'juice.threads.v1.$sid': threadJson,
    });

    // Sanity: launcher is up; resume screen is not.
    expect(find.byKey(const Key('launcher-continue')), findsOneWidget);
    expect(find.byType(SessionResumeScreen), findsNothing);

    await tester.tap(find.byKey(const Key('launcher-continue')));
    await tester.pumpAndSettle();

    // The bug: this used to find NOTHING (resume route dropped on gate dismiss).
    expect(find.byType(SessionResumeScreen), findsOneWidget);
    expect(find.byKey(const Key('resume-continue')), findsOneWidget);

    // Continue dismisses the resume screen and lands on a verb (the shell).
    await tester.tap(find.byKey(const Key('resume-continue')));
    await tester.pumpAndSettle();
    expect(find.byType(SessionResumeScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('Continue on a campaign with ZERO entries lands directly',
      (tester) async {
    await _pumpLauncher(tester, prefs: {
      'juice.sessions.v1':
          '{"active":"$sid","sessions":[{"id":"$sid","name":"C1"}]}',
    });

    expect(find.byKey(const Key('launcher-continue')), findsOneWidget);
    await tester.tap(find.byKey(const Key('launcher-continue')));
    await tester.pumpAndSettle();

    // No resume ritual for a fresh campaign — straight onto the shell.
    expect(find.byType(SessionResumeScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets(
      'in-launcher switch to a campaign WITH entries shows Session '
      'Resume', (tester) async {
    // Two campaigns; "default" is active+empty, "other" has prior state. Tapping
    // the "other" row drives _switch (switchTo + resume hop).
    await _pumpLauncher(tester, prefs: {
      'juice.sessions.v1':
          '{"active":"$sid","sessions":[{"id":"$sid","name":"C1"},{"id":"other","name":"C2"}]}',
      'juice.journal.v2.other': '[$lastEntryJson,$sceneJson]',
      'juice.threads.v1.other': threadJson,
    });

    await tester.tap(find.byKey(const Key('launcher-campaign-other')));
    await tester.pumpAndSettle();

    expect(find.byType(SessionResumeScreen), findsOneWidget);
    expect(find.byKey(const Key('resume-continue')), findsOneWidget);
  });
}
