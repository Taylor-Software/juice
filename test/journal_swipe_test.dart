import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';

import 'fake_interpreter.dart';

Future<ProviderContainer> _pump(WidgetTester t, {required double width}) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.ai_nudge_seen.v1': true,
    'juice.chip_help_seen.v1': true,
    'juice.journal.v2.default':
        '[{"id":"e1","timestamp":"2026-07-11T10:00:00.000","title":"",'
            '"body":"The burned mill looms.","kind":"text"}]',
  });
  final c = ProviderContainer(overrides: [
    interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
  ]);
  addTearDown(c.dispose);
  t.view.physicalSize = Size(width, 812);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: JournalScreen()),
    ),
  ));
  await t.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('phone: swipe left deletes with Undo; Undo restores', (t) async {
    final c = await _pump(t, width: 375);
    expect(find.byKey(const ValueKey('swipe-e1')), findsOneWidget);

    await t.drag(find.text('The burned mill looms.'), const Offset(-400, 0));
    await t.pumpAndSettle();
    expect(c.read(journalProvider).value, isEmpty);
    expect(find.text('Entry deleted'), findsOneWidget);

    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(
        c.read(journalProvider).value!.single.body, 'The burned mill looms.');
  });

  testWidgets('phone: swipe right opens the edit dialog, nothing deleted',
      (t) async {
    final c = await _pump(t, width: 375);
    await t.drag(find.text('The burned mill looms.'), const Offset(400, 0));
    await t.pumpAndSettle();
    expect(find.text('Edit journal entry'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.read(journalProvider).value, hasLength(1));
  });

  testWidgets('desktop width: entries are not swipe-dismissible', (t) async {
    await _pump(t, width: 900);
    expect(find.byKey(const ValueKey('swipe-e1')), findsNothing);
  });
}
