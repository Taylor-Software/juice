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
  test('HexCell.siteLines round-trips and omits when empty', () {
    const h = HexCell(
        col: 1,
        row: 1,
        envRow: 1,
        site: 'Cave or grotto',
        siteLines: ['Held by: Scavengers']);
    final back = HexCell.maybeFromJson(h.toJson())!;
    expect(back.siteLines.single, 'Held by: Scavengers');
    expect(
        const HexCell(col: 0, row: 0, envRow: 1)
            .toJson()
            .containsKey('siteLines'),
        isFalse);
  });

  test('rollSiteLine: labelled by index, body from the right table', () {
    final data = _data();
    final occ = rollSiteLine(data, 0, Dice(Random(1)));
    expect(occ.startsWith('Held by: '), isTrue);
    expect(data.siteOccupants, contains(occ.substring('Held by: '.length)));
    final hook = rollSiteLine(data, 1, Dice(Random(1)));
    expect(hook.startsWith('Hook: '), isTrue);
    final feat = rollSiteLine(data, 2, Dice(Random(1)));
    expect(feat.startsWith('Feature: '), isTrue);
  });

  test('rollSiteDetail returns 4 ordered lines', () {
    final lines = rollSiteDetail(_data(), Dice(Random(5)));
    expect(lines.length, 4);
    expect(lines[0].startsWith('Held by: '), isTrue);
    expect(lines[1].startsWith('Hook: '), isTrue);
    expect(lines[2].startsWith('Feature: '), isTrue);
    expect(lines[3].startsWith('Feature: '), isTrue);
  });

  test('crawlSite appends one line (cap 5); generateSite sets 4', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final data = _data();
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    final n = c.read(mapProvider.notifier);
    await c.read(mapProvider.future);
    await n.revealHexAt(0, 0, 1);
    await n.setHexSite(0, 0, 'Cave or grotto');

    await n.crawlSite(0, 0, data, Dice(Random(3)));
    var s = await c.read(mapProvider.future);
    expect(s.hexes.first.siteLines.length, 1);

    await n.generateSite(0, 0, data, Dice(Random(4)));
    s = await c.read(mapProvider.future);
    expect(s.hexes.first.siteLines.length, 4);
  });
}
