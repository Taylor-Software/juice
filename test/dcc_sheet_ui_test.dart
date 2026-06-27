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

  group('DccSheetView leveled', () {
    DccSheet leveledWarrior() => const DccSheet(
          className: 'Warrior',
          alignment: 'Lawful',
          stats: {
            'str': 16,
            'agi': 12,
            'sta': 13,
            'per': 9,
            'int': 8,
            'lck': 11,
          },
          lckMax: 11,
          currentHp: 8,
          maxHp: 8,
        );

    DccSheet leveledCleric() => const DccSheet(
          className: 'Cleric',
          alignment: 'Lawful',
          stats: {
            'str': 10,
            'agi': 10,
            'sta': 10,
            'per': 14,
            'int': 9,
            'lck': 10,
          },
          lckMax: 10,
          currentHp: 6,
          maxHp: 6,
        );

    testWidgets('deed die only for Warrior/Dwarf', (tester) async {
      await _pumpDcc(tester, leveledWarrior());
      expect(find.byKey(const Key('dcc-deed-roll')), findsOneWidget);
      expect(find.byKey(const Key('dcc-spell-check-roll')), findsNothing);
      expect(find.byKey(const Key('dcc-disapproval-roll')), findsNothing);
    });

    testWidgets('caster sections only for Cleric', (tester) async {
      await _pumpDcc(tester, leveledCleric());
      expect(find.byKey(const Key('dcc-deed-roll')), findsNothing);
      expect(find.byKey(const Key('dcc-spell-check-roll')), findsOneWidget);
      expect(find.byKey(const Key('dcc-disapproval-roll')), findsOneWidget);
    });

    testWidgets('spellburn stepper reduces effective stat', (tester) async {
      await _pumpDcc(tester, leveledCleric());
      // PER 14 -> burn raises spellburn; tap the per burn +
      await tester.tap(find.byKey(const Key('dcc-burn-per-plus')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Spellburn: +1'), findsOneWidget);
    });

    testWidgets('disapproval roll shows snackbar', (tester) async {
      await _pumpDcc(tester, leveledCleric());
      await tester.tap(find.byKey(const Key('dcc-disapproval-roll')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Disapproval check:'), findsOneWidget);
    });

    testWidgets('renders stats grid and lucky-sign field', (tester) async {
      await _pumpDcc(tester, leveledWarrior());
      expect(find.byKey(const Key('dcc-sheet')), findsOneWidget);
      expect(find.byKey(const Key('dcc-lucky-sign')), findsOneWidget);
      expect(find.byKey(const Key('dcc-stat-str')), findsOneWidget);
      // STR 16 -> +2
      expect(find.textContaining('STR (+2)'), findsOneWidget);
    });

    testWidgets('save roll opens DC dialog and shows snackbar', (tester) async {
      await _pumpDcc(tester, leveledWarrior());
      await tester.tap(find.byKey(const Key('dcc-fort-roll')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dcc-dc-field')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('dcc-dc-field')), '11');
      await tester.tap(find.byKey(const Key('dcc-dc-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Fortitude:'), findsOneWidget);
      expect(find.textContaining('DC 11'), findsOneWidget);
    });

    testWidgets('luck spend persists via shared widget', (tester) async {
      final c = await _pumpDcc(tester, leveledWarrior());
      expect(find.text('11 / 11'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dcc-luck-spend')));
      await tester.pumpAndSettle();
      expect(find.text('10 / 11'), findsOneWidget);
      expect((await c.read(charactersProvider.future)).single.dcc!.stats['lck'],
          10);
    });
  });
}
