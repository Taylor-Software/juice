import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/oracle.dart';
import 'package:loreseer/engine/oracle_data.dart';
import 'package:loreseer/features/journal_screen.dart';
import 'package:loreseer/shared/theme.dart';
import 'package:loreseer/state/interpreter.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

void main() {
  testWidgets('composer inspire button opens the generate sheet',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'loreseer.journal.v2.default': '[]',
    });
    final oracle = Oracle(OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>));
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
      interpreterServiceProvider
          .overrideWith((ref) => FakeInterpreterService()),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: JournalScreen()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer-inspire')));
    await tester.pumpAndSettle();
    expect(find.text('Pay the Price'), findsOneWidget); // sheet is open
  });
}
