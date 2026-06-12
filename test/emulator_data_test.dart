import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/emulator_data.dart';

void main() {
  // Tests run with CWD = project root, so read the asset file directly
  // (avoids rootBundle, which needs a widget-test asset bundle).
  final data = EmulatorData(
      jsonDecode(File('assets/emulator_data.json').readAsStringSync())
          as Map<String, dynamic>);

  final d66Keys = [
    for (var t = 1; t <= 6; t++)
      for (var u = 1; u <= 6; u++) t * 10 + u,
  ];

  test('spark and specific table names come in zine order', () {
    expect(data.sparkNames, [
      'action',
      'focus',
      'method',
      'disposition',
      'motivation',
      'dynamics',
    ]);
    expect(data.specificNames, [
      'combat',
      'social',
      'exploration',
      'delving',
      'interpretation',
      'downtime',
      'planning',
    ]);
  });

  test('every d66 table carries exactly keys 11..66 with non-empty text', () {
    for (final name in data.sparkNames) {
      final table = data.sparkTable(name);
      expect(table.keys.toList()..sort(), d66Keys, reason: name);
      expect(table.values.every((v) => v.trim().isNotEmpty), isTrue,
          reason: name);
    }
    for (final name in data.specificNames) {
      final table = data.specificTable(name);
      expect(table.keys.toList()..sort(), d66Keys, reason: name);
      expect(table.values.every((v) => v.trim().isNotEmpty), isTrue,
          reason: name);
    }
  });

  test('pinned cells match the zine (transcription anchors)', () {
    expect(data.d66Entry('combat', 11), 'Aim carefully, wait for an opening');
    expect(data.d66Entry('social', 25), 'Confide a secret');
    expect(data.d66Entry('action', 11), 'Abort');
    expect(data.d66Entry('dynamics', 66), 'Uneasy');
    expect(data.d66Entry('method', 34), 'Magic');
    expect(data.d66Entry('planning', 55), 'Split the party');
  });

  test('throws on unknown table or bad key', () {
    expect(() => data.sparkTable('nope'), throwsArgumentError);
    expect(() => data.specificTable('action'), throwsArgumentError);
    expect(() => data.d66Entry('nope', 11), throwsArgumentError);
    expect(() => data.d66Entry('combat', 10), throwsArgumentError);
  });

  test('attribution carries both license lines', () {
    expect(data.attribution, [
      'PET & Sidekick © Tam H (hedonic.ink), CC-BY 4.0',
      'Triple-O © Cezar Capacle / Critical Kit, CC-BY-SA 4.0',
    ]);
  });
}
