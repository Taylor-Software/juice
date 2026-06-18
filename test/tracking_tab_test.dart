import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/features/tracking_tab.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Track shows the core subtabs and no longer hosts NPCs',
      (t) async {
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: TrackingTab(systems: {}))),
    ));
    await t.pumpAndSettle();
    for (final label in [
      'Scenes',
      'Threads',
      'Rumors',
      'Tracks',
      'Encounter',
    ]) {
      expect(find.widgetWithText(Tab, label), findsOneWidget);
    }
    // NPCs (CharactersPane) moved to the Sheet verb; party subtabs are gated.
    expect(find.widgetWithText(Tab, 'NPCs'), findsNothing);
    expect(find.widgetWithText(Tab, 'Emulator'), findsNothing);
  });
}
