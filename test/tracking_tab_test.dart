import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/tracking_tab.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _emulatorData = EmulatorData(
    jsonDecode(File('assets/emulator_data.json').readAsStringSync())
        as Map<String, dynamic>);
final _emulatorOverride =
    emulatorDataProvider.overrideWith((ref) async => _emulatorData);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Adapted: seeds mode:"gm" so Rumors is visible (party mode hides Rumors).
  testWidgets('Track shows the core subtabs and no longer hosts NPCs',
      (t) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1","mode":"gm"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: TrackingTab(systems: {}))),
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

  testWidgets('GM mode shows Rumors, hides party tools', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["party"],"mode":"gm"}]}',
    });
    final c = ProviderContainer(overrides: [_emulatorOverride]);
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: TrackingTab(systems: {'party'})))));
    await tester.pumpAndSettle();
    expect(find.text('Rumors'), findsOneWidget);
    expect(find.text('Emulator'), findsNothing);
  });

  testWidgets('Party mode hides Rumors, shows party tools', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["party"],"mode":"party"}]}',
    });
    final c = ProviderContainer(overrides: [_emulatorOverride]);
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: TrackingTab(systems: {'party'})))));
    await tester.pumpAndSettle();
    expect(find.text('Rumors'), findsNothing);
    expect(find.text('Emulator'), findsOneWidget);
  });
}
