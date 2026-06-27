import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/funnel_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester, FunnelSheet sheet) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default': jsonEncode([
      {
        'id': 'f1',
        'name': '0-Level Funnel',
        'stats': [],
        'tracks': [],
        'tags': [],
        'funnel': sheet.toJson(),
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
        body: Consumer(builder: (_, ref, __) {
          final live =
              ref.watch(charactersProvider).valueOrNull?.firstOrNull ?? char;
          return FunnelSheetView(character: live, onBack: () {});
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

FunnelSheet _dccFunnel() => FunnelSheet(seedSystem: 'dcc', peasants: const [
      FunnelPeasant(
          name: '', hp: 1,
          stats: {'str': 10, 'agi': 10, 'sta': 10, 'per': 10, 'int': 10, 'lck': 10},
          flavor: {'occupation': '', 'weapon': '', 'tradeGoods': ''}),
    ]);

void main() {
  testWidgets('renders the funnel header + add button', (tester) async {
    await _pump(tester, _dccFunnel());
    expect(find.byKey(const Key('funnel-sheet')), findsOneWidget);
    expect(find.textContaining('1 / 1 alive'), findsOneWidget);
    expect(find.byKey(const Key('funnel-peasant-0')), findsOneWidget);
    expect(find.byKey(const Key('funnel-add-peasant')), findsOneWidget);
  });

  testWidgets('add peasant raises count + caps at kFunnelMaxPeasants',
      (tester) async {
    final c = await _pump(tester, _dccFunnel());
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('funnel-add-peasant')));
      await tester.pumpAndSettle();
    }
    expect((await c.read(charactersProvider.future)).single.funnel!.peasants.length, 6);
    final btn = tester.widget<FilledButton>(
        find.byKey(const Key('funnel-add-peasant')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('graduate spawns a hero + funnel persists', (tester) async {
    final c = await _pump(tester, _dccFunnel());
    await tester.tap(find.byKey(const Key('funnel-peasant-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('funnel-peasant-0-graduate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('funnel-graduate-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final list = await c.read(charactersProvider.future);
    expect(list.length, 2);
    final hero = list.firstWhere((x) => x.dcc != null);
    expect(hero.dcc!.className, 'Warrior'); // default first pick
    expect(list.firstWhere((x) => x.funnel != null)
        .funnel!.peasants[0].graduated, true);
  });
}
