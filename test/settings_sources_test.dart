import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/features/settings_sheet.dart';
import 'package:loreseer/state/interpreter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Future<void> pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'loreseer.ai_enabled.v1': false});
  final fake =
      FakeInterpreterService(initial: const InterpreterStatus(InterpreterPhase.unsupported));
  await tester.pumpWidget(ProviderScope(
    overrides: [interpreterServiceProvider.overrideWithValue(fake)],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSettingsSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Settings shows a Sources & licenses entry', (tester) async {
    await pump(tester);
    expect(find.text('Sources & licenses'), findsWidgets);
  });
}
