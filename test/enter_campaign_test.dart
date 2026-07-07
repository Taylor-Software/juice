import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/enter_campaign.dart';
import 'package:juice_oracle/features/session_resume_screen.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty entries — land called, no push', (t) async {
    final container = ProviderContainer(overrides: [
      interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
    ]);
    addTearDown(container.dispose);

    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SizedBox())),
    ));

    final nav = t.state<NavigatorState>(find.byType(Navigator));
    final shellRoute = container.read(shellRouteProvider.notifier);

    await enterCampaignWith(
      nav: nav,
      shellRoute: shellRoute,
      entries: const [],
      hasEncounter: false,
    );

    // no encounter → Play (journal) destination
    expect(
      container.read(shellRouteProvider).destination,
      Destination.journal,
    );
    // nothing pushed onto the navigator
    expect(nav.canPop(), isFalse);
  });

  testWidgets('empty entries with encounter — lands on Track/encounter',
      (t) async {
    final container = ProviderContainer(overrides: [
      interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
    ]);
    addTearDown(container.dispose);

    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SizedBox())),
    ));

    final nav = t.state<NavigatorState>(find.byType(Navigator));
    final shellRoute = container.read(shellRouteProvider.notifier);

    await enterCampaignWith(
      nav: nav,
      shellRoute: shellRoute,
      entries: const [],
      hasEncounter: true,
    );

    final route = container.read(shellRouteProvider);
    expect(route.destination, Destination.track);
    expect(route.subtab, 'encounter');
    expect(nav.canPop(), isFalse);
  });

  testWidgets('non-empty entries — SessionResumeScreen pushed', (t) async {
    final container = ProviderContainer(overrides: [
      interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
    ]);
    addTearDown(container.dispose);

    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SizedBox())),
    ));

    final nav = t.state<NavigatorState>(find.byType(Navigator));
    final shellRoute = container.read(shellRouteProvider.notifier);

    final entry = JournalEntry(
      id: 'e1',
      kind: JournalKind.result,
      title: 'First roll',
      body: 'A test entry.',
      timestamp: DateTime(2026, 1, 1),
    );

    // Don't await — push returns only when route pops (never in this test)
    unawaited(enterCampaignWith(
      nav: nav,
      shellRoute: shellRoute,
      entries: [entry],
      hasEncounter: false,
    ));

    await t.pumpAndSettle();

    expect(find.byType(SessionResumeScreen), findsOneWidget);
    // shellRoute not changed — land not called
    expect(
      container.read(shellRouteProvider).destination,
      Destination.journal,
    );
  });
}
