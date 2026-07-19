import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/embark_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpSheet(WidgetTester tester) async {
  const sheet = EmbarkSheet(
    className: 'Mage',
    stats: {'str': 1, 'dex': 2, 'wil': 4, 'int': 3},
    level: 2,
    maxHp: 8,
    currentHp: 5,
    injuries: 1,
    av: 2,
    resource: 2,
    resourceMax: 3,
  );
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default': jsonEncode([
      {
        'id': 'c1',
        'name': 'Ash',
        'stats': [],
        'tracks': [],
        'tags': [],
        'embark': sheet.toJson(),
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
            return EmbarkSheetView(character: live, onBack: () {});
          })))));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  void _bigView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('embark-sheet renders with name and system label',
      (tester) async {
    _bigView(tester);
    await _pumpSheet(tester);
    expect(find.byKey(const Key('embark-sheet')), findsOneWidget);
    expect(find.text('Ash'), findsOneWidget);
    expect(find.text('Embark 2E'), findsWidgets);
    // Resource box is labeled by class (Mage → Spell Dice).
    expect(find.text('Spell Dice'), findsOneWidget);
  });

  testWidgets('HP stepper persists', (tester) async {
    _bigView(tester);
    final c = await _pumpSheet(tester);
    await tester.tap(find.byKey(const Key('embark-hp-minus')));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.embark!.currentHp, 4);
  });

  testWidgets('Injuries stepper persists', (tester) async {
    _bigView(tester);
    final c = await _pumpSheet(tester);
    await tester.tap(find.byKey(const Key('embark-injuries-plus')));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.embark!.injuries, 2);
  });

  testWidgets('class dropdown change persists and relabels resource',
      (tester) async {
    _bigView(tester);
    final c = await _pumpSheet(tester);
    await tester.tap(find.byKey(const Key('embark-class')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warrior').last);
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.embark!.className, 'Warrior');
    expect(find.text('Grit'), findsOneWidget);
  });

  testWidgets('check button shows snackbar with em-dash', (tester) async {
    _bigView(tester);
    await _pumpSheet(tester);
    await tester.tap(find.byKey(const Key('embark-check-str')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('—'), findsOneWidget);
  });
}
