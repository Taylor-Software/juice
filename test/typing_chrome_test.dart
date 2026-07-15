// Phone typing budget: what the shell yields to the writer while the keyboard
// is up, driven through the REAL HomeShell (the bottom nav lives there, the
// dock lives in the journal — only the whole shell shows the real split).
//
// Measured before this collapse existed, on a 390x844 phone with the keyboard
// up: 508px usable, of which AppBar 56 + HUD 60 + panel toggle 34 + suggestion
// chips 48 + dock 56 + composer 120 + bottom nav 80 = 454, leaving the journal
// 34px — 6.7%. You could not see the story you were writing about. The nav, the
// dock and the "Track …?" chips are 184px of tools nobody reaches for
// mid-sentence, so they now yield while the composer has focus and return on
// blur.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/engine/verdant_data.dart';
import 'package:juice_oracle/features/inline_roll_dock.dart';
import 'package:juice_oracle/shared/home_shell.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

// Load from file, not rootBundle, which hangs the headless runner.
final _verdantOverride = verdantDataProvider.overrideWith((ref) async =>
    VerdantData(jsonDecode(File('assets/verdant_data.json').readAsStringSync())
        as Map<String, dynamic>));

final _emulatorOverride = emulatorDataProvider.overrideWith((ref) async =>
    EmulatorData(
        jsonDecode(File('assets/emulator_data.json').readAsStringSync())
            as Map<String, dynamic>));

String _entry(String id, String body) => '{'
    '"id":"$id","timestamp":"2026-06-12T10:00:00.000Z",'
    '"title":"Scene","body":"$body","kind":"note","tags":[]}';

const _composer = Key('journal-composer');

/// The entry list is the only reverse:true ListView (the filter strip is a
/// short horizontal one) — match it exactly rather than by type.
final _entryList = find.byWidgetPredicate(
    (w) => w is ListView && w.reverse == true && w.controller != null);

void main() {
  // NOTE: SharedPreferences caches its singleton, so re-seeding
  // setMockInitialValues inside ONE test silently keeps the first seed — every
  // case below needs its own testWidgets.
  Future<void> pumpShell(WidgetTester t, {required Size size}) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = size;
    t.view.viewInsets = const FakeViewPadding(bottom: 0);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetViewInsets);
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      // Not a first-run user: the one-time cards are dismissed, so this
      // measures the steady state rather than the nudge.
      'juice.ai_offer_seen.v1': true,
      'juice.welcome_seen.v1': true,
      'juice.ai_nudge_seen.v1': true,
      'juice.chip_help_seen.v1': true,
      'juice.journal.v2.default': '['
          '${_entry('e1', 'Gorath met Mira near the Vault.')},'
          '${_entry('e2', 'The Vault held secrets.')},'
          '${_entry('e3', 'Mira drew her blade.')}'
          ']',
    });
    await t.pumpWidget(ProviderScope(
      overrides: [
        oracleProvider.overrideWith((ref) async => _oracle()),
        interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
        _verdantOverride,
        _emulatorOverride,
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: HomeShell(oracle: _oracle()),
      ),
    ));
    await t.pumpAndSettle();
  }

  /// Focus the composer and raise the keyboard, as the OS does.
  Future<void> startTyping(WidgetTester t) async {
    await t.tap(find.byKey(_composer));
    await t.pumpAndSettle();
    t.view.viewInsets = const FakeViewPadding(bottom: 336);
    await t.pumpAndSettle();
  }

  testWidgets('phone: the nav, dock and chips yield to the writer',
      (tester) async {
    await pumpShell(tester, size: const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(InlineRollDock), findsOneWidget);

    await startTyping(tester);

    expect(find.byType(NavigationBar), findsNothing,
        reason: 'you are not navigating mid-sentence');
    expect(find.byType(InlineRollDock), findsNothing);
    expect(find.byType(InputChip), findsNothing,
        reason: 'the "Track …?" chips are a suggestion, not a writing tool');

    // The budget, not a raw height: 844 - 336 of keyboard leaves 508 usable,
    // and the journal must get a real share of it. This was 34px (6.7%) and is
    // now 180px (35.4%) — the floor leaves headroom but fails if a chunk of
    // chrome creeps back into the typing path. Do NOT compare against the
    // keyboard-down height; that is a bigger number for an unrelated reason
    // (no keyboard), and the comparison is meaningless.
    const usable = 844.0 - 336.0;
    expect(tester.getSize(_entryList).height, greaterThan(usable * 0.30),
        reason: 'while typing, the journal must keep ~a third of the usable '
            'screen — the writer has to see the story they are writing about');
  });

  testWidgets('phone: the chrome returns on blur', (tester) async {
    await pumpShell(tester, size: const Size(390, 844));
    await startTyping(tester);
    expect(find.byType(NavigationBar), findsNothing);

    // Keyboard down + focus lost, as when the writer taps away.
    tester.view.viewInsets = const FakeViewPadding(bottom: 0);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget,
        reason: 'the collapse is visual and momentary — nav must come back');
    expect(find.byType(InlineRollDock), findsOneWidget);
  });

  testWidgets('desktop: typing changes nothing', (tester) async {
    // The collapse buys back a phone keyboard's damage. A desktop has room and
    // no software keyboard, so its chrome must be untouched.
    await pumpShell(tester, size: const Size(1400, 900));
    final dockBefore = find.byType(InlineRollDock).evaluate().length;
    await tester.tap(find.byKey(_composer));
    await tester.pumpAndSettle();
    expect(find.byType(InlineRollDock).evaluate().length, dockBefore,
        reason: 'the dock must survive focus on a desktop');
  });

  testWidgets('phone: typing still works while the chrome is gone',
      (tester) async {
    // Dropping widgets out of the journal's Column while the composer has focus
    // is exactly the shape of #301. The composer stays LAST so the bottom-up
    // child sync keeps its element (and its text-input connection) alive.
    await pumpShell(tester, size: const Size(390, 844));
    await startTyping(tester);

    expect(tester.testTextInput.isVisible, isTrue,
        reason: 'dropping the dock must not close the keyboard');
    tester.testTextInput.enterText('a fine mess');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(_composer)).controller!.text,
        'a fine mess');
  });
}
