import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/oracles_tab.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'Oracles tab shows Oracle/Generators/Tables; Moves hidden with empty family',
      (t) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(home: Scaffold(body: OraclesTab(oracle: _oracle()))),
    ));
    await t.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Oracle'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Generators'), findsNothing);
    expect(find.widgetWithText(Tab, 'Tables'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Moves'), findsNothing);
  });
}
