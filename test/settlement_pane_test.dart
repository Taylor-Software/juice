import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/settlement_pane.dart';
import 'package:juice_oracle/state/providers.dart';

Oracle _oracle() => Oracle(
    OracleData(jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>),
    Dice(Random(3)));

void main() {
  Future<ProviderContainer> pump(WidgetTester t) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child:
          MaterialApp(home: Scaffold(body: SettlementPane(oracle: _oracle()))),
    ));
    await t.pumpAndSettle();
    return c;
  }

  testWidgets('empty state, then Generate town creates a town with buildings',
      (t) async {
    final c = await pump(t);
    expect(find.text('No settlements yet. Generate a town.'), findsOneWidget);
    await t.tap(find.byKey(const Key('settlement-generate')));
    await t.pumpAndSettle();
    final s = await c.read(mapProvider.future);
    expect(s.settlements, hasLength(1));
    expect(s.settlements.single.buildings, isNotEmpty);
    // Building cards render.
    expect(
        find.byKey(Key('building-${s.settlements.single.buildings.first.id}')),
        findsOneWidget);
    expect(find.text('Buildings'), findsOneWidget);
  });

  testWidgets('delete a building removes its card', (t) async {
    final c = await pump(t);
    final n = c.read(mapProvider.notifier);
    final sid = await n.addSettlement(name: 'Hollow');
    final bid = await n.addBuilding(sid, name: 'Smithy');
    await t.pumpAndSettle();
    expect(find.byKey(Key('building-$bid')), findsOneWidget);
    await t.tap(find.byKey(Key('building-del-$bid')));
    await t.pumpAndSettle();
    expect(find.byKey(Key('building-$bid')), findsNothing);
  });

  testWidgets('rename settlement via the editor', (t) async {
    final c = await pump(t);
    await c.read(mapProvider.notifier).addSettlement(name: 'Old Name');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('settlement-rename')));
    await t.pumpAndSettle();
    await t.enterText(
        find.byKey(const Key('settlement-name-field')), 'New Name');
    await t.enterText(find.byKey(const Key('settlement-kind-field')), 'City');
    await t.tap(find.byKey(const Key('settlement-save')));
    await t.pumpAndSettle();
    final s = await c.read(mapProvider.future);
    expect(s.settlements.single.name, 'New Name');
    expect(s.settlements.single.kind, 'City');
  });
}
