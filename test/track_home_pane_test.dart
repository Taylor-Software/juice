import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/track_home_pane.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A scene journal entry (newest-first; the dashboard's NOW card falls back to
/// the newest scene when no activeSceneId is pinned).
const _sceneJson =
    '{"id":"s1","timestamp":"2026-06-20T10:00:00.000Z","title":"The Ruined Gate",'
    '"body":"Cold wind through the arch.","kind":"scene","tags":[],"pinned":false}';

const _baseSession =
    '{"active":"default","sessions":[{"id":"default","name":"C1","mode":"gm"}]}';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Map<String, Object> prefs,
}) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1': _baseSession,
    ...prefs,
  });
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await c.read(sessionsProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: TrackHomePane()),
    ),
  ));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('renders summary cards from seeded state', (tester) async {
    final c = await _pump(tester, prefs: {
      // Dismiss the orientation card so the summary cards aren't pushed
      // off-screen by the extra leading card.
      'juice.track_help_seen.v1': true,
      'juice.journal.v2.default': '[$_sceneJson]',
      'juice.threads.v1.default':
          '[{"id":"t1","title":"Find the Relic","open":true,"progress":3},'
              '{"id":"t2","title":"Closed quest","open":false}]',
      'juice.characters.v1.default': '[{"id":"c1","name":"Ash","stats":[],'
          '"tracks":[{"label":"HP","current":4,"max":5}],"tags":[]}]',
      // Idle encounter: no combatants.
      'juice.encounter.v1.default': '{"combatants":[],"turnIndex":0,"round":1}',
    });

    // NOW card shows the active scene title.
    expect(find.byKey(const Key('track-home-now')), findsOneWidget);
    expect(find.text('The Ruined Gate'), findsOneWidget);

    // THREADS card shows the open count (1 open of 2 total).
    expect(find.byKey(const Key('track-home-threads')), findsOneWidget);
    expect(find.textContaining('1 open'), findsOneWidget);
    expect(find.text('Find the Relic'), findsOneWidget);
    // Progress bars + n/max readout replace the per-row Open/Closed pill.
    expect(
        find.descendant(
          of: find.byKey(const Key('track-home-threads')),
          matching: find.byType(LinearProgressIndicator),
        ),
        findsWidgets);
    expect(find.text('3/10'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
    expect(find.text('Closed'), findsNothing);

    // PARTY card shows the PC + its HP chip.
    expect(find.byKey(const Key('track-home-party')), findsOneWidget);
    expect(find.text('Ash'), findsOneWidget);
    expect(find.text('4/5'), findsOneWidget);

    // ENCOUNTER card exists and is Idle.
    expect(find.byKey(const Key('track-home-encounter')), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);

    c.dispose();
  });

  testWidgets('tapping the THREADS card navigates to the threads subtab',
      (tester) async {
    final c = await _pump(tester, prefs: {
      'juice.threads.v1.default':
          '[{"id":"t1","title":"Find the Relic","open":true}]',
    });

    // Default route is the journal home; nothing aimed at Track yet.
    expect(c.read(shellRouteProvider).destination, Destination.journal);

    await tester.tap(find.byKey(const Key('track-home-threads')));
    await tester.pumpAndSettle();

    final route = c.read(shellRouteProvider);
    expect(route.destination, Destination.track);
    expect(route.subtab, 'threads');

    c.dispose();
  });

  testWidgets('tapping the PARTY card navigates to the Sheet verb',
      (tester) async {
    final c = await _pump(tester, prefs: {
      'juice.characters.v1.default':
          '[{"id":"c1","name":"Ash","stats":[],"tracks":[],"tags":[]}]',
    });

    await tester.tap(find.byKey(const Key('track-home-party')));
    await tester.pumpAndSettle();

    expect(c.read(shellRouteProvider).destination, Destination.sheet);

    c.dispose();
  });

  testWidgets('a live encounter renders the emphasized round state',
      (tester) async {
    await _pump(tester, prefs: {
      'juice.encounter.v1.default':
          '{"combatants":[{"id":"k1","name":"Goblin","characterId":null,'
              '"initiative":12,"track":{"label":"HP","current":3,"max":5},'
              '"tags":[],"defeated":false}],"turnIndex":0,"round":2}',
    });

    expect(find.byKey(const Key('track-home-encounter')), findsOneWidget);
    // Live: shows the round and the in-fight count, not "Idle".
    expect(find.text('Round 2'), findsOneWidget);
    expect(find.textContaining('in the fight'), findsOneWidget);
    expect(find.text('Idle'), findsNothing);
  });

  testWidgets('empty state is defensive (no scene / threads / party)',
      (tester) async {
    // Dismiss the orientation card so all summary cards fit the viewport.
    await _pump(tester, prefs: const {'juice.track_help_seen.v1': true});
    expect(find.text('No scene yet'), findsOneWidget);
    // Every card still renders.
    expect(find.byKey(const Key('track-home-now')), findsOneWidget);
    expect(find.byKey(const Key('track-home-threads')), findsOneWidget);
    expect(find.byKey(const Key('track-home-tracks')), findsOneWidget);
    expect(find.byKey(const Key('track-home-party')), findsOneWidget);
    expect(find.byKey(const Key('track-home-encounter')), findsOneWidget);
  });

  testWidgets('orientation card shows by default and dismiss persists',
      (tester) async {
    final c = await _pump(tester, prefs: const {});
    expect(find.byKey(const Key('track-help-card')), findsOneWidget);

    await tester.tap(find.byKey(const Key('track-help-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('track-help-card')), findsNothing);
    expect(c.read(trackHelpSeenProvider).valueOrNull, isTrue);

    c.dispose();
  });

  testWidgets('orientation card hidden once seen', (tester) async {
    final c = await _pump(tester, prefs: const {
      'juice.track_help_seen.v1': true,
    });
    expect(find.byKey(const Key('track-help-card')), findsNothing);
    c.dispose();
  });
}
