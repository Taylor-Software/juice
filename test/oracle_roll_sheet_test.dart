import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/oracle_roll_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

OracleData _loadData() =>
    OracleData(jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>);

const _sid = 'default';

Future<ProviderContainer> _open(
    WidgetTester tester, OracleData data, String defaultOracle) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"$_sid","sessions":[{"id":"$_sid","name":"C1"}]}',
    'juice.journal.v2.$_sid': '[]',
  });
  final oracle = Oracle(data, Dice(Random(3)));
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await c.read(sessionsProvider.future);
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => showOracleRollSheet(context, oracle, defaultOracle),
          child: const Text('open'),
        );
      })),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  late OracleData data;
  setUpAll(() => data = _loadData());

  testWidgets('icons: pick a count, roll logs N icons with the animation',
      (tester) async {
    final c = await _open(tester, data, 'icons');
    await tester.tap(find.byKey(const Key('oracle-roll-icon-count-3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('oracle-roll-icons')));
    await tester.pumpAndSettle(); // past the tumble

    final entries = await c.read(journalProvider.future);
    final e = entries.singleWhere((x) => x.sourceTool == 'gen-abstract-icon');
    expect((e.payload?['icons'] as List), hasLength(3));
    expect(e.title, 'Story Dice (3)');
  });

  testWidgets('cards: single standard draw logs a cards entry', (tester) async {
    final c = await _open(tester, data, 'cards');
    // Spread controls are tarot-only — not shown for the standard deck.
    expect(find.byKey(const Key('oracle-roll-mode')), findsNothing);
    await tester.tap(find.byKey(const Key('oracle-roll-cards')));
    await tester.pumpAndSettle();
    final entries = await c.read(journalProvider.future);
    expect(entries.where((x) => x.sourceTool == 'cards'), hasLength(1));
  });

  testWidgets('tarot: a spread draw logs one spread entry', (tester) async {
    final c = await _open(tester, data, 'tarot');
    // Default deck is Tarot → the Single/Spread toggle shows; pick Spread.
    await tester.tap(find.byKey(const Key('oracle-roll-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spread'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('oracle-roll-cards')));
    await tester.pumpAndSettle();
    final entries = await c.read(journalProvider.future);
    final spreads = entries
        .where((x) => x.sourceTool == 'cards' && x.title == 'Tarot Spread');
    expect(spreads, hasLength(1));
  });
}
