import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/features/rumors_pane.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('adds a rumor through the UI', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(rumorsProvider.future);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: RumorsPane())),
    ));
    await t.tap(find.byKey(const Key('rumors-add')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'Bridge is watched');
    await t.tap(find.text('Add'));
    await t.pumpAndSettle();
    expect(find.text('Bridge is watched'), findsOneWidget);
  });

  testWidgets('toggling a rumor marks it resolved', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(rumorsProvider.future);
    await c.read(rumorsProvider.notifier).add('North gate');
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: RumorsPane())),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byType(Checkbox).first);
    await t.pumpAndSettle();
    expect(c.read(rumorsProvider).value!.single.resolved, isTrue);
  });
}
