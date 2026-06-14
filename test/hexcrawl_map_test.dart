import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/engine/hexcrawl_map.dart';
import 'package:juice_oracle/engine/map_builder.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('HexCell.site round-trips and is omitted from JSON when null', () {
    const withSite = HexCell(
        col: 1, row: 2, envRow: 1, terrain: 'forest', site: 'Cave or grotto');
    final back = HexCell.maybeFromJson(withSite.toJson())!;
    expect(back.site, 'Cave or grotto');
    expect(back.terrain, 'forest');
    const bare = HexCell(col: 0, row: 0, envRow: 1);
    expect(bare.toJson().containsKey('site'), isFalse);
    expect(HexCell.maybeFromJson(bare.toJson())!.site, isNull);
  });

  final data = HexcrawlData(
      jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
          as Map<String, dynamic>);
  final terrainKeys = data.terrains.map((t) => t.key).toSet();

  test('growRegion yields N connected hexes with defined terrain', () {
    final region = growRegion(
        data: data, climate: 'temperate', count: 12, dice: Dice(Random(5)));
    expect(region.length, 12);
    final coords = {for (final g in region) (g.col, g.row)};
    expect(coords.length, 12); // no duplicate cells
    for (final g in region) {
      expect(terrainKeys, contains(g.terrain));
      if (g.site != null) expect(data.siteTypes, contains(g.site));
    }
    // Connected: every non-origin hex has a neighbour in the region.
    for (final g in region) {
      if (g.col == 0 && g.row == 0) continue;
      final hasNeighbour = hexNeighbors(g.col, g.row)
          .any((n) => coords.contains((n.col, n.row)));
      expect(hasNeighbour, isTrue, reason: 'hex ${g.col},${g.row} is isolated');
    }
  });

  test('growRegion is deterministic per seed and handles count<=0', () {
    final a =
        growRegion(data: data, climate: 'hot', count: 8, dice: Dice(Random(1)));
    final b =
        growRegion(data: data, climate: 'hot', count: 8, dice: Dice(Random(1)));
    expect(a.map((g) => '${g.col},${g.row},${g.terrain}'),
        b.map((g) => '${g.col},${g.row},${g.terrain}'));
    expect(
        growRegion(data: data, climate: 'hot', count: 0, dice: Dice(Random(1))),
        isEmpty);
  });

  test('rollCrawlHex returns a defined neighbour terrain', () {
    final r = rollCrawlHex(data, 'forest', Dice(Random(3)));
    expect(terrainKeys, contains(r.terrain));
    if (r.site != null) expect(data.siteTypes, contains(r.site));
  });
}
