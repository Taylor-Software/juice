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

  testWidgets('reorder moves a block and persists the new order',
      (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 'b1', type: CustomBlockType.freeform, label: 'First'),
      CustomBlock(id: 'b2', type: CustomBlockType.freeform, label: 'Second'),
    ]);
    final c = await _pump(tester, sheet: sheet);
    await tester.tap(find.byKey(const Key('custom-mode-toggle'))); // -> edit
    await tester.pumpAndSettle();
    // The default test platform is android, where ReorderableListView makes the
    // whole item a long-press drag target (no Icons.drag_handle). Drag the
    // first block's card down past the second to swap their order.
    final card = find.byKey(const ValueKey('b1'));
    final drag = await tester.startGesture(tester.getCenter(card));
    // Hold past the long-press threshold (500ms) so the drag is recognized.
    await tester.pump(const Duration(milliseconds: 600));
    // Move down past the second card in small increments, pumping each frame so
    // the reorder list recomputes the drop target as we cross it.
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(0, 16));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pumpAndSettle();
    final blocks =
        (await c.read(charactersProvider.future)).single.custom!.blocks;
    expect(blocks.map((b) => b.id), ['b2', 'b1']);
  });

  // ---- Task 5: counter + stat + conditions renderers -------------------------

  testWidgets('counter block steps and persists', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(
          id: 'b1',
          type: CustomBlockType.counter,
          label: 'AC',
          config: {'min': 0, 'max': 30, 'step': 1}),
    ], values: {
      'b1': 12
    });
    final c = await _pump(tester, sheet: sheet);
    // play mode (non-empty sheet starts in play)
    await tester.tap(find.byKey(const Key('custom-b1-counter-plus')));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.custom!.values['b1'], 13);
  });

  testWidgets('stat block shows derived modifier and steps', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 'b1', type: CustomBlockType.stat, label: 'Abilities', config: {
        'stats': [
          {'key': 'str', 'label': 'STR'}
        ],
        'min': 3,
        'max': 18,
        'modFormula': 'fived',
      }),
    ], values: {
      'b1': {'str': 14}
    });
    final c = await _pump(tester, sheet: sheet);
    expect(find.text('+2'), findsOneWidget); // fived(14) = +2
    await tester.tap(find.byKey(const Key('custom-b1-stat-str-plus')));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect((chars.single.custom!.values['b1'] as Map)['str'], 15);
  });

  // ---- Task 5 Part B: config-dialog exemplars --------------------------------

  testWidgets('counter config edits max and persists', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 'b1', type: CustomBlockType.counter, label: 'AC',
          config: {'min': 0, 'max': 30, 'step': 1}),
    ], values: {'b1': 12});
    final c = await _pump(tester, sheet: sheet);
    await tester.tap(find.byKey(const Key('custom-mode-toggle'))); // -> edit
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('custom-block-b1-config')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('custom-cfg-max')), '25');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final blk =
        (await c.read(charactersProvider.future)).single.custom!.blocks.single;
    expect((blk.config['max'] as num).toInt(), 25);
  });

  testWidgets('stat config adds a stat row and persists', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 'b1', type: CustomBlockType.stat, label: 'Abilities', config: {
        'stats': [{'key': 'str', 'label': 'STR'}],
        'min': 3, 'max': 18, 'modFormula': 'raw',
      }),
    ]);
    final c = await _pump(tester, sheet: sheet);
    await tester.tap(find.byKey(const Key('custom-mode-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('custom-block-b1-config')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('custom-cfg-stat-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final blk = (await c.read(charactersProvider.future)).single.custom!.blocks.single;
    expect((blk.config['stats'] as List).length, 2);
  });

  testWidgets('stat config removes a stat row and persists', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 'b1', type: CustomBlockType.stat, label: 'Abilities', config: {
        'stats': [{'key': 'str', 'label': 'STR'}, {'key': 'dex', 'label': 'DEX'}],
        'min': 3, 'max': 18, 'modFormula': 'raw',
      }),
    ]);
    final c = await _pump(tester, sheet: sheet);
    await tester.tap(find.byKey(const Key('custom-mode-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('custom-block-b1-config')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('custom-cfg-stat-0-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final blk = (await c.read(charactersProvider.future)).single.custom!.blocks.single;
    expect((blk.config['stats'] as List).length, 1);
  });

  testWidgets('stat config changes the modifier formula and persists',
      (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(
          id: 'b1',
          type: CustomBlockType.stat,
          label: 'Abilities',
          config: {
            'stats': [
              {'key': 'str', 'label': 'STR'}
            ],
            'min': 3,
            'max': 18,
            'modFormula': 'raw',
          }),
    ]);
    final c = await _pump(tester, sheet: sheet);
    await tester.tap(find.byKey(const Key('custom-mode-toggle'))); // -> edit
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('custom-block-b1-config')));
    await tester.pumpAndSettle();
    // Tap the formula dropdown and select 'fived'
    await tester.tap(find.byKey(const Key('custom-cfg-formula')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('fived').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final blk =
        (await c.read(charactersProvider.future)).single.custom!.blocks.single;
    expect(blk.config['modFormula'], 'fived');
  });
}
