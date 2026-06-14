import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';

import 'fake_interpreter.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

Widget _app() => ProviderScope(
      overrides: [
        oracleProvider.overrideWith((ref) async => _oracle()),
        interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
      ],
      child: const MaterialApp(home: Scaffold(body: JournalScreen())),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('composer has a dice action and no scene button', (t) async {
    await t.pumpWidget(_app());
    await t.pumpAndSettle();
    expect(find.byKey(const Key('composer-dice')), findsOneWidget);
    expect(find.byTooltip('New scene'), findsNothing);
  });

  testWidgets('tapping dice opens the roll sheet', (t) async {
    await t.pumpWidget(_app());
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('composer-dice')));
    await t.pumpAndSettle();
    // The Dice Roller's quick-dice chips appear in the sheet.
    expect(find.text('d20'), findsWidgets);
  });
}
