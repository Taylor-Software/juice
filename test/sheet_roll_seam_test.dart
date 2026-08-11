import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/dice.dart';
import 'package:loreseer/engine/models.dart';
import 'package:loreseer/features/cairn_sheet.dart';
import 'package:loreseer/features/ose_sheet.dart';
import 'package:loreseer/shared/theme.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Dice that returns a scripted sequence, so a sheet's roll button has a
/// known outcome. This is the whole point of routing the sheets through
/// [diceProvider]: before it they called `Random()` directly and no test
/// could reach the roll at all.
class _ScriptedDice implements Dice {
  _ScriptedDice(this.faces);
  final List<int> faces;
  int _i = 0;

  @override
  int dN(int n) => faces[_i++ % faces.length];

  @override
  int fate() => dN(3) - 2;
  @override
  int d10Index({int skew = 0}) => dN(10);
  @override
  int d100() => dN(100);
  @override
  bool coin() => dN(2) == 1;
}

Future<void> _pumpCairn(WidgetTester tester, Dice dice) async {
  const sheet = CairnSheet(
      background: 'Hunter', str: 14, dex: 12, wil: 10, maxHp: 6, currentHp: 3);
  SharedPreferences.setMockInitialValues({
    'loreseer.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'loreseer.characters.v1.default': jsonEncode([
      {
        'id': 'c1',
        'name': 'Wren',
        'stats': [],
        'tracks': [],
        'tags': [],
        'cairn': sheet.toJson(),
      }
    ]),
  });
  final container =
      ProviderContainer(overrides: [diceProvider.overrideWithValue(dice)]);
  addTearDown(container.dispose);
  final char = (await container.read(charactersProvider.future)).single;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: CairnSheetView(character: char, onBack: () {})),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _pumpOse(WidgetTester tester, Dice dice) async {
  const sheet = OseSheet(className: 'Fighter', saves: {'death': 12});
  SharedPreferences.setMockInitialValues({
    'loreseer.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'loreseer.characters.v1.default': jsonEncode([
      {
        'id': 'c1',
        'name': 'Bram',
        'stats': [],
        'tracks': [],
        'tags': [],
        'ose': sheet.toJson(),
      }
    ]),
  });
  final container =
      ProviderContainer(overrides: [diceProvider.overrideWithValue(dice)]);
  addTearDown(container.dispose);
  final char = (await container.read(charactersProvider.future)).single;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: OseSheetView(character: char, onBack: () {})),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a seeded die makes a Cairn save deterministic — a pass',
      (tester) async {
    // STR is 14, so a 3 is comfortably under.
    await _pumpCairn(tester, _ScriptedDice([3]));
    await tester.tap(find.byKey(const Key('cairn-save-str')));
    await tester.pump();
    expect(find.textContaining('STR save: 3 — Pass'), findsOneWidget);
  });

  testWidgets('the same button fails on a high roll', (tester) async {
    await _pumpCairn(tester, _ScriptedDice([20]));
    await tester.tap(find.byKey(const Key('cairn-save-str')));
    await tester.pump();
    expect(find.textContaining('STR save: 20 — Fail'), findsOneWidget);
  });

  testWidgets('an OSE save reads the sheet target, not a constant',
      (tester) async {
    // Save target is 12; a 12 is exactly a pass.
    await _pumpOse(tester, _ScriptedDice([12]));
    await tester.tap(find.byKey(const Key('ose-save-roll-death')));
    await tester.pump();
    expect(find.textContaining('12 — Pass'), findsOneWidget);
  });

  test('the real diceProvider hands out a working Dice', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final dice = container.read(diceProvider);
    for (var i = 0; i < 50; i++) {
      expect(dice.dN(6), inInclusiveRange(1, 6));
    }
  });

  test('a seeded Dice is reproducible', () {
    List<int> roll() {
      final d = Dice(Random(7));
      return [for (var i = 0; i < 10; i++) d.dN(20)];
    }

    expect(roll(), roll());
  });
}
