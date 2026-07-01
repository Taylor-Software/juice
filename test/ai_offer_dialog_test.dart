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

/// Pump the real launcher with a fake interpreter (so on-device AI reports
/// "supported"), a single session, and caller-chosen prefs.
Future<ProviderContainer> _pump(
  WidgetTester t, {
  required Map<String, Object> prefs,
  FakeInterpreterService? fake,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final c = ProviderContainer(overrides: [
    interpreterServiceProvider
        .overrideWithValue(fake ?? FakeInterpreterService()),
    sessionsProvider.overrideWith(() => _FixedSessions(const SessionsState(
          active: 'a',
          sessions: [SessionMeta(id: 'a', name: 'Campaign 1')],
        ))),
  ]);
  addTearDown(c.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: LauncherScreen()),
  ));
  await t.pumpAndSettle();
  return c;
}

void main() {
  // welcomeSeen=true → the welcome card is gone → the offer gate is free to
  // fire on first run.
  const firstRunPrefs = {'juice.welcome_seen.v1': true};

  testWidgets('offer appears on first run when AI is supported and unenabled',
      (t) async {
    await _pump(t, prefs: firstRunPrefs);
    expect(find.byKey(const Key('ai-offer-dialog')), findsOneWidget);
    expect(find.byKey(const Key('ai-offer-enable')), findsOneWidget);
    expect(find.byKey(const Key('ai-offer-later')), findsOneWidget);
  });

  testWidgets('Enable & download flips AI on, starts the download, marks seen',
      (t) async {
    final fake = FakeInterpreterService();
    final c = await _pump(t, prefs: firstRunPrefs, fake: fake);

    await t.tap(find.byKey(const Key('ai-offer-enable')));
    await t.pumpAndSettle();

    expect(c.read(aiEnabledProvider).valueOrNull, isTrue);
    expect(fake.warmUpCalls, 1, reason: 'download should have been kicked off');
    expect(c.read(aiOfferSeenProvider).valueOrNull, isTrue);
    // The dialog is gone and a background-download SnackBar confirms.
    expect(find.byKey(const Key('ai-offer-dialog')), findsNothing);
    expect(find.textContaining('Downloading the AI model'), findsOneWidget);
  });

  testWidgets('Not now marks seen without enabling or downloading', (t) async {
    final fake = FakeInterpreterService();
    final c = await _pump(t, prefs: firstRunPrefs, fake: fake);

    await t.tap(find.byKey(const Key('ai-offer-later')));
    await t.pumpAndSettle();

    expect(c.read(aiEnabledProvider).valueOrNull, isFalse);
    expect(fake.warmUpCalls, 0);
    expect(c.read(aiOfferSeenProvider).valueOrNull, isTrue);
    expect(find.byKey(const Key('ai-offer-dialog')), findsNothing);
  });

  testWidgets('offer does not appear while the welcome card is showing',
      (t) async {
    // welcomeSeen defaults false + a single session → welcome shows → gated.
    await _pump(t, prefs: const {});
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.byKey(const Key('ai-offer-dialog')), findsNothing);
  });

  testWidgets('offer does not reappear once seen', (t) async {
    await _pump(t, prefs: const {
      'juice.welcome_seen.v1': true,
      'juice.ai_offer_seen.v1': true,
    });
    expect(find.byKey(const Key('ai-offer-dialog')), findsNothing);
  });

  testWidgets('offer does not appear when AI is already enabled', (t) async {
    await _pump(t, prefs: const {
      'juice.welcome_seen.v1': true,
      'juice.ai_enabled.v1': true,
    });
    expect(find.byKey(const Key('ai-offer-dialog')), findsNothing);
  });

  testWidgets('offer does not appear when the platform lacks on-device AI',
      (t) async {
    // unsupported phase → aiSupportedProvider is false.
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.unsupported));
    await _pump(t, prefs: firstRunPrefs, fake: fake);
    expect(find.byKey(const Key('ai-offer-dialog')), findsNothing);
  });
}
