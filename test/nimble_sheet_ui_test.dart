import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/nimble_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Use a tall view so the full ListView renders (steppers may be far down).
  setUp(() {});

  Future<ProviderContainer> pumpSheet(WidgetTester tester,
      {Character? character}) async {
    final nimbleJson = const NimbleSheet(
      className: 'The Cheat',
      maxHp: 10,
      currentHp: 10,
    ).toJson();
    final charJson = character != null
        ? jsonEncode([character.toJson()])
        : jsonEncode([
            {
              'id': 'c1',
              'name': 'Ari',
              'stats': [],
              'tracks': [],
              'tags': [],
              'nimble': nimbleJson,
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
            // Mirror the roster: re-pass the LIVE character on each change so
            // the view re-reads state (it takes character as a prop, like the
            // other sheets — the parent feeds updates).
            home: Scaffold(body: Consumer(builder: (_, ref, __) {
              final live =
                  ref.watch(charactersProvider).valueOrNull?.firstOrNull ??
                      char;
              return NimbleSheetView(character: live, onBack: () {});
            })))));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('nimble-sheet key renders', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpSheet(tester);

    expect(find.byKey(const Key('nimble-sheet')), findsOneWidget);
    expect(find.text('Ari'), findsOneWidget);
    expect(find.text('Nimble'), findsOneWidget);
  });

  testWidgets('tapping nimble-stat-str-plus persists stats[str] == 1',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('nimble-stat-str-plus')));
    await tester.pumpAndSettle();

    final chars = await container.read(charactersProvider.future);
    expect(chars.single.nimble!.stats['str'], 1);
  });

  testWidgets('tapping nimble-wounds-plus persists wounds == 1',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // wounds starts at 0, maxWounds at 6, so +1 is within range.
    final container = await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('nimble-wounds-plus')));
    await tester.pumpAndSettle();

    final chars = await container.read(charactersProvider.future);
    expect(chars.single.nimble!.wounds, 1);
  });

  testWidgets('sheet-back button fires onBack', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
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
          'name': 'Ari',
          'stats': [],
          'tracks': [],
          'tags': [],
          'nimble': const NimbleSheet().toJson(),
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
                body: NimbleSheetView(
                    character: char, onBack: () => backCalled = true)))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();

    expect(backCalled, isTrue);
  });

  testWidgets('save toggle cycles none -> adv -> dis -> none', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = await pumpSheet(tester);
    NimbleSheet s() => c.read(charactersProvider).value!.single.nimble!;
    final btn = find.byKey(const Key('nimble-save-str'));
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(s().saveAdv['str'], 1); // advantaged
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(s().saveAdv['str'], -1); // disadvantaged
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(s().saveAdv['str'], isNull); // back to none (zero omitted)
  });
}
