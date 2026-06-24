import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/draw_steel_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpSheet(WidgetTester tester,
    {Character? character}) async {
  final sheet = DrawSteelSheet(
    className: kDrawSteelClasses.first,
    maxStamina: 30,
    currentStamina: 20,
    maxRecoveries: 8,
    recoveries: 8,
  );
  final charJson = character != null
      ? jsonEncode([character.toJson()])
      : jsonEncode([
          {
            'id': 'c1',
            'name': 'Kael',
            'stats': [],
            'tracks': [],
            'tags': [],
            'drawSteel': sheet.toJson(),
          }
        ]);
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default': charJson,
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
            return DrawSteelSheetView(character: live, onBack: () {});
          })))));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('draw-steel-sheet key renders', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSheet(tester);
    expect(find.byKey(const Key('draw-steel-sheet')), findsOneWidget);
    expect(find.text('Kael'), findsOneWidget);
    expect(find.text('Draw Steel'), findsOneWidget);
  });

  testWidgets('stamina stepper persists', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = await _pumpSheet(tester);

    await tester.tap(find.byKey(const Key('draw-steel-stamina-minus')));
    await tester.pumpAndSettle();

    final chars = await c.read(charactersProvider.future);
    expect(chars.single.drawSteel!.currentStamina, 19);
  });

  testWidgets('roll button shows snackbar with tier', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSheet(tester);

    // Tap the roll button for 'might' (first characteristic).
    await tester.tap(find.byKey(const Key('draw-steel-roll-might')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // A snackbar should appear containing "Tier".
    expect(find.textContaining('Tier'), findsOneWidget);
  });

  testWidgets('class dropdown changes class', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = await _pumpSheet(tester);

    // Pick the second class in the list.
    final second = kDrawSteelClasses[1];
    await tester.tap(find.byKey(const Key('draw-steel-class')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(second).last);
    await tester.pumpAndSettle();

    final chars = await c.read(charactersProvider.future);
    expect(chars.single.drawSteel!.className, second);
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
          'name': 'Kael',
          'stats': [],
          'tracks': [],
          'tags': [],
          'drawSteel': const DrawSteelSheet().toJson(),
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
                body: DrawSteelSheetView(
                    character: char, onBack: () => backCalled = true)))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    expect(backCalled, isTrue);
  });
}
