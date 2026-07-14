import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

/// The journal body swaps layout branches at its 360px scroll-fallback height:
/// a tall viewport gets `Column[rail, Expanded(entries), chrome]`, a short one
/// gets `SingleChildScrollView(Column[...])`. On a phone the software keyboard
/// shrinks the journal straight across that threshold, so the swap fires the
/// instant the user starts typing.
///
/// The swap must not rebuild the composer's element. When it did, the old
/// EditableText closed its text-input connection (hiding the keyboard) while
/// the State-owned `_composerFocus` kept focus — so no focus-change event ever
/// fired to reopen it. The field kept its cursor, the keyboard stayed down and
/// keystrokes went nowhere: the journal was unwritable on a phone.
///
/// These guard the symptom, not the mechanism — `hasFocus` stayed true through
/// the whole bug, so asserting on focus alone would pass against the break.
void main() {
  const composer = Key('journal-composer');
  // Roughly an iPhone keyboard; 640 - 336 = 304 is under the 360 threshold.
  const keyboardInset = FakeViewPadding(bottom: 336);

  Future<void> pump(WidgetTester t) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(390, 640);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetViewInsets);
    await t.pumpWidget(ProviderScope(
      overrides: [
        // Avoid rootBundle (which hangs the headless runner) for the oracle.
        oracleProvider.overrideWith((ref) async => _oracle()),
        interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
      ],
      child: const MaterialApp(home: Scaffold(body: JournalScreen())),
    ));
    await t.pumpAndSettle();
  }

  String composerText(WidgetTester t) =>
      t.widget<TextField>(find.byKey(composer)).controller!.text;

  testWidgets('the keyboard survives the layout swap it triggers', (t) async {
    await pump(t);
    await t.tap(find.byKey(composer));
    await t.pumpAndSettle();
    expect(t.testTextInput.isVisible, isTrue,
        reason: 'tapping the composer should raise the keyboard');

    // The keyboard slides up and the journal shrinks past the threshold.
    t.view.viewInsets = keyboardInset;
    await t.pumpAndSettle();

    expect(t.testTextInput.isVisible, isTrue,
        reason: 'the layout swap must not close the keyboard');
    expect(t.testTextInput.hasAnyClients, isTrue,
        reason: 'the composer must keep its text-input connection');

    // The user can actually write — the thing the bug took away.
    t.testTextInput.enterText('a fine mess');
    await t.pumpAndSettle();
    expect(composerText(t), 'a fine mess');
  });

  testWidgets('the composer element is reused across the swap', (t) async {
    await pump(t);
    await t.tap(find.byKey(composer));
    await t.pumpAndSettle();
    final before = find.byKey(composer).evaluate().single;

    t.view.viewInsets = keyboardInset;
    await t.pumpAndSettle();

    // Identity is the mechanism the keyboard fix rests on: a rebuilt element
    // disposes the EditableText and drops the input connection.
    expect(identical(before, find.byKey(composer).evaluate().single), isTrue,
        reason: 'the composer must reparent across the swap, not rebuild');
  });

  testWidgets('typing still works after the keyboard closes again', (t) async {
    await pump(t);
    await t.tap(find.byKey(composer));
    await t.pumpAndSettle();

    // Open, then dismiss: the journal crosses the threshold in both directions.
    t.view.viewInsets = keyboardInset;
    await t.pumpAndSettle();
    t.view.viewInsets = const FakeViewPadding(bottom: 0);
    await t.pumpAndSettle();

    expect(t.testTextInput.isVisible, isTrue);
    t.testTextInput.enterText('still here');
    await t.pumpAndSettle();
    expect(composerText(t), 'still here');
  });
}
