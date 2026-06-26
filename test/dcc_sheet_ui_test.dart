import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/dcc_sheet.dart';
import 'package:juice_oracle/features/sheet_widgets.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpDcc(WidgetTester tester, DccSheet sheet) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default': jsonEncode([
      {
        'id': 'c1',
        'name': 'Reaper',
        'stats': [],
        'tracks': [],
        'tags': [],
        'dcc': sheet.toJson(),
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
          return DccSheetView(character: live, onBack: () {});
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('luckTokensSection', () {
    testWidgets('spend and restore fire callbacks', (tester) async {
      int? setTo;
      var reset = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => luckTokensSection(
              keyPrefix: 'dcc-luck',
              label: 'Luck (LCK)',
              current: 3,
              max: 5,
              onSet: (v) => setTo = v,
              onReset: () => reset = true,
            ),
          ),
        ),
      ));
      expect(find.text('3 / 5'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dcc-luck-spend')));
      expect(setTo, 2);
      await tester.tap(find.byKey(const Key('dcc-luck-restore')));
      expect(reset, true);
    });

    testWidgets('spend disabled at zero', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: luckTokensSection(
            keyPrefix: 'dcc-luck',
            label: 'Luck',
            current: 0,
            max: 5,
            onSet: (_) {},
            onReset: () {},
          ),
        ),
      ));
      final btn =
          tester.widget<IconButton>(find.byKey(const Key('dcc-luck-spend')));
      expect(btn.onPressed, isNull);
    });
  });
}
