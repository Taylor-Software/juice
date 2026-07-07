import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/custom_table.dart';
import 'package:juice_oracle/engine/loop_kit.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/launcher_screen.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';

import 'fake_interpreter.dart';

class _FixedSessions extends SessionsNotifier {
  _FixedSessions(this.state0);
  final SessionsState state0;
  @override
  Future<SessionsState> build() async => state0;
}

ProviderContainer _container() {
  // The launcher is AI-aware (its _AiOfferGate watches aiSupportedProvider), so
  // every launcher test must supply the fake interpreter — never the real Gemma
  // service. Mark the first-run AI offer already-seen so it doesn't pop over
  // tests that aren't about it.
  SharedPreferences.setMockInitialValues({'juice.ai_offer_seen.v1': true});
  return ProviderContainer(overrides: [
    interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
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

  testWidgets('campaign card shows the enabled-systems badge', (t) async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(overrides: [
      sessionsProvider.overrideWith(() => _FixedSessions(const SessionsState(
            active: 'a',
            sessions: [
              SessionMeta(id: 'a', name: 'Delve', systems: ['dnd', 'mythic']),
            ],
          ))),
    ]);
    addTearDown(c.dispose);
    await _pump(t, c);
    // The welcome card (single fresh campaign) can push the list below the
    // fold in the test viewport — scroll the badge into view rather than
    // depending on card height.
    await t.scrollUntilVisible(find.text('D&D · Mythic'), 100,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('D&D · Mythic'), findsOneWidget);
  });

  ProviderContainer modedContainer() {
    SharedPreferences.setMockInitialValues({'juice.ai_offer_seen.v1': true});
    return ProviderContainer(overrides: [
      interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
      sessionsProvider.overrideWith(() => _FixedSessions(const SessionsState(
            active: 'a',
            sessions: [
              SessionMeta(id: 'a', name: 'Alpha'),
              SessionMeta(id: 'b', name: 'Beta'),
            ],
          ))),
    ]);
  }

  testWidgets('Continue lands on the Journal', (t) async {
    final c = modedContainer();
    addTearDown(c.dispose);
    await _pump(t, c);
    // Point the route elsewhere so the landing is observable.
    c.read(shellRouteProvider.notifier).goTo(Destination.map);
    await t.tap(find.byKey(const Key('launcher-continue')));
    await t.pumpAndSettle();
    expect(c.read(shellRouteProvider).destination, Destination.journal);
  });

  testWidgets('switching campaigns lands on Play', (t) async {
    final c = modedContainer();
    addTearDown(c.dispose);
    await _pump(t, c);
    await t.tap(find.byKey(const Key('launcher-campaign-b')));
    await t.pumpAndSettle();
    expect(c.read(sessionsProvider).valueOrNull?.active, 'b');
    expect(c.read(shellRouteProvider).destination, Destination.journal);
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

  // Regression: the launcher's New-campaign → wizard → Create path must pop a
  // record matching its showDialog<NewCampaignResult> generic. A drifting shape
  // throws a TypeError on pop (caught live on macOS, missed by unit tests that
  // pump the dialog directly). Drives the real launcher caller end to end.
  testWidgets('New campaign wizard (funnel) creates without a type error',
      (t) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(t, c);

    await t.tap(find.byKey(const Key('launcher-new')));
    await t.pumpAndSettle();
    await t.enterText(
        find.byKey(const Key('new-campaign-name')), 'Wizard Funnel');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('wizard-next'))); // -> system + tools
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ruleset-experimental'))); // expand drawer
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('ruleset-dcc')));
    await t.tap(find.byKey(const Key('ruleset-dcc')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('wizard-next'))); // -> start
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('new-start-funnel')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('wizard-create')));
    await t.pumpAndSettle();

    // No TypeError on pop (the bug), the gate dismissed, the campaign exists
    // with the funnel system + a funnel character was seeded.
    expect(t.takeException(), isNull);
    expect(c.read(launcherGateProvider), isFalse);
    final created = c
        .read(sessionsProvider)
        .valueOrNull!
        .sessions
        .firstWhere((m) => m.name == 'Wizard Funnel');
    expect(created.enabledSystems.contains('funnel'), isTrue);
    final chars = await c.read(charactersProvider.future);
    expect(chars.any((ch) => ch.funnel != null), isTrue);
  });

  testWidgets('New campaign wizard (kit) applies the kit after creation',
      (t) async {
    // Two sessions (not one) so the launcher's first-run WelcomeCard branch
    // — an unrelated pre-existing layout quirk, not something this test is
    // about — doesn't engage; mirrors _container()'s default session set.
    final c = ProviderContainer(overrides: [
      interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
      sessionsProvider.overrideWith(() => _FixedSessions(const SessionsState(
            active: 'a',
            sessions: [
              SessionMeta(id: 'a', name: 'Alpha'),
              SessionMeta(id: 'b', name: 'Beta'),
            ],
          ))),
      kitsProvider.overrideWith((ref) async => const [
            LoopKit(
              name: 'Test Kit',
              system: 'ironsworn',
              tables: [
                CustomTable(id: 't1', name: 'Omens', rows: [CustomRow('X')]),
              ],
              sceneTitle: 'Opening Scene',
              sceneBody: 'Body text',
            ),
          ]),
    ]);
    addTearDown(c.dispose);
    SharedPreferences.setMockInitialValues({'juice.ai_offer_seen.v1': true});
    await _pump(t, c);

    await t.tap(find.byKey(const Key('launcher-new')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('new-campaign-name')), 'Wizard Kit');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('wizard-next'))); // -> system + tools
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('wizard-next'))); // -> start
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('new-start-kit')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('kit-pick-0')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('wizard-create')));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    final tables = await c.read(customTablesProvider.future);
    expect(tables.any((tb) => tb.name == 'Omens'), isTrue);
    final journal = await c.read(journalProvider.future);
    expect(journal.any((e) => e.title == 'Opening Scene'), isTrue);
  });

  testWidgets(
      'wizard-next on step 0 stays disabled without a campaign name '
      '(regression: Create used to strand disabled with no feedback)',
      (t) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(t, c);

    await t.tap(find.byKey(const Key('launcher-new')));
    await t.pumpAndSettle();
    // No name entered — only a stance pick.
    await t.pumpAndSettle();

    expect(
        t.widget<FilledButton>(find.byKey(const Key('wizard-next'))).onPressed,
        isNull);

    await t.enterText(find.byKey(const Key('new-campaign-name')), 'Named');
    await t.pumpAndSettle();
    expect(
        t.widget<FilledButton>(find.byKey(const Key('wizard-next'))).onPressed,
        isNotNull);
  });

  testWidgets('New campaign wizard (roster) creates without a type error',
      (t) async {
    // Real (unfixtured) kitsProvider — same as production — so step 2 renders
    // the real "Import a kit" card alongside "Start with a roster".
    final c = _container();
    addTearDown(c.dispose);
    await _pump(t, c);

    await t.tap(find.byKey(const Key('launcher-new')));
    await t.pumpAndSettle();
    await t.enterText(
        find.byKey(const Key('new-campaign-name')), 'Wizard Roster');
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
    final created = c
        .read(sessionsProvider)
        .valueOrNull!
        .sessions
        .firstWhere((m) => m.name == 'Wizard Roster');
    expect(created.enabledSystems.contains('funnel'), isFalse);
  });

  testWidgets(
      'New campaign wizard (roster) works on a true first run (WelcomeCard showing)',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(overrides: [
      interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
      sessionsProvider.overrideWith(() => _FixedSessions(const SessionsState(
            active: 'a',
            sessions: [SessionMeta(id: 'a', name: 'Campaign 1')],
          ))),
    ]);
    addTearDown(c.dispose);
    await _pump(t, c);

    // Sanity: this really is the first-run state the bug report describes.
    // (The AI offer is gated behind the welcome card, so it stays put here.)
    expect(find.text('Welcome'), findsOneWidget);

    await t.scrollUntilVisible(find.byKey(const Key('launcher-new')), 200,
        scrollable: find.byType(Scrollable));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('launcher-new')));
    await t.pumpAndSettle();
    await t.enterText(
        find.byKey(const Key('new-campaign-name')), 'First Run Roster');
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
    expect(sessions.any((m) => m.name == 'First Run Roster'), isTrue,
        reason: 'Campaign should exist after Create: $sessions');
  });
}
