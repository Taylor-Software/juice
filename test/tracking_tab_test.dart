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
    expect(find.widgetWithText(Tab, 'Party'), findsNothing);
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
    expect(find.widgetWithText(Tab, 'Party'), findsOneWidget);
  });

  testWidgets('Party subtab hosts Emulator/Behavior/Sidekick behind a switch',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["party"]}]}',
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
    // Open the one Party subtab.
    await tester.tap(find.widgetWithText(Tab, 'Party'));
    await tester.pumpAndSettle();
    // The internal switch + all three surfaces are reachable.
    expect(find.byKey(const Key('party-tools-switch')), findsOneWidget);
    // Emulator is the default surface.
    expect(find.byKey(const Key('pe-pet-actions')), findsOneWidget);
    // Switch to Sidekick.
    await tester.tap(find.text('Sidekick'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pe-pet-actions')), findsNothing);
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
    expect(find.widgetWithText(Tab, 'Party'), findsOneWidget);
  });
}
