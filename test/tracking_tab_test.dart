import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
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

  testWidgets('Track shows the core subtabs including Rumors always',
      (t) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
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

  testWidgets('Rumors always shown regardless of mode', (tester) async {
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
    // Rumors always present (no mode gate).
    expect(find.text('Rumors'), findsOneWidget);
    // Party tools present when party system is enabled.
    expect(find.text('Emulator'), findsOneWidget);
  });

  testWidgets('Party tools gated by system, not mode', (tester) async {
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
    // Party tools present because party system is enabled (mode doesn't gate).
    expect(find.text('Rumors'), findsOneWidget);
    expect(find.text('Emulator'), findsOneWidget);
  });
}
