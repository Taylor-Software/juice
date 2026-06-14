/// Region + crawl terrain/site generation for the Hexcrawl toolkit (H2). Pure,
/// no Flutter. Reuses H1's pick engine and the existing odd-q [hexNeighbors].
library;

import 'dice.dart';
import 'hexcrawl.dart';
import 'hexcrawl_data.dart';
import 'map_builder.dart' show hexNeighbors;

/// One generated hex, relative to the region origin (0,0).
class GenHex {
  const GenHex(
      {required this.col, required this.row, required this.terrain, this.site});
  final int col;
  final int row;
  final String terrain;
  final String? site;
}

/// A site on ~1/3 of hexes (d6 <= 2), drawn from the generic site types.
String? _rollSite(HexcrawlData data, Dice dice) =>
    dice.dN(6) <= 2 ? rollFrom(data.siteTypes, dice) : null;

/// A single crawl hex: terrain rolled from [fromTerrain] via neighbouring
/// terrain, plus an optional site.
({String terrain, String? site}) rollCrawlHex(
    HexcrawlData data, String fromTerrain, Dice dice) {
  final t = rollNeighbour(data, fromTerrain, dice);
  return (terrain: t?.key ?? fromTerrain, site: _rollSite(data, dice));
}

/// Grow a connected region of [count] hexes from a climate-seeded start at
/// (0,0). Each new hex is an empty neighbour of a placed hex; its terrain is
/// rolled from an adjacent placed hex. Deterministic for a given [dice].
List<GenHex> growRegion(
    {required HexcrawlData data,
    required String climate,
    required int count,
    required Dice dice}) {
  if (count <= 0) return const [];
  final start = rollTerrain(data, climate, dice);
  final startKey = start?.key ?? data.terrains.first.key;
  final placed = <(int, int), GenHex>{
    (0, 0):
        GenHex(col: 0, row: 0, terrain: startKey, site: _rollSite(data, dice)),
  };
  while (placed.length < count) {
    final candidates = <(int, int)>{};
    for (final h in placed.values) {
      for (final n in hexNeighbors(h.col, h.row)) {
        if (!placed.containsKey((n.col, n.row))) candidates.add((n.col, n.row));
      }
    }
    if (candidates.isEmpty) break;
    final list = candidates.toList();
    final pick = list[dice.dN(list.length) - 1];
    final adj = hexNeighbors(pick.$1, pick.$2)
        .where((n) => placed.containsKey((n.col, n.row)))
        .toList();
    final from = adj[dice.dN(adj.length) - 1];
    final fromTerrain = placed[(from.col, from.row)]!.terrain;
    final t = rollNeighbour(data, fromTerrain, dice);
    placed[(pick.$1, pick.$2)] = GenHex(
        col: pick.$1,
        row: pick.$2,
        terrain: t?.key ?? fromTerrain,
        site: _rollSite(data, dice));
  }
  return placed.values.toList();
}
