import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';

OracleData _loadData() =>
    OracleData(jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final data = _loadData();

  group('d66Index', () {
    test('row 11 -> 0, row 66 -> 35, row 34 -> 20', () {
      expect(d66Index(1, 1), 0);
      expect(d66Index(6, 6), 35);
      expect(d66Index(3, 4), 20);
    });
  });

  group('wordOracle', () {
    test('returns Word Oracle with 3 labelled rolls from the tables', () {
      final oracle = Oracle(data, Dice(Random(7)));
      final r = oracle.wordOracle();
      expect(r.title, 'Word Oracle');
      expect(r.rolls.map((e) => e.label).toList(),
          ['Action', 'Descriptor', 'Subject']);
      expect(data.table('word_action'), contains(r.rolls[0].value));
      expect(data.table('word_descriptor'), contains(r.rolls[1].value));
      expect(data.table('word_subject'), contains(r.rolls[2].value));
      for (final roll in r.rolls) {
        expect(roll.detail, matches(RegExp(r'^d66 → [1-6][1-6]$')));
      }
    });
  });
}
