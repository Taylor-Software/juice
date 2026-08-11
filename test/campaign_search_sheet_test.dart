import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/features/campaign_search_sheet.dart';
import 'package:loreseer/shared/destination.dart';
import 'package:loreseer/shared/shell_route.dart';
import 'package:loreseer/shared/theme.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// campaign_search_test.dart covers the pure `searchCampaign`. This covers the
/// SHEET around it — in particular the 250 ms debounce, which was entirely
/// unexercised even though the feature shipped.
Future<ProviderContainer> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'loreseer.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'loreseer.journal.v2.default': jsonEncode([
      {
        'id': 'j1',
        'timestamp': DateTime(2026, 1, 1).toIso8601String(),
        'title': 'The salt marsh',
        'body': 'Reeds and standing water.',
      },
    ]),
    'loreseer.threads.v1.default': jsonEncode([
      {'id': 't1', 'title': 'Find the salt road', 'open': true},
    ]),
  });
  final container = ProviderContainer();
  addTearDown(container.dispose);
  // Warm the lists so the first frame has data.
  await container.read(journalProvider.future);
  await container.read(threadsProvider.future);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: CampaignSearchSheet()),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('opens listing everything until a query narrows it',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('campaign-search-field')), findsOneWidget);
    // An empty query is "show me the campaign", not "show me nothing".
    expect(
        find.byKey(const Key('search-result-journalEntry-j1')), findsOneWidget);
    expect(find.byKey(const Key('search-result-thread-t1')), findsOneWidget);
  });

  testWidgets('the query is not applied until the debounce elapses',
      (tester) async {
    await _pump(tester);
    // Type something that matches NOTHING: the row should linger while the
    // debounce is pending, then disappear once it fires.
    await tester.enterText(
        find.byKey(const Key('campaign-search-field')), 'zzzznothing');

    await tester.pump(const Duration(milliseconds: 100));
    expect(
        find.byKey(const Key('search-result-journalEntry-j1')), findsOneWidget,
        reason: 'the 250ms debounce should still be pending');

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('search-result-journalEntry-j1')), findsNothing);
    expect(find.textContaining('No results for'), findsOneWidget);
  });

  testWidgets('one query matches across entity types', (tester) async {
    await _pump(tester);
    await tester.enterText(
        find.byKey(const Key('campaign-search-field')), 'salt');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('search-result-journalEntry-j1')), findsOneWidget);
    expect(find.byKey(const Key('search-result-thread-t1')), findsOneWidget);
  });

  testWidgets('a non-matching query clears the results', (tester) async {
    await _pump(tester);
    final field = find.byKey(const Key('campaign-search-field'));
    await tester.enterText(field, 'salt');
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        find.byKey(const Key('search-result-journalEntry-j1')), findsOneWidget);

    await tester.enterText(field, 'zzzznothing');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('search-result-journalEntry-j1')), findsNothing);
  });

  testWidgets('tapping a journal result routes to the Journal verb',
      (tester) async {
    final c = await _pump(tester);
    await tester.enterText(
        find.byKey(const Key('campaign-search-field')), 'salt');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-result-journalEntry-j1')));
    await tester.pumpAndSettle();
    expect(c.read(shellRouteProvider).destination, Destination.journal);
  });

  testWidgets('tapping a thread result routes to Track > threads',
      (tester) async {
    final c = await _pump(tester);
    await tester.enterText(
        find.byKey(const Key('campaign-search-field')), 'salt');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-result-thread-t1')));
    await tester.pumpAndSettle();
    final route = c.read(shellRouteProvider);
    expect(route.destination, Destination.track);
    expect(route.subtab, 'threads');
  });

  testWidgets('a pending debounce is cancelled on dispose', (tester) async {
    await _pump(tester);
    await tester.enterText(
        find.byKey(const Key('campaign-search-field')), 'salt');
    // Tear the sheet down mid-debounce; the timer must not fire into a dead
    // State (which would throw and fail this test).
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
