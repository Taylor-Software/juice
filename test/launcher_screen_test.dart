import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/launcher_screen.dart';
import 'package:juice_oracle/state/providers.dart';

class _FixedSessions extends SessionsNotifier {
  _FixedSessions(this.state0);
  final SessionsState state0;
  @override
  Future<SessionsState> build() async => state0;
}

ProviderContainer _container() {
  SharedPreferences.setMockInitialValues({});
  return ProviderContainer(overrides: [
    sessionsProvider.overrideWith(() => _FixedSessions(const SessionsState(
          active: 'a',
          sessions: [
            SessionMeta(id: 'a', name: 'Alpha'),
            SessionMeta(id: 'b', name: 'Beta'),
          ],
        ))),
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
  testWidgets('Continue shows the active campaign and dismisses the gate',
      (t) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(t, c);
    expect(find.textContaining('Alpha'), findsWidgets);
    expect(c.read(launcherGateProvider), isTrue);
    await t.tap(find.byKey(const Key('launcher-continue')));
    await t.pumpAndSettle();
    expect(c.read(launcherGateProvider), isFalse);
  });

  testWidgets('tapping another campaign switches and dismisses', (t) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(t, c);
    await t.tap(find.byKey(const Key('launcher-campaign-b')));
    await t.pumpAndSettle();
    expect(c.read(sessionsProvider).valueOrNull?.active, 'b');
    expect(c.read(launcherGateProvider), isFalse);
  });

  testWidgets('New and Import actions are present', (t) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(t, c);
    expect(find.byKey(const Key('launcher-new')), findsOneWidget);
    expect(find.byKey(const Key('launcher-import')), findsOneWidget);
  });

  testWidgets('rename updates the campaign name', (t) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(t, c);
    await t.tap(find.byKey(const Key('launcher-rename-b')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('rename-field')), 'Gamma');
    await t.tap(find.byKey(const Key('rename-confirm')));
    await t.pumpAndSettle();
    expect(
        c
            .read(sessionsProvider)
            .valueOrNull!
            .sessions
            .firstWhere((m) => m.id == 'b')
            .name,
        'Gamma');
  });

  testWidgets('delete removes a campaign', (t) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(t, c);
    await t.tap(find.byKey(const Key('launcher-delete-b')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('delete-confirm')));
    await t.pumpAndSettle();
    expect(
        c.read(sessionsProvider).valueOrNull!.sessions.any((m) => m.id == 'b'),
        isFalse);
  });
}
