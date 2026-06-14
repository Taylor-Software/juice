import 'package:flutter/material.dart';
import '../engine/dice.dart';
import '../features/dice_roller_screen.dart';

/// Opens the Dice Roller as a modal bottom sheet (its home is the entry line,
/// not a tab).
Future<void> showDiceSheet(BuildContext context, Dice dice) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.85,
      child: SafeArea(child: DiceRollerScreen(dice: dice)),
    ),
  );
}
