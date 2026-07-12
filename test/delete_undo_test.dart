import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/features/tracks_pane.dart';
import 'package:juice_oracle/state/providers.dart';

void _seed(Map<String, String> scoped) {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    ...scoped,
  });
}

void main() {
  test('restoreAt re-inserts a deleted row at its old index', () async {
    _seed({
      'juice.threads.v1.default':
          '[{"id":"a","title":"A"},{"id":"b","title":"B"},{"id":"c","title":"C"}]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final threads = await c.read(threadsProvider.future);
    final doomed = threads[1];

    await c.read(threadsProvider.notifier).remove('b');
    expect(c.read(threadsProvider).value!.map((t) => t.id), ['a', 'c']);

    await c.read(threadsProvider.notifier).restoreAt(1, doomed);
    expect(c.read(threadsProvider).value!.map((t) => t.id), ['a', 'b', 'c']);
  });

  test('restoreAt clamps an out-of-range index', () async {
    _seed({
      'juice.threads.v1.default': '[{"id":"a","title":"A"}]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final only = (await c.read(threadsProvider.future)).single;

    await c.read(threadsProvider.notifier).remove('a');
    await c.read(threadsProvider.notifier).restoreAt(99, only);
    expect(c.read(threadsProvider).value!.single.id, 'a');
  });

  test('undismiss returns a dismissed suggestion key', () async {
    _seed({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(dismissedSuggestionsProvider.future);

    await c.read(dismissedSuggestionsProvider.notifier).dismiss('char:Kara');
    expect(c.read(dismissedSuggestionsProvider).value, contains('char:Kara'));

    await c.read(dismissedSuggestionsProvider.notifier).undismiss('char:Kara');
    expect(c.read(dismissedSuggestionsProvider).value,
        isNot(contains('char:Kara')));
  });

  testWidgets('track delete shows an Undo snackbar that restores the track',
      (t) async {
    _seed({
      'juice.tracks.v1.default': '[{"id":"tk","name":"Doom clock"}]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(tracksProvider.future);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: TracksPane())),
    ));
    await t.pumpAndSettle();

    // Delete via the row's popup menu.
    await t.tap(find.byType(PopupMenuButton<String>).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(c.read(tracksProvider).value, isEmpty);
    expect(find.text('Track deleted'), findsOneWidget);

    // Undo brings it back.
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(c.read(tracksProvider).value!.single.name, 'Doom clock');
  });
}
