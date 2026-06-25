import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/kal_arath_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester) async {
  const sheet = KalArathSheet(
    archetype: 'Warrior',
    stats: {'str': 2, 'tou': 1, 'agi': 0, 'int': -1, 'pre': 1},
    maxHp: 8,
    currentHp: 6,
    fatePoints: 1,
  );
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default': jsonEncode([
      {
        'id': 'c1',
        'name': 'Vorr',
        'stats': [],
        'tracks': [],
        'tags': [],
        'kalArath': sheet.toJson(),
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
            return KalArathSheetView(character: live, onBack: () {});
          })))));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('kal-arath-sheet renders with name + label', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester);
    expect(find.byKey(const Key('kal-arath-sheet')), findsOneWidget);
    expect(find.text('Vorr'), findsOneWidget);
    expect(find.text('Kal-Arath'), findsOneWidget);
  });

  testWidgets('rename pencil edits the character name', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = await _pump(tester);
    await tester.tap(find.byKey(const Key('kal-arath-name-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('kal-arath-name')), 'Skarn');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.name, 'Skarn');
  });

  testWidgets('HP stepper persists', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = await _pump(tester);
    await tester.tap(find.byKey(const Key('kal-arath-hp-minus')));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.kalArath!.currentHp, 5);
  });

  testWidgets('roll button shows snackbar with em-dash', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester);
    await tester.tap(find.byKey(const Key('kal-arath-roll-str')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('—'), findsOneWidget);
  });

  testWidgets('fate point stepper persists', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = await _pump(tester);
    await tester.tap(find.byKey(const Key('kal-arath-fate-minus')));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.kalArath!.fatePoints, 0);
  });

  testWidgets('sheet-back fires onBack', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var back = false;
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': jsonEncode([
        {
          'id': 'c1',
          'name': 'Vorr',
          'stats': [],
          'tracks': [],
          'tags': [],
          'kalArath': const KalArathSheet().toJson(),
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
                body: KalArathSheetView(
                    character: char, onBack: () => back = true)))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    expect(back, isTrue);
  });
}
