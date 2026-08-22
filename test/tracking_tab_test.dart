import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loreseer/engine/emulator_data.dart';
import 'package:loreseer/features/tracker_screen.dart';
import 'package:loreseer/features/tracking_tab.dart';
import 'package:loreseer/shared/destination.dart';
import 'package:loreseer/shared/shell_route.dart';
import 'package:loreseer/shared/theme.dart';
import 'package:loreseer/state/interpreter.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

final _emulatorData = EmulatorData(
    jsonDecode(File('assets/emulator_data.json').readAsStringSync())
        as Map<String, dynamic>);
final _emulatorOverride =
    emulatorDataProvider.overrideWith((ref) async => _emulatorData);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Track shows the core subtabs', (t) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
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
      'Encounter',
    ]) {
      expect(find.widgetWithText(Tab, label), findsOneWidget);
    }
    // Rumors/Tracks tabs are retired; Threads absorbs them via aliases.
    expect(find.widgetWithText(Tab, 'Rumors'), findsNothing);
    expect(find.widgetWithText(Tab, 'Tracks'), findsNothing);
    // NPCs (CharactersPane) moved to the Sheet verb; party subtabs are gated.
    expect(find.widgetWithText(Tab, 'NPCs'), findsNothing);
    expect(find.widgetWithText(Tab, 'Party'), findsNothing);
  });

  testWidgets('legacy rumors/tracks routes land on Threads', (t) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
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

    c
        .read(shellRouteProvider.notifier)
        .goTo(Destination.track, subtab: 'rumors');
    await t.pumpAndSettle();
    expect(find.byType(ThreadsPane), findsOneWidget);

    c
        .read(shellRouteProvider.notifier)
        .goTo(Destination.track, subtab: 'tracks');
    await t.pumpAndSettle();
    expect(find.byType(ThreadsPane), findsOneWidget);
  });

  testWidgets('Party tools shown when party system is enabled', (tester) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
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
    // Party tools present when party system is enabled.
    expect(find.widgetWithText(Tab, 'Party'), findsOneWidget);
  });

  testWidgets('Party subtab hosts the campaign\'s chosen party tool',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["party"],"partyTool":"sidekick"}]}',
    });
    final c = ProviderContainer(overrides: [
      _emulatorOverride,
      interpreterServiceProvider.overrideWithValue(FakeInterpreterService(
          initial: const InterpreterStatus(InterpreterPhase.ready))),
    ]);
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
    // No switch anymore — the campaign's chosen paradigm (sidekick) renders
    // directly; the emulator surface is absent.
    expect(find.byKey(const Key('party-tools-switch')), findsNothing);
    expect(find.byKey(const Key('pe-pet-actions')), findsNothing);
  });

  testWidgets('Party tools gated by system, not mode', (tester) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
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
    expect(find.widgetWithText(Tab, 'Party'), findsOneWidget);
  });
}
