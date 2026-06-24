import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/dice_notation.dart';
import 'package:juice_oracle/features/dice_roll_animation.dart';

void main() {
  final result = parseDice('2d6+1').roll(Dice(Random(1)));

  testWidgets('settles to the final total + group label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DiceRollAnimation(result: result, rollId: 1)),
    ));
    await tester.pumpAndSettle(); // past the tumble (timer cancels on settle)
    expect(tester.widget<Text>(find.byKey(const Key('dice-total'))).data,
        '${result.total}');
    expect(find.textContaining('2d6'), findsOneWidget); // the group label
  });

  testWidgets('reduced-motion renders immediately, no pending timer',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: DiceRollAnimation(result: result, rollId: 1),
          );
        }),
      ),
    ));
    await tester.pump(); // one frame — no tumble to settle
    expect(tester.widget<Text>(find.byKey(const Key('dice-total'))).data,
        '${result.total}');
  });

  testWidgets('changing rollId mid-tumble replays then settles',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DiceRollAnimation(result: result, rollId: 1)),
    ));
    await tester.pump(const Duration(milliseconds: 100)); // mid-tumble
    final r2 = parseDice('1d20').roll(Dice(Random(2)));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DiceRollAnimation(result: r2, rollId: 2)),
    ));
    await tester
        .pumpAndSettle(); // the replay settles (no hung/duplicate timer)
    // dice-total now reflects the SECOND roll — proves the replay re-ran cleanly.
    expect(tester.widget<Text>(find.byKey(const Key('dice-total'))).data,
        '${r2.total}');
  });

  testWidgets('dropped dice settle struck-through', (tester) async {
    final dropped = parseDice('4d6kh3').roll(Dice(Random(1))); // 1 die dropped
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DiceRollAnimation(result: dropped, rollId: 1)),
    ));
    await tester.pumpAndSettle();
    final struck = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.style?.decoration == TextDecoration.lineThrough);
    expect(struck, isNotEmpty); // the dropped die's face
  });
}
