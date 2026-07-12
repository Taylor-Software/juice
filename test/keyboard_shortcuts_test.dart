import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/engine/lonelog_data.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/engine/verdant_data.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/home_shell.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';

import 'fake_interpreter.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));
final _verdant = VerdantData(
    jsonDecode(File('assets/verdant_data.json').readAsStringSync())
        as Map<String, dynamic>);
final _emu = EmulatorData(
    jsonDecode(File('assets/emulator_data.json').readAsStringSync())
        as Map<String, dynamic>);
final _lonelog = LonelogData(
    jsonDecode(File('assets/lonelog_data.json').readAsStringSync())
        as Map<String, dynamic>);
final _hex = HexcrawlData(
    jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
        as Map<String, dynamic>);

Future<void> _combo(WidgetTester t, LogicalKeyboardKey key,
    {bool shift = false}) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(key);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Cmd+Enter logs the composer text', (t) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.ai_nudge_seen.v1': true,
    });
    final c = ProviderContainer(overrides: [
      interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: JournalScreen()),
      ),
    ));
    await t.pumpAndSettle();

    await t.enterText(
        find.byKey(const Key('journal-composer')), 'The mill burns.');
    await _combo(t, LogicalKeyboardKey.enter);

    final entries = c.read(journalProvider).value!;
    expect(entries.single.body, 'The mill burns.');
  });

  testWidgets('Cmd+Shift+N opens the New-scene dialog', (t) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.ai_nudge_seen.v1': true,
    });
    await t.pumpWidget(ProviderScope(
      overrides: [
        interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: JournalScreen()),
      ),
    ));
    await t.pumpAndSettle();

    // Focus the composer so the journal subtree owns focus.
    await t.tap(find.byKey(const Key('journal-composer')));
    await t.pump();
    await _combo(t, LogicalKeyboardKey.keyN, shift: true);
    expect(find.text('New scene'), findsWidgets);
  });

  testWidgets('Cmd+K opens campaign search from the shell', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(ProviderScope(
      overrides: [
        verdantDataProvider.overrideWith((ref) async => _verdant),
        emulatorDataProvider.overrideWith((ref) async => _emu),
        lonelogDataProvider.overrideWith((ref) async => _lonelog),
        hexcrawlDataProvider.overrideWith((ref) async => _hex),
      ],
      child: MaterialApp(home: HomeShell(oracle: _oracle())),
    ));
    await t.pumpAndSettle();

    await _combo(t, LogicalKeyboardKey.keyK);
    expect(find.byKey(const Key('campaign-search-field')), findsOneWidget);
  });
}
