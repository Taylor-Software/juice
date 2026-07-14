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

/// The assistant rail sits above the journal entry list, inside the body that
/// swaps layout branches at the 360px scroll-fallback height — the same swap
/// the software keyboard triggers on a phone. The rail's State holds the
/// Ask-the-Oracle text and the LLM rank cache, so rebuilding it across the
/// swap silently dropped a half-typed question and re-ranked unchanged play
/// state. Both are guarded here; the rail is pumped through [JournalScreen]
/// (not standalone) because the swap is what these regressions ride on.
void main() {
  const ask = Key('ask-gm-field');
  const keyboardInset = FakeViewPadding(bottom: 336);

  Future<FakeInterpreterService> pump(WidgetTester t) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
      // One open thread → an 'advance-thread' chip for the rail to rank.
      'juice.threads.v1.default':
          '[{"id":"t1","title":"The missing heir","open":true}]',
      'juice.ai_enabled.v1': true,
      'juice.assistant_rail_expanded.v1': true,
    });
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    t.view.devicePixelRatio = 1.0;
    // 640 - 336 = 304, under the 360px threshold: the keyboard forces the swap.
    t.view.physicalSize = const Size(390, 640);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetViewInsets);
    await t.pumpWidget(ProviderScope(
      overrides: [
        // Avoid rootBundle (which hangs the headless runner) for the oracle.
        oracleProvider.overrideWith((ref) async => _oracle()),
        interpreterServiceProvider.overrideWithValue(fake),
      ],
      child: const MaterialApp(home: Scaffold(body: JournalScreen())),
    ));
    await t.pumpAndSettle();
    return fake;
  }

  testWidgets('the Ask box keeps its question when the keyboard opens',
      (t) async {
    await pump(t);
    await t.tap(find.byKey(ask));
    await t.pumpAndSettle();
    t.testTextInput.enterText('does the heir still live?');
    await t.pumpAndSettle();

    t.view.viewInsets = keyboardInset;
    await t.pumpAndSettle();

    // The rail must reparent across the swap: rebuilding disposes its
    // TextEditingController and the typed question is gone for good.
    expect(t.widget<TextField>(find.byKey(ask)).controller!.text,
        'does the heir still live?',
        reason: 'the layout swap ate the half-typed question');
    expect(t.testTextInput.isVisible, isTrue);
    expect(t.testTextInput.hasAnyClients, isTrue);
  });

  testWidgets('a keyboard cycle does not re-rank unchanged play state',
      (t) async {
    final fake = await pump(t);
    expect(fake.rankCalls, 1, reason: 'the rail ranks once on first expand');

    // Open and close the keyboard. No entry was added and no scene changed, so
    // the rank signature is identical — the cache should absorb both frames.
    t.view.viewInsets = keyboardInset;
    await t.pumpAndSettle();
    t.view.viewInsets = const FakeViewPadding(bottom: 0);
    await t.pumpAndSettle();

    expect(fake.rankCalls, 1,
        reason: 'the swap discarded _rankCache and re-ranked identical state — '
            'each redundant call is a real on-device LLM run');
  });
}
