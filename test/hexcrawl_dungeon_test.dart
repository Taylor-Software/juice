import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/hexcrawl.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final data = HexcrawlData(
      jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
          as Map<String, dynamic>);

  test('rollDungeonRoom: title is a room type; detail has content + dressing',
      () {
    final r = rollDungeonRoom(data, Dice(Random(4)));
    expect(data.dungeonRoomTypes, contains(r.title));
    expect(data.dungeonContents.any((c) => r.detail.contains(c)), isTrue);
    expect(data.dungeonDressing.any((d) => r.detail.contains(d)), isTrue);
  });

  test('crawlDungeon adds a room; generateDungeon adds N rooms', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    final n = c.read(mapProvider.notifier);
    await c.read(mapProvider.future);

    await n.crawlDungeon(data, Dice(Random(2)));
    var s = await c.read(mapProvider.future);
    expect(s.rooms.length, 1);
    expect(s.rooms.single.title, isNotEmpty);

    await n.generateDungeon(data, 5, Dice(Random(8)));
    s = await c.read(mapProvider.future);
    expect(s.rooms.length, 6); // 1 + 5
  });
}
