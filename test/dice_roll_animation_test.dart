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
}
