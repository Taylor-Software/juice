/// Pure pick helpers for the generic hexcrawl toolkit. No Flutter. Weighted and
/// uniform table rolls against a [Dice]; the content lives in [HexcrawlData].
library;

import 'dice.dart';
import 'hexcrawl_data.dart';
import 'models.dart';

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

/// One ring sub-hex of a local-zoom flower: finer terrain (from the parent
/// terrain's neighbour table) + a local feature. [slot] is the ring position.
LocalCell rollLocalCell(
    HexcrawlData data, String centerTerrain, int slot, Dice dice) {
  final terrain =
      rollNeighbour(data, centerTerrain, dice)?.key ?? centerTerrain;
  return LocalCell(
      slot: slot,
      terrain: terrain,
      feature: rollFrom(data.localFeatures, dice));
}

/// One line of a site writeup. index 0 = occupant, 1 = hook, >=2 = a feature.
String rollSiteLine(HexcrawlData data, int index, Dice dice) {
  if (index == 0) return 'Held by: ${rollFrom(data.siteOccupants, dice)}';
  if (index == 1) return 'Hook: ${rollFrom(data.siteHooks, dice)}';
  return 'Feature: ${rollFrom(data.siteFeatures, dice)}';
}

/// The full site writeup (occupant, hook, two features) for the Full path.
List<String> rollSiteDetail(HexcrawlData data, Dice dice) =>
    [for (var i = 0; i < 4; i++) rollSiteLine(data, i, dice)];

/// A site interior area type (H4c).
String rollSiteArea(HexcrawlData data, Dice dice) =>
    rollFrom(data.siteAreaTypes, dice);
