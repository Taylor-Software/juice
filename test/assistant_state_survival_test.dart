import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/loop_bar.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

/// The assistant lives inside the Play screen's collapsible "Next" panel, and
/// on a phone that panel auto-collapses whenever the journal composer takes
/// focus — i.e. on every keyboard cycle. Collapsing UNMOUNTS the assistant, so
/// anything held in its State would be destroyed routinely: the Ask box would
/// drop a half-typed question, and the LLM rank cache would re-rank unchanged
/// play state (each redundant call is a real on-device LLM run).
///
/// Both are guarded here. The assistant is pumped through [PlayScreen] (not
/// standalone) because the collapse cycle is what these regressions ride on.
///
/// Previously this guarded the same two properties against `JournalScreen`'s
/// 360px layout swap, which used to rebuild the rail where it was then mounted.
void main() {
  const ask = Key('ask-gm-field');

  Future<(FakeInterpreterService, ProviderContainer)> pump(
      WidgetTester t) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
      // One open thread → an 'advance-thread' chip to rank.
      'juice.threads.v1.default':
          '[{"id":"t1","title":"The missing heir","open":true}]',
      'juice.ai_enabled.v1': true,
      'juice.play_panel_expanded.v1': true,
    });
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(390, 840); // a phone: compact width
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = ProviderContainer(overrides: [
      // Avoid rootBundle (which hangs the headless runner) for the oracle.
      oracleProvider.overrideWith((ref) async => _oracle()),
      interpreterServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: PlayScreen())),
    ));
    await t.pumpAndSettle();
    return (fake, c);
  }

  /// Drive the real auto-collapse trigger: composer focus on a compact
  /// viewport (the app sets this when the composer's FocusNode fires).
  Future<void> setComposerFocus(
      WidgetTester t, ProviderContainer c, bool focused) async {
    c.read(journalComposerFocusProvider.notifier).state = focused;
    await t.pumpAndSettle();
  }

  testWidgets('the Ask box keeps its question across a composer-focus collapse',
      (t) async {
    final (_, c) = await pump(t);
    await t.enterText(find.byKey(ask), 'does the heir still live?');
    await t.pumpAndSettle();

    // Focusing the composer collapses the panel and unmounts the assistant.
    await setComposerFocus(t, c, true);
    expect(find.byKey(ask), findsNothing);
    await setComposerFocus(t, c, false);

    expect(t.widget<TextField>(find.byKey(ask)).controller!.text,
        'does the heir still live?',
        reason: 'the collapse cycle ate the half-typed question');
  });

  testWidgets('a composer-focus cycle does not re-rank unchanged play state',
      (t) async {
    final (fake, c) = await pump(t);
    expect(fake.rankCalls, 1, reason: 'ranks once when the panel first opens');

    // Collapse and reopen. No entry was added and no scene changed, so the
    // rank signature is identical — the cache should absorb the remount.
    await setComposerFocus(t, c, true);
    await setComposerFocus(t, c, false);

    expect(fake.rankCalls, 1,
        reason: 'the remount discarded the rank cache and re-ranked identical '
            'state — each redundant call is a real on-device LLM run');
  });
}
