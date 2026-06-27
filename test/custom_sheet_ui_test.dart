import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/custom_sheet.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/custom_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester,
    {CustomSheet sheet = const CustomSheet()}) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default': jsonEncode([
      {
        'id': 'c1',
        'name': 'Homebrew',
        'stats': [],
        'tracks': [],
        'tags': [],
        'custom': sheet.toJson(),
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
            return CustomSheetView(character: live, onBack: () {});
          })))));
  await tester.pumpAndSettle();
  return container;
}

void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('addCustom seeds a character with the given blocks', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': '[]',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(charactersProvider.future);

    const blocks = [
      CustomBlock(id: 'b1', type: CustomBlockType.counter, label: 'AC'),
    ];
    final id =
        await container.read(charactersProvider.notifier).addCustom(blocks);

    final chars = await container.read(charactersProvider.future);
    final c = chars.firstWhere((e) => e.id == id);
    expect(c.custom, isNotNull);
    expect(c.custom!.blocks.single.label, 'AC');
  });

  testWidgets('empty sheet starts in edit mode with add-block', (tester) async {
    _bigView(tester);
    await _pump(tester);
    expect(find.byKey(const Key('custom-add-block')), findsOneWidget);
  });

  testWidgets('delete removes a block and persists', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 'b1', type: CustomBlockType.freeform, label: 'Notes'),
    ]);
    final c = await _pump(tester, sheet: sheet);
    // ensure edit mode
    if (find.byKey(const Key('custom-block-b1-delete')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('custom-mode-toggle')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('custom-block-b1-delete')));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.custom!.blocks, isEmpty);
  });
}
