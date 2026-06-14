import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/features/scenes_pane.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/shared/destination.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists scenes and a New scene action', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    await c.read(journalProvider.notifier).addScene('The Crossing');
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ScenesPane())),
    ));
    await t.pumpAndSettle();
    expect(find.text('The Crossing'), findsOneWidget);
    expect(find.byKey(const Key('scenes-new')), findsOneWidget);
  });

  testWidgets('tapping a scene navigates to Journal', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    await c.read(journalProvider.notifier).addScene('The Crossing');
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ScenesPane())),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('The Crossing'));
    await t.pumpAndSettle();
    expect(c.read(shellRouteProvider).destination, Destination.journal);
  });
}
