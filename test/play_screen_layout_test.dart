import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/features/loop_bar.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

/// Regression guard for the Play-screen split. PlayScreen previously wrapped the
/// Solo-Loop bar in `Flexible(fit: loose)` — which defaults to flex: 1, the same
/// as the journal's `Expanded` — so the column split its height ~50/50 and the
/// journal feed was squeezed to a sliver that couldn't scroll. The loop bar must
/// be a compact NON-flex child so the journal keeps priority, and it must be
/// collapsible.
void main() {
  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(1000, 720);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(ProviderScope(
      overrides: [
        // Avoid rootBundle (which hangs the headless runner) for the oracle.
        oracleProvider.overrideWith((ref) async => _oracle()),
        interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
      ],
      child: const MaterialApp(home: Scaffold(body: PlayScreen())),
    ));
    await t.pumpAndSettle();
  }

  testWidgets(
      'loop bar is collapsed by default so the journal fills the height',
      (t) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    await pump(t);
    // Default is collapsed: no loop bar chrome, the journal owns the height and
    // the composer is reachable at the bottom.
    expect(find.byType(LoopBar), findsNothing);
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
  });

  testWidgets('expanding shows a compact loop bar the journal still dwarfs',
      (t) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    await pump(t);
    final collapsedJournalH = t.getSize(find.byType(JournalScreen)).height;

    // Expand the loop bar via its sticky toggle.
    await t.tap(find.byKey(const Key('loop-collapse-toggle')));
    await t.pumpAndSettle();

    final loopH = t.getSize(find.byType(LoopBar)).height;
    final journalH = t.getSize(find.byType(JournalScreen)).height;
    // Even expanded, the loop bar stays compact and the journal dominates (the
    // old Flexible(flex:1) bug split the height ~50/50).
    expect(journalH, greaterThan(loopH * 2),
        reason: 'journal ($journalH) should dwarf loop bar ($loopH)');
    expect(loopH, lessThan(260), reason: 'loop bar should be compact');
    // Expanding took height away from the journal.
    expect(journalH, lessThan(collapsedJournalH));
  });

  testWidgets('expanded loop bar has a visible scrollbar and reachable steps',
      (t) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    await pump(t);
    await t.tap(find.byKey(const Key('loop-collapse-toggle')));
    await t.pumpAndSettle();

    // The capped region carries the "there is more below" affordance
    // (audit F2 / stranger-test S3: clipped Steps read as nonexistent).
    expect(
        find.ancestor(
            of: find.byType(LoopBar), matching: find.byType(Scrollbar)),
        findsOneWidget);

    // Expanding Steps overflows the cap; the last step must be reachable by
    // scrolling the capped region.
    await t.tap(find.byKey(const Key('loop-steps')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const Key('loop-capture-field')), 200,
        scrollable: find
            .descendant(
                of: find.ancestor(
                    of: find.byType(LoopBar), matching: find.byType(Scrollbar)),
                matching: find.byType(Scrollable))
            .first);
    expect(find.byKey(const Key('loop-capture-field')), findsOneWidget);
  });
}
