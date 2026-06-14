import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/features/tracks_pane.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('add a track and increment it', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(tracksProvider.future);
    await c.read(tracksProvider.notifier).add('Escape');
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: TracksPane())),
    ));
    await t.pumpAndSettle();
    expect(find.text('Escape'), findsOneWidget);
    await t.tap(find.byKey(const Key('track-inc-0')));
    await t.pumpAndSettle();
    expect(c.read(tracksProvider).value!.single.filled, 1);
  });
}
