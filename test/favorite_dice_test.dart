import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/features/dice_roller_screen.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  test('favorites add/dedupe/cap/remove persist', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(favoriteDiceProvider.notifier);
    await c.read(favoriteDiceProvider.future);

    await n.add(' 2d6+3 ');
    await n.add('2d6+3'); // dedupe
    await n.add('');
    expect(c.read(favoriteDiceProvider).value, ['2d6+3']);

    for (var i = 0; i < 13; i++) {
      await n.add('d$i');
    }
    expect(c.read(favoriteDiceProvider).value!.length, 12); // capped
    expect(c.read(favoriteDiceProvider).value!.first,
        isNot('2d6+3')); // oldest evicted

    await n.remove('d12');
    expect(c.read(favoriteDiceProvider).value, isNot(contains('d12')));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('juice.favorite_dice.v1'),
        c.read(favoriteDiceProvider).value);
  });

  testWidgets('roller pins a favorite and rolls it from the chip', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: DiceRollerScreen(dice: Dice(Random(7)))),
      ),
    ));
    await t.pumpAndSettle();

    await t.enterText(find.byKey(const Key('dice-input')), '2d6+1');
    await t.pump();
    await t.tap(find.byKey(const Key('dice-fav-add')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('dice-fav-2d6+1')), findsOneWidget);

    await t.tap(find.byKey(const Key('dice-fav-2d6+1')));
    await t.pumpAndSettle();
    // The favorite rolled: its expression shows on the result card.
    expect(find.text('2d6+1'), findsWidgets);
  });
}
