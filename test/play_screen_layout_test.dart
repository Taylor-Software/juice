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

  testWidgets('loop bar is compact and the journal dominates the height',
      (t) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    await pump(t);

    final loopH = t.getSize(find.byType(LoopBar)).height;
    final journalH = t.getSize(find.byType(JournalScreen)).height;
    // The journal must dwarf the loop bar (the old 50/50 split made these
    // roughly equal). The composer must be present at the bottom.
    expect(journalH, greaterThan(loopH * 2),
        reason: 'journal ($journalH) should dwarf loop bar ($loopH)');
    expect(loopH, lessThan(260), reason: 'loop bar should be compact');
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
  });

  testWidgets('collapsing the loop bar hands its space to the journal',
      (t) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    await pump(t);
    final before = t.getSize(find.byType(JournalScreen)).height;

    await t.tap(find.byKey(const Key('loop-collapse-toggle')));
    await t.pumpAndSettle();

    expect(find.byType(LoopBar), findsNothing);
    expect(t.getSize(find.byType(JournalScreen)).height, greaterThan(before));
  });
}
