import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/fate_screen.dart';
import 'package:juice_oracle/features/generators_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every generator belongs to exactly one section', () {
    final seen = <String>{};
    for (final s in GenSection.values) {
      for (final label in GeneratorsScreen.labelsFor(s)) {
        expect(seen.add(label), isTrue, reason: '$label in two sections');
      }
    }
    expect(seen.length, greaterThanOrEqualTo(28));
  });

  test('section labels cover the activity taxonomy', () {
    expect(
        GenSection.values.map((s) => s.label),
        containsAll([
          'Story & Scenes',
          'NPCs & Dialog',
          'Exploration',
          'Encounters & Combat',
          'Names & Details',
        ]));
  });

  testWidgets('initialSection: mythic scrolls on a short viewport',
      (tester) async {
    tester.view.physicalSize = const Size(390, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final data = OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: FateScreen(
                    oracle: Oracle(data),
                    initialSection: FateSection.mythic)))));
    await tester.pumpAndSettle();
    final pos = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(pos.pixels, greaterThan(0));
  });
}
