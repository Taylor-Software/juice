import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/tracker_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const seeded =
      '[{"id":"c1","name":"Ash","note":"","stats":[],"tracks":[{"label":"HP","current":7,"max":10}],"tags":[]}]';

  // The Threads/Characters tab chrome now lives in tracking_tab.dart; these
  // tests pump the public panes directly.
  Future<ProviderContainer> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': seeded,
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  Future<ProviderContainer> pumpThreads(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.threads.v1.default':
          '[{"id":"t1","title":"Find the Relic","open":true}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ThreadsPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(ThreadsPane)));
  }

  testWidgets('list row shows first-track summary', (tester) async {
    await pump(tester);
    expect(find.text('Ash'), findsOneWidget);
    expect(find.text('HP 7/10'), findsOneWidget);
  });

  testWidgets('track steppers adjust and persist, clamped', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('track-plus-0')));
    await tester.pumpAndSettle();
    expect(find.text('8/10'), findsOneWidget);
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.tracks.single.current, 8);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('track-plus-0')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('10/10'), findsOneWidget);
  });

  testWidgets('add stat and tag from the editor; back returns to list',
      (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-stat')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stat-label')), 'Iron');
    await tester.enterText(find.byKey(const Key('stat-value')), '+2');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Iron'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-tag')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tag-input')), 'wounded');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('wounded'), findsOneWidget);
    final c = (await container.read(charactersProvider.future)).single;
    expect(c.stats.single.value, '+2');
    expect(c.tags, ['wounded']);
    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    expect(find.text('HP 7/10'), findsOneWidget);
  });

  testWidgets('sheet shows the emulation summary only when emulation exists',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"c1","name":"Ash","note":"","stats":[],"tracks":[],"tags":[]},'
              '{"id":"c2","name":"Em","note":"","stats":[],"tracks":[],"tags":["brave"],'
              '"emulation":{"tokens":3,"prominentTags":["brave","bold"],"usedTags":[]}}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Em'));
    await tester.pumpAndSettle();
    expect(
        find.text('Emulation: 2 prominent traits · 3 tokens'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Emulation:'), findsNothing);
  });

  testWidgets('sheet falls back to list when the character disappears',
      (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sheet-back')), findsOneWidget);
    // Character removed underneath the open sheet (session switch, import…).
    await container.read(charactersProvider.notifier).remove('c1');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('sheet-back')), findsNothing);
    expect(find.textContaining('No characters yet'), findsOneWidget);
  });

  testWidgets('character list row has star IconButton that toggles starred',
      (tester) async {
    final container = await pump(tester);
    // Star button present in list row.
    expect(find.byKey(const Key('star-char-c1')), findsOneWidget);
    // Initially not starred.
    expect((await container.read(charactersProvider.future)).single.starred,
        isFalse);
    // Tap star → starred.
    await tester.tap(find.byKey(const Key('star-char-c1')));
    await tester.pumpAndSettle();
    expect((await container.read(charactersProvider.future)).single.starred,
        isTrue);
    // Tap again → unstarred.
    await tester.tap(find.byKey(const Key('star-char-c1')));
    await tester.pumpAndSettle();
    expect((await container.read(charactersProvider.future)).single.starred,
        isFalse);
  });

  testWidgets('thread list row has pin IconButton that toggles pinned',
      (tester) async {
    final container = await pumpThreads(tester);
    // Pin button present.
    expect(find.byKey(const Key('pin-thread-t1')), findsOneWidget);
    // Initially not pinned.
    expect(
        (await container.read(threadsProvider.future)).single.pinned, isFalse);
    // Tap pin → pinned.
    await tester.tap(find.byKey(const Key('pin-thread-t1')));
    await tester.pumpAndSettle();
    expect(
        (await container.read(threadsProvider.future)).single.pinned, isTrue);
    // Tap again → unpinned.
    await tester.tap(find.byKey(const Key('pin-thread-t1')));
    await tester.pumpAndSettle();
    expect(
        (await container.read(threadsProvider.future)).single.pinned, isFalse);
  });
}
