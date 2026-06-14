/// Pure pick helpers for the generic hexcrawl toolkit. No Flutter. Weighted and
/// uniform table rolls against a [Dice]; the content lives in [HexcrawlData].
library;

import 'dice.dart';
import 'hexcrawl_data.dart';

/// Weighted pick: probability proportional to weight. Returns the terrain key.
String weightedPick(List<WeightedTerrain> table, Dice dice) {
  final total = table.fold<int>(0, (a, e) => a + e.weight);
  var roll = dice.dN(total); // 1..total
  for (final e in table) {
    roll -= e.weight;
    if (roll <= 0) return e.terrain;
  }
  return table.last.terrain;
}

/// Uniform pick from a flat list of strings.
String rollFrom(List<String> options, Dice dice) =>
    options[dice.dN(options.length) - 1];

/// A starting terrain for [climate].
HexTerrain? rollTerrain(HexcrawlData data, String climate, Dice dice) {
  final table = data.climateToTerrain[climate];
  if (table == null || table.isEmpty) return null;
  return data.terrainByKey(weightedPick(table, dice));
}

/// The terrain of a hex adjacent to one of [terrainKey].
HexTerrain? rollNeighbour(HexcrawlData data, String terrainKey, Dice dice) {
  final table = data.neighbouringTerrain[terrainKey];
  if (table == null || table.isEmpty) return null;
  return data.terrainByKey(weightedPick(table, dice));
}

/// A generic dungeon room: a room type (title) plus content + dressing (detail).
({String title, String detail}) rollDungeonRoom(HexcrawlData data, Dice dice) {
  final type = rollFrom(data.dungeonRoomTypes, dice);
  final content = rollFrom(data.dungeonContents, dice);
  final dressing = rollFrom(data.dungeonDressing, dice);
  return (title: type, detail: '$content. $dressing.');
}
