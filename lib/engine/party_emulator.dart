import 'dice.dart';
import 'emulator_data.dart';

/// A d66 roll: two d6 read as tens then units (key 11..66).
class D66Result {
  const D66Result(this.tens, this.units);
  final int tens;
  final int units;
  int get key => tens * 10 + units;
}

/// Roll a d66 (first die = tens, second = units).
D66Result rollD66(Dice dice) => D66Result(dice.dN(6), dice.dN(6));

/// One behavior-table roll: which table, the d66 key, and the cell text.
class TableRollResult {
  const TableRollResult(
      {required this.table, required this.key, required this.text});
  final String table;
  final int key;
  final String text;
}

/// Roll d66 on a named spark/specific table and look up the entry.
TableRollResult rollBehavior(EmulatorData data, String table, Dice dice) {
  final key = rollD66(dice).key;
  return TableRollResult(
      table: table, key: key, text: data.d66Entry(table, key));
}

/// Roll each named table in order (the zine's spark combos, e.g.
/// Action + Focus).
List<TableRollResult> rollCombo(
        EmulatorData data, List<String> tables, Dice dice) =>
    [for (final t in tables) rollBehavior(data, t, dice)];
