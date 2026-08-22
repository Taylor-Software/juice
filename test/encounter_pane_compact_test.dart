import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';
import 'package:loreseer/features/encounter_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  void seed(List<Map<String, dynamic>> combatants) {
    SharedPreferences.setMockInitialValues({
      'loreseer.encounter.v1.default': jsonEncode({
        'round': 2,
        'turnIndex': 0,
        'combatants': combatants,
      }),
      'loreseer.sessions.v1': jsonEncode({
        'active': 'default',
        'sessions': [
          {'id': 'default', 'name': 'Campaign 1'}
        ],
      }),
    });
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
        child:
            MaterialApp(home: Scaffold(body: EncounterPane(compact: true)))));
    await tester.pumpAndSettle();
  }

  testWidgets('compact renders glance rows and actions, no manager UI',
      (tester) async {
    seed([
      {
        'id': 'g1',
        'name': 'Goblin',
        'initiative': 12,
        'track': {'current': 4, 'max': 7},
      },
    ]);
    await pump(tester);

    expect(find.byKey(const Key('run-init-row-g1')), findsOneWidget);
    expect(find.text('Goblin'), findsOneWidget);
    expect(find.text('4/7'), findsOneWidget);
    expect(find.byKey(const Key('run-init-next')), findsOneWidget);
    expect(find.byKey(const Key('run-init-roll-all')), findsOneWidget);
    expect(find.byKey(const Key('run-init-open-full')), findsOneWidget);

    // Manager affordances absent in compact mode.
    expect(find.byKey(const Key('enc-attack-g1')), findsNothing);
    expect(find.byKey(const Key('enc-minus-0')), findsNothing);
    expect(find.byKey(const Key('enc-statblock-g1')), findsNothing);
    expect(find.byKey(const Key('add-adhoc')), findsNothing);
    expect(find.byKey(const Key('end-encounter')), findsNothing);
  });

  testWidgets('compact empty state', (tester) async {
    seed([]);
    await pump(tester);
    expect(find.byKey(const Key('run-init-empty')), findsOneWidget);
  });
}
