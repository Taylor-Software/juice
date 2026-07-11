import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/launcher_screen.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';

import 'fake_interpreter.dart';

class _FixedSessions extends SessionsNotifier {
  _FixedSessions(this.state0);
  final SessionsState state0;
  @override
  Future<SessionsState> build() async => state0;
}

/// The untouched first-run registry that SessionsNotifier.build() fabricates.
const _pristineState = SessionsState(
  active: 'default',
  sessions: [SessionMeta(id: 'default', name: 'Campaign 1')],
);

ProviderContainer _container(SessionsState sessions,
    {Map<String, Object> prefs = const {}}) {
  SharedPreferences.setMockInitialValues({
    // Welcome + AI offer are not under test; keep them out of the way.
    'juice.welcome_seen.v1': true,
    'juice.ai_offer_seen.v1': true,
    ...prefs,
  });
  return ProviderContainer(overrides: [
    interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
    sessionsProvider.overrideWith(() => _FixedSessions(sessions)),
  ]);
}

Future<void> _pump(WidgetTester t, ProviderContainer c) async {
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: LauncherScreen()),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('pristine first run shows Start-first, hides Continue/list',
      (t) async {
    final c = _container(_pristineState);
    addTearDown(c.dispose);
    await _pump(t, c);

    expect(find.byKey(const Key('launcher-start-first')), findsOneWidget);
    expect(find.byKey(const Key('launcher-skip-blank')), findsOneWidget);
    expect(find.byKey(const Key('launcher-import')), findsOneWidget);
    expect(find.byKey(const Key('launcher-continue')), findsNothing);
    expect(find.byKey(const Key('launcher-campaign-default')), findsNothing);
    expect(find.byKey(const Key('launcher-new')), findsNothing);
  });

  testWidgets('a journaled Campaign 1 gets the normal launcher', (t) async {
    final c = _container(_pristineState, prefs: {
      'juice.journal.v2.default':
          '[{"id":"e1","timestamp":"2026-07-11T00:00:00.000",'
              '"title":"Played","body":"played","kind":"text"}]',
    });
    addTearDown(c.dispose);
    await _pump(t, c);

    expect(find.byKey(const Key('launcher-continue')), findsOneWidget);
    expect(find.byKey(const Key('launcher-start-first')), findsNothing);
  });

  testWidgets('a renamed default campaign gets the normal launcher', (t) async {
    final c = _container(const SessionsState(
      active: 'default',
      sessions: [SessionMeta(id: 'default', name: 'My Saga')],
    ));
    addTearDown(c.dispose);
    await _pump(t, c);

    expect(find.byKey(const Key('launcher-continue')), findsOneWidget);
    expect(find.byKey(const Key('launcher-start-first')), findsNothing);
  });

  testWidgets('skip opens the blank campaign and dismisses the gate',
      (t) async {
    final c = _container(_pristineState);
    addTearDown(c.dispose);
    await _pump(t, c);

    await t.tap(find.byKey(const Key('launcher-skip-blank')));
    await t.pumpAndSettle();
    expect(c.read(launcherGateProvider), isFalse);
    // The placeholder campaign is untouched.
    final sessions = c.read(sessionsProvider).valueOrNull!.sessions;
    expect(sessions.single.id, 'default');
  });

  testWidgets('wizard create from pristine replaces the placeholder',
      (t) async {
    final c = _container(_pristineState);
    addTearDown(c.dispose);
    await _pump(t, c);

    await t.tap(find.byKey(const Key('launcher-start-first')));
    await t.pumpAndSettle();
    await t.enterText(
        find.byKey(const Key('new-campaign-name')), 'First Adventure');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('wizard-next'))); // -> system + tools
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('wizard-next'))); // -> start
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('new-start-roster')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('wizard-create')));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(c.read(launcherGateProvider), isFalse);
    final sessions = c.read(sessionsProvider).valueOrNull!.sessions;
    expect(sessions.any((m) => m.name == 'First Adventure'), isTrue);
    expect(sessions.any((m) => m.id == 'default'), isFalse,
        reason: 'the pristine placeholder should be removed: $sessions');
  });

  testWidgets('cancelling the wizard keeps the pristine launcher', (t) async {
    final c = _container(_pristineState);
    addTearDown(c.dispose);
    await _pump(t, c);

    await t.tap(find.byKey(const Key('launcher-start-first')));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('launcher-start-first')), findsOneWidget);
    final sessions = c.read(sessionsProvider).valueOrNull!.sessions;
    expect(sessions.single.id, 'default');
  });
}
