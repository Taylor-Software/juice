import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/state/providers.dart';

HexcrawlData _data() => HexcrawlData(
    jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('crawlHexcrawl adds a hex with terrain and advances current', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    final n = c.read(mapProvider.notifier);
    await c.read(mapProvider.future);

    await n.crawlHexcrawl(_data(), 'temperate', Dice(Random(2)));
    var s = await c.read(mapProvider.future);
    expect(s.hexes.length, 1);
    expect(s.hexes.single.terrain, isNotNull);

    await n.crawlHexcrawl(_data(), 'temperate', Dice(Random(4)));
    s = await c.read(mapProvider.future);
    expect(s.hexes.length, 2);
    expect(s.currentHexCol, isNotNull);
  });

  test('generateRegion populates N connected hexes with terrain', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    final n = c.read(mapProvider.notifier);
    await c.read(mapProvider.future);

    await n.generateRegion(_data(), 'hot', 10, Dice(Random(7)));
    final s = await c.read(mapProvider.future);
    expect(s.hexes.length, 10);
    expect(s.hexes.every((h) => h.terrain != null), isTrue);
  });
}
