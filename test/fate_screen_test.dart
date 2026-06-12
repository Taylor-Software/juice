import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/fate_screen.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('selecting a likelihood rolls immediately at that likelihood',
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
            home: Scaffold(body: FateScreen(oracle: Oracle(data))))));
    await tester.pumpAndSettle();

    // No result yet.
    expect(find.textContaining('Intensity:'), findsNothing);

    // Tap a likelihood segment — the result card appears without the
    // Roll Fate Check button being pressed.
    await tester.tap(find.descendant(
        of: find.byType(SegmentedButton<Likelihood>),
        matching: find.text('Likely')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Intensity:'), findsOneWidget);

    // The roll used the tapped likelihood: journaling it records the
    // likelihood in the entry title.
    await tester.tap(find.byTooltip('Add to journal'));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(FateScreen)));
    final entries = container.read(journalProvider).valueOrNull ?? [];
    expect(entries, hasLength(1));
    expect(entries.single.title, 'Fate Check (Likely)');
  });
}
