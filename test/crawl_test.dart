import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';

OracleData _loadData() {
  final raw = File('assets/oracle_data.json').readAsStringSync();
  return OracleData(jsonDecode(raw) as Map<String, dynamic>);
}

void main() {
  final data = _loadData();

  group('CrawlState model', () {
    test('defaults: no environment yet, not lost, dialog at center', () {
      const s = CrawlState();
      expect(s.envRow, isNull);
      expect(s.lost, isFalse);
      expect(s.dialogRow, 2);
      expect(s.dialogCol, 2);
    });

    test('json round-trip preserves all fields', () {
      const s = CrawlState(envRow: 7, lost: true, dialogRow: 0, dialogCol: 4);
      final back = CrawlState.fromJson(s.toJson());
      expect(back.envRow, 7);
      expect(back.lost, isTrue);
      expect(back.dialogRow, 0);
      expect(back.dialogCol, 4);
    });

    test('copyWith can clear envRow via sentinel', () {
      const s = CrawlState(envRow: 3, lost: true);
      final reset = s.copyWith(clearEnvRow: true, lost: false);
      expect(reset.envRow, isNull);
      expect(reset.lost, isFalse);
      expect(reset.dialogRow, 2);
    });
  });
}
