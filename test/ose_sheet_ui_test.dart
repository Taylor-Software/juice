import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/ose_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpSheet(WidgetTester tester) async {
  const sheet = OseSheet(
    className: 'Fighter',
    level: 3,
    stats: {'str': 15, 'int': 9, 'wis': 8, 'dex': 12, 'con': 14, 'cha': 10},
    saves: {
      'death': 12,
      'wands': 13,
      'paralysis': 14,
      'breath': 15,
      'spells': 16
    },
    maxHp: 18,
    currentHp: 15,
    ac: 5,
    thac0: 17,
  );
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default': jsonEncode([
      {
        'id': 'c1',
        'name': 'Thorin',
        'stats': [],
        'tracks': [],
        'tags': [],
        'ose': sheet.toJson(),
      }
    ]),
  });
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final char = (await container.read(charactersProvider.future)).single;
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: Consumer(builder: (_, ref, __) {
            final live =
                ref.watch(charactersProvider).valueOrNull?.firstOrNull ?? char;
            return OseSheetView(character: live, onBack: () {});
          })))));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('ose-sheet key renders with name and system label',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSheet(tester);
    expect(find.byKey(const Key('ose-sheet')), findsOneWidget);
    expect(find.text('Thorin'), findsOneWidget);
    expect(find.text('OSE / B/X'), findsOneWidget);
  });

  testWidgets('HP stepper persists', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = await _pumpSheet(tester);
    await tester.tap(find.byKey(const Key('ose-hp-minus')));
    await tester.pumpAndSettle();

    final chars = await c.read(charactersProvider.future);
    expect(chars.single.ose!.currentHp, 14);
  });

  testWidgets('save roll button shows snackbar with em-dash', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSheet(tester);
    await tester.tap(find.byKey(const Key('ose-save-roll-death')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('—'), findsOneWidget);
  });

  testWidgets('save target stepper persists', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = await _pumpSheet(tester);
    await tester.tap(find.byKey(const Key('ose-save-death-minus')));
    await tester.pumpAndSettle();

    final chars = await c.read(charactersProvider.future);
    expect(chars.single.ose!.saves['death'], 11);
  });

  testWidgets('sheet-back fires onBack', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var backCalled = false;
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': jsonEncode([
        {
          'id': 'c1',
          'name': 'Thorin',
          'stats': [],
          'tracks': [],
          'tags': [],
          'ose': const OseSheet().toJson(),
        }
      ]),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final char = (await container.read(charactersProvider.future)).single;
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
                body: OseSheetView(
                    character: char, onBack: () => backCalled = true)))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    expect(backCalled, isTrue);
  });
}
