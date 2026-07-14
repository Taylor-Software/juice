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

  testWidgets('the composer field stays writable-wide on a phone', (t) async {
    // The trailing actions are an Expanded field's only competition, and they
    // accreted one per feature until six of them squeezed the field to ~58px on
    // a 390pt phone — you could not see the line you were typing. Guard the
    // field's share of the row, not the icon count: the next feature is free to
    // add an action as long as it does not re-crowd the field.
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(390, 800);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(_app());
    await t.pumpAndSettle();

    // blobStoreAvailable/pdfAvailable are `!kIsWeb`, so this pumps the same
    // full set of actions a phone shows. The floor is a third of the row: the
    // broken layout gave the field 58px, the current one ~142px.
    final width = t.getSize(find.byKey(const Key('journal-composer'))).width;
    expect(width, greaterThan(130),
        reason: 'the composer field got $width of 390 — the trailing actions '
            'are crowding it out; move one behind the composer-attach menu');
  });
}
