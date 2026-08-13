import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/emulator_data.dart';
import 'package:loreseer/features/behavior_tables_screen.dart';
import 'package:loreseer/features/party_emulator_screen.dart';
import 'package:loreseer/features/party_tools_pane.dart';
import 'package:loreseer/features/sidekick_screen.dart';
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

Override _fakeInterpreterOverride() =>
    interpreterServiceProvider.overrideWithValue(FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready)));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('default (no partyTool set) renders the Emulator paradigm only',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer(
        overrides: [_emulatorOverride, _fakeInterpreterOverride()]);
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: PartyToolsPane())),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(PartyEmulatorScreen), findsOneWidget);
    expect(find.byType(BehaviorTablesScreen), findsNothing);
    expect(find.byType(SidekickScreen), findsNothing);
    expect(find.byKey(const Key('party-tools-switch')), findsNothing);
  });

  testWidgets('partyTool "sidekick" renders only the Sidekick paradigm',
      (tester) async {
    final c = ProviderContainer(overrides: [
      _emulatorOverride,
      _fakeInterpreterOverride(),
      partyToolProvider.overrideWithValue('sidekick'),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: PartyToolsPane())),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SidekickScreen), findsOneWidget);
    expect(find.byType(PartyEmulatorScreen), findsNothing);
    expect(find.byType(BehaviorTablesScreen), findsNothing);
    expect(find.byKey(const Key('party-tools-switch')), findsNothing);
  });
}
