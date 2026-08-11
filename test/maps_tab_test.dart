import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loreseer/features/maps_tab.dart';
import 'package:loreseer/engine/oracle.dart';
import 'package:loreseer/engine/oracle_data.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Maps tab shows World/Town/Dungeon/Journey subtabs', (t) async {
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
          home: Scaffold(
              body: MapsTab(oracle: _oracle(), systems: const {'verdant'}))),
    ));
    await t.pumpAndSettle();
    expect(find.text('World'), findsWidgets);
    expect(find.text('Town'), findsWidgets);
    expect(find.text('Dungeon'), findsWidgets);
    expect(find.text('Journey'), findsWidgets);
  });
}
