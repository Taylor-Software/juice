import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/generate_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

void main() {
  testWidgets('lists flavor generators (not the entity ones)', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
    });
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => _oracle()),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: GenerateSheet()))));
    await tester.pumpAndSettle();
    expect(find.text('Pay the Price'), findsOneWidget);
    expect(find.text('Random Event'), findsOneWidget);
    // entity generators are NOT in the flavor sheet:
    expect(find.text('New Scene'), findsNothing);
    expect(find.text('Monster Encounter'), findsNothing);
  });

  testWidgets('tapping a generator adds a journal entry', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
    });
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => _oracle()),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: GenerateSheet()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay the Price'));
    await tester.pumpAndSettle();
    final entries = await c.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.sourceTool, 'gen-story');
  });
}
