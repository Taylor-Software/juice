import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/hexcrawl.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/engine/map_builder.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

HexcrawlData _data() => HexcrawlData(
    jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  test('HexCell.siteAreas round-trips and omits when empty', () {
    const h = HexCell(
        col: 0,
        row: 0,
        envRow: 1,
        site: 'Ruined structure',
        siteAreas: [SiteArea(x: 0, y: 0, name: 'Entrance')]);
    final back = HexCell.maybeFromJson(h.toJson())!;
    expect(back.siteAreas.single.name, 'Entrance');
    expect(
        const HexCell(col: 0, row: 0, envRow: 1)
            .toJson()
            .containsKey('siteAreas'),
        isFalse);
  });

  test('rollSiteArea is a defined area type', () {
    final data = _data();
    expect(data.siteAreaTypes, contains(rollSiteArea(data, Dice(Random(1)))));
  });

  test('nextSiteAreaPosition: first at origin, then non-overlapping', () {
    final dice = Dice(Random(7));
    final areas = <SiteArea>[];
    final occupied = <(int, int)>{};
    for (var i = 0; i < 8; i++) {
      final p = nextSiteAreaPosition(areas, dice);
      expect(occupied.contains((p.x, p.y)), isFalse);
      occupied.add((p.x, p.y));
      areas.add(SiteArea(x: p.x, y: p.y, name: 'A'));
    }
    expect(areas.first.x, 0);
    expect(areas.first.y, 0);
  });

  test('crawlSiteArea adds one area; generateSiteInterior sets N (clamped)',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final data = _data();
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    final n = c.read(mapProvider.notifier);
    await c.read(mapProvider.future);
    await n.revealHexAt(0, 0, 1);
    await n.setHexSite(0, 0, 'Ruined structure');

    await n.crawlSiteArea(0, 0, data, Dice(Random(2)));
    var s = await c.read(mapProvider.future);
    expect(s.hexes.first.siteAreas.length, 1);

    await n.generateSiteInterior(0, 0, 5, data, Dice(Random(3)));
    s = await c.read(mapProvider.future);
    expect(s.hexes.first.siteAreas.length, 5);

    await n.generateSiteInterior(0, 0, 99, data, Dice(Random(4))); // clamp 12
    s = await c.read(mapProvider.future);
    expect(s.hexes.first.siteAreas.length, 12);

    // No-op without a site.
    await n.revealHexAt(2, 0, 1);
    await n.crawlSiteArea(2, 0, data, Dice(Random(5)));
    s = await c.read(mapProvider.future);
    expect(s.hexes.firstWhere((h) => h.col == 2).siteAreas, isEmpty);
  });
}
