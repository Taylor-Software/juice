import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/assistant_rail.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Future<ProviderContainer> pumpRail(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.journal.v2.default': '[]',
    'juice.threads.v1.default': '[]',
  });
  final c = ProviderContainer();
  await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AssistantRail()))));
  await tester.pumpAndSettle();
  return c;
}

/// The rail is collapsed by default; reveal the chips + ask box.
Future<void> expandRail(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('assistant-expand')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('collapsed by default; chips hidden until expanded',
      (tester) async {
    await pumpRail(tester);
    expect(find.text('Roll the oracle'), findsNothing);
    await expandRail(tester);
    expect(find.text('Roll the oracle'), findsOneWidget);
  });

  testWidgets('navigate chip routes via shellRouteProvider', (tester) async {
    final c = await pumpRail(tester); // empty campaign → start-scene present
    await expandRail(tester);
    await tester.tap(find.text('Start a scene'));
    await tester.pumpAndSettle();
    final route = c.read(shellRouteProvider);
    expect(route.destination, Destination.track);
    expect(route.subtab, 'scenes');
  });

  testWidgets('ask-the-GM writes a Q&A journal entry via the fake',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
      'juice.threads.v1.default': '[]',
    });
    final fake = FakeInterpreterService(
      initial: const InterpreterStatus(InterpreterPhase.ready),
    )..queuedAskGm.add('The door is barred from within.');
    final c = ProviderContainer(overrides: [
      interpreterServiceProvider.overrideWith((ref) => fake),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: AssistantRail()))));
    await tester.pumpAndSettle();

    await expandRail(tester);
    await tester.enterText(find.byKey(const Key('ask-gm-field')), 'Locked?');
    await tester.tap(find.byKey(const Key('ask-gm-send')));
    await tester.pumpAndSettle();

    expect(fake.askGmCalls, 1);
    final entries = await c.read(journalProvider.future);
    expect(entries.first.body, contains('The door is barred from within.'));
    expect(entries.first.body, contains('Locked?'));
  });
}
