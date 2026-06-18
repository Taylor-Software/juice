import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/sheet_tab.dart';
import 'package:juice_oracle/features/tracker_screen.dart';
import 'package:juice_oracle/features/tracking_tab.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('SheetTab with no family renders the roster only',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': '[]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: SheetTab(family: [])))));
    await tester.pumpAndSettle();
    expect(find.byType(CharactersPane), findsOneWidget);
    expect(find.text('Characters'), findsNothing); // no subtab bar
  });

  testWidgets('Track shows party subtabs only when party system is on',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["party"]}]}',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: TrackingTab(systems: {'party'})))));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Emulator'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Scenes'), findsOneWidget);
  });
}
