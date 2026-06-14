import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/lonelog_data.dart';

void main() {
  final data = LonelogData(
      jsonDecode(File('assets/lonelog_data.json').readAsStringSync())
          as Map<String, dynamic>);

  test('legend loads with the expected shapes', () {
    expect(data.version, '1.5.0');
    expect(data.symbols.map((s) => s.symbol),
        containsAll(['@', '?', 'd:', '->', '=>']));
    expect(data.tagPrefixes.length, 16);
    expect(data.blocks.length, 5);
    expect(data.addons.length, 7);
    expect(data.examples.length, greaterThanOrEqualTo(4));
  });

  test('reserved prefixes are unique', () {
    final ps = data.tagPrefixes.map((p) => p.prefix).toList();
    expect(ps.toSet().length, ps.length);
  });

  test('every example has a title and non-empty lines', () {
    for (final ex in data.examples) {
      expect(ex.title, isNotEmpty);
      expect(ex.lines, isNotEmpty);
    }
  });
}
