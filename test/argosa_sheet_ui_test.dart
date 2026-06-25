import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/argosa_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpSheet(WidgetTester tester,
    {Map<String, dynamic>? charOverride}) async {
  const sheet = ArgosaSheet(
    className: 'Fighter',
    level: 3,
    stats: {
      'str': 12,
      'dex': 14,
      'con': 10,
      'int': 8,
      'per': 11,
      'wil': 9,
      'cha': 13
    },
    maxHp: 14,
    currentHp: 7,
    luck: 10,
  );
  final charJson = charOverride != null
      ? jsonEncode([charOverride])
      : jsonEncode([
          {
            'id': 'c1',
            'name': 'Korrin',
            'stats': [],
            'tracks': [],
            'tags': [],
            'argosa': sheet.toJson(),
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
            return ArgosaSheetView(character: live, onBack: () {});
          })))));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('argosa-sheet key renders with name and system label',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSheet(tester);
    expect(find.byKey(const Key('argosa-sheet')), findsOneWidget);
    expect(find.text('Korrin'), findsOneWidget);
    expect(find.text('Tales of Argosa'), findsOneWidget);
  });

  testWidgets('HP stepper persists', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = await _pumpSheet(tester);

    await tester.tap(find.byKey(const Key('argosa-hp-minus')));
    await tester.pumpAndSettle();

    final chars = await c.read(charactersProvider.future);
    expect(chars.single.argosa!.currentHp, 6);
  });

  testWidgets('Stagger badge appears when HP <= half maxHp', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // currentHp=7, maxHp=14 → 7*2 == 14 → staggered
    await _pumpSheet(tester);
    expect(find.text('Staggered'), findsOneWidget);
  });

  testWidgets('roll button shows snackbar with em-dash', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSheet(tester);

    await tester.tap(find.byKey(const Key('argosa-roll-str')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Snackbar shows "Strength: N — [Success/Failure/Great Success]"
    expect(find.textContaining('—'), findsOneWidget);
  });

  testWidgets('Luck reset button sets luck to resetLuck', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = await _pumpSheet(tester);
    // luck=10, level=3 → resetLuck = 10 + ceil(3/2) = 12
    await tester.tap(find.byKey(const Key('argosa-luck-reset')));
    await tester.pumpAndSettle();

    final chars = await c.read(charactersProvider.future);
    expect(chars.single.argosa!.luck, 12);
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
          'name': 'Korrin',
          'stats': [],
          'tracks': [],
          'tags': [],
          'argosa': const ArgosaSheet().toJson(),
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
                body: ArgosaSheetView(
                    character: char, onBack: () => backCalled = true)))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    expect(backCalled, isTrue);
  });
}
