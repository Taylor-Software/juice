import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/features/tracking_tab.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Tracking shows all six subtabs', (t) async {
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: TrackingTab())),
    ));
    await t.pumpAndSettle();
    for (final label in [
      'Scenes',
      'NPCs',
      'Threads',
      'Rumors',
      'Tracks',
      'Encounter'
    ]) {
      expect(find.widgetWithText(Tab, label), findsOneWidget);
    }
  });
}
