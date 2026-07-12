import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/features/tracker_screen.dart';
import 'package:juice_oracle/features/world_pane.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/state/providers.dart';

void _seed(Map<String, String> scoped) {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    ...scoped,
  });
}

void main() {
  testWidgets('New-task flow on ThreadsPane creates a tallied thread',
      (t) async {
    _seed({
      'juice.threads.v1.default': '[{"id":"a","title":"A plain thread"}]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(threadsProvider.future);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ThreadsPane())),
    ));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('task-new')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('task-name')), 'Slay the dragon');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('task-preset-Difficult task')));
    await t.pumpAndSettle();

    final threads = c.read(threadsProvider).value!;
    final task = threads.firstWhere((x) => x.title == 'Slay the dragon');
    expect(task.tally?.current, 4);
    expect(task.tally?.target, 8);
  });

  testWidgets('WorldPane toggles People/Places and honors legacy routes',
      (t) async {
    _seed({
      'juice.npcs.v1.default': '[{"id":"n1","name":"Brannoc"}]',
      'juice.places.v1.default': '[{"id":"p1","name":"The Vault"}]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(npcsProvider.future);
    await c.read(placesProvider.future);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: WorldPane())),
    ));
    await t.pumpAndSettle();

    // Defaults to People.
    expect(find.text('Brannoc'), findsOneWidget);
    expect(find.text('The Vault'), findsNothing);

    // Manual segment switch (tap the segment's label).
    await t.tap(find.text('Places'));
    await t.pumpAndSettle();
    expect(find.text('The Vault'), findsOneWidget);

    // Legacy route 'people' selects the People segment.
    c
        .read(shellRouteProvider.notifier)
        .goTo(Destination.track, subtab: 'people');
    await t.pumpAndSettle();
    expect(find.text('Brannoc'), findsOneWidget);
    expect(find.text('The Vault'), findsNothing);

    // Legacy route 'places' selects Places.
    c
        .read(shellRouteProvider.notifier)
        .goTo(Destination.track, subtab: 'places');
    await t.pumpAndSettle();
    expect(find.text('The Vault'), findsOneWidget);
  });

  testWidgets('WorldPane mounts on the routed segment', (t) async {
    _seed({
      'juice.places.v1.default': '[{"id":"p1","name":"The Vault"}]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(placesProvider.future);
    c
        .read(shellRouteProvider.notifier)
        .goTo(Destination.track, subtab: 'places');
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: WorldPane())),
    ));
    await t.pumpAndSettle();
    expect(find.text('The Vault'), findsOneWidget);
  });
}
