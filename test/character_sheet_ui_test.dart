import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/tracker_screen.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const seeded =
      '[{"id":"c1","name":"Ash","note":"","stats":[],"tracks":[{"label":"HP","current":7,"max":10}],"tags":[]}]';

  Future<ProviderContainer> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': seeded,
    });
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: TrackerScreen()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Characters'));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(TrackerScreen)));
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
}
