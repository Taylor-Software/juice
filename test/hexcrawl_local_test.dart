import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/hexcrawl.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

HexcrawlData _data() => HexcrawlData(
    jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  test('HexCell.local round-trips and omits when empty', () {
    const h = HexCell(col: 1, row: 2, envRow: 1, terrain: 'forest', local: [
      LocalCell(slot: 0, terrain: 'hills', feature: 'A rocky outcrop'),
    ]);
    final j = h.toJson();
    expect(j['local'], isNotNull);
    final back = HexCell.maybeFromJson(j)!;
    expect(back.local.single.slot, 0);
    expect(back.local.single.terrain, 'hills');
    expect(back.local.single.feature, 'A rocky outcrop');

    final empty = const HexCell(col: 0, row: 0, envRow: 1).toJson();
    expect(empty.containsKey('local'), isFalse);
  });

  test('rollLocalCell: terrain is a defined key, feature from localFeatures',
      () {
    final data = _data();
    final keys = data.terrains.map((t) => t.key).toSet();
    final c = rollLocalCell(data, 'forest', 3, Dice(Random(1)));
    expect(c.slot, 3);
    expect(keys, contains(c.terrain));
    expect(data.localFeatures, contains(c.feature));
  });

  test('crawlLocal adds one ring cell (cap 6); generateLocal fills 6',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final data = _data();
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    final n = c.read(mapProvider.notifier);
    await c.read(mapProvider.future);
    // Seed one terrained hex via the public region path.
    await n.generateRegion(data, 'temperate', 1, Dice(Random(2)));
    var s = await c.read(mapProvider.future);
    final h0 = s.hexes.first;

    await n.crawlLocal(h0.col, h0.row, data, Dice(Random(3)));
    s = await c.read(mapProvider.future);
    expect(
        s.hexes
            .firstWhere((h) => h.col == h0.col && h.row == h0.row)
            .local
            .length,
        1);

    await n.generateLocal(h0.col, h0.row, data, Dice(Random(4)));
    s = await c.read(mapProvider.future);
    expect(
        s.hexes
            .firstWhere((h) => h.col == h0.col && h.row == h0.row)
            .local
            .length,
        6);
  });
}
