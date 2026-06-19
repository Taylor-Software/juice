import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/generator_registry.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/generators_screen.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('generator add-to-journal sets sourceTool and payload rolls',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final data = OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: GeneratorsScreen(
                    oracle: Oracle(data), section: GenSection.details)))));
    await tester.pumpAndSettle();

    // Tap 'Name' to generate a result.
    await tester.tap(find.widgetWithText(ActionChip, 'Name'));
    await tester.pumpAndSettle();

    // Tap the ResultCard's log button.
    await tester.tap(find.byTooltip('Add to journal'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(GeneratorsScreen)));
    final entries = container.read(journalProvider).valueOrNull ?? [];
    expect(entries, hasLength(1));
    expect(entries.single.sourceTool, 'gen-details');
    final rolls = entries.single.payload?['rolls'] as List?;
    expect(rolls, isNotNull);
    expect(rolls, isNotEmpty);
  });

  testWidgets('Location: tap rolls, renders grid + compass label, journals',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final data = OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: GeneratorsScreen(
                    oracle: Oracle(data), section: GenSection.exploration)))));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('gen-location')));
    await tester.tap(find.byKey(const Key('gen-location')));
    await tester.pumpAndSettle();

    // The 5x5 grid and a "<compass label> (<roll>)" line render.
    expect(find.byKey(const Key('location-grid')), findsOneWidget);
    expect(
        find.textContaining(
            RegExp(r'^(North|South|East|West|Center|North-West|North-East|'
                r'South-West|South-East) \(\d{1,2}\)$')),
        findsOneWidget);

    // Add-to-journal writes an entry titled 'Location'.
    await tester.tap(find.byKey(const Key('location-log')));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(GeneratorsScreen)));
    final entries = container.read(journalProvider).valueOrNull ?? [];
    expect(entries, hasLength(1));
    expect(entries.single.title, 'Location');
  });
}
