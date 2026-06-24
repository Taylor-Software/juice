import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/cairn_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpSheet(WidgetTester tester) async {
  const sheet = CairnSheet(
    background: 'Hunter',
    str: 14,
    dex: 12,
    wil: 10,
    maxHp: 6,
    currentHp: 3,
    armor: 1,
    deprived: false,
    fatigue: 0,
  );
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default': jsonEncode([
      {
        'id': 'c1',
        'name': 'Wren',
        'stats': [],
        'tracks': [],
        'tags': [],
        'cairn': sheet.toJson(),
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
            return CairnSheetView(character: live, onBack: () {});
          })))));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('cairn-sheet key renders with name and system label',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSheet(tester);
    expect(find.byKey(const Key('cairn-sheet')), findsOneWidget);
    expect(find.text('Wren'), findsOneWidget);
    expect(find.text('Cairn'), findsOneWidget);
  });

  testWidgets('HP stepper persists', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = await _pumpSheet(tester);
    await tester.tap(find.byKey(const Key('cairn-hp-minus')));
    await tester.pumpAndSettle();

    final chars = await c.read(charactersProvider.future);
    expect(chars.single.cairn!.currentHp, 2);
  });

  testWidgets('save button shows snackbar with em-dash', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSheet(tester);
    await tester.tap(find.byKey(const Key('cairn-save-str')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('—'), findsOneWidget);
  });

  testWidgets('Deprived toggle persists', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = await _pumpSheet(tester);
    await tester.tap(find.byKey(const Key('cairn-deprived')));
    await tester.pumpAndSettle();

    final chars = await c.read(charactersProvider.future);
    expect(chars.single.cairn!.deprived, isTrue);
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
          'name': 'Wren',
          'stats': [],
          'tracks': [],
          'tags': [],
          'cairn': const CairnSheet().toJson(),
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
                body: CairnSheetView(
                    character: char, onBack: () => backCalled = true)))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    expect(backCalled, isTrue);
  });
}
