import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/features/map_screen.dart';

void main() {
  test('every hexcrawl terrain key has a hue', () {
    final data = HexcrawlData(
        jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
            as Map<String, dynamic>);
    for (final t in data.terrains) {
      expect(hexcrawlTerrainHues.containsKey(t.key), isTrue,
          reason: 'no hue for terrain ${t.key}');
    }
  });
}
