/// Pure 4D6 classic-dungeon room resolution over DungeonTables. Expands
/// {ref:XX} cross-reference tokens (depth-capped), applies the A2 stockDouble
/// effect (tierBump/treasureBonus/leadsToCaves are parsed but deferred to the
/// P2 treasure/level features), rolls reaction + faction for organized
/// monsters, and renders the room's detail text. No Flutter, no I/O.
library;

import '../dice.dart';
import 'faction.dart';
import 'footprint.dart';
import 'tables.dart';

enum RoomType { corridor, chamber }

class DungeonGenContext {
  const DungeonGenContext(
      {required this.level,
      required this.effect,
      required this.tables,
      required this.factions,
      required this.roomId});
  final int level;
  final A2Type effect;
  final DungeonTables tables;
  final FactionRegistry factions;

  /// Id of the room being generated. The caller mints it BEFORE generating so
  /// a faction assigned here carries the real room id from the start (no
  /// placeholder reconciliation).
  final String roomId;
}

class RoomResult {
  const RoomResult(
      {required this.type,
      required this.entryDoorKind,
      required this.shapeFamily,
      required this.detail,
      required this.factions});
  final RoomType type;
  final DoorKind entryDoorKind;
  final String shapeFamily;
  final String detail;
  final FactionRegistry factions;
}

/// D6 type die -> (roomType, entry door kind), per the zine's B1/C1 headers.
(RoomType, DoorKind) _typeDie(int d6) => switch (d6) {
      1 => (RoomType.corridor, DoorKind.locked),
      2 => (RoomType.corridor, DoorKind.door),
      3 => (RoomType.corridor, DoorKind.open),
      4 => (RoomType.chamber, DoorKind.open),
      5 => (RoomType.chamber, DoorKind.door),
      _ => (RoomType.chamber, DoorKind.locked),
    };

int _d66(Dice dice) => dice.dN(6) * 10 + dice.dN(6);

/// Human labels for the dict-shaped build-element tables (H1/H2/H3/H6/H8), which
/// carry nested sub-tables rather than a flat row list. P1 renders these as a
/// word rather than expanding their internal structure.
const _dictRefLabels = <String, String>{
  'H1': 'a coffin',
  'H2': 'a statue',
  'H3': 'a secret room',
  'H6': 'a shrine',
  'H8': 'treasure',
};

String _label(DungeonTables t, String id) =>
    _dictRefLabels[id] ?? t.labelFallbacks[id] ?? id;

/// Expand {ref:XX} tokens in [text]. Recurses into list-shaped tables up to
/// [budget] levels; B4 (a `{triggers,effects}` dict) renders one "trigger ->
/// effect" trap; other dict tables render a `_dictRefLabels`/`labelFallbacks`
/// word; a P2-only or unknown ref becomes its fallback label; a self-referential
/// ref stops at [budget].
String _expand(String text, DungeonTables t, Dice dice, {int budget = 4}) {
  final re = RegExp(r'\{ref:([A-Z]\d+)\}');
  return text.replaceAllMapped(re, (m) {
    final id = m.group(1)!;
    if (budget <= 0) return _label(t, id);
    final table = t.raw[id];
    if (table is List) {
      final row = table[dice.dN(table.length) - 1].toString();
      return _expand(row, t, dice, budget: budget - 1);
    }
    if (table is Map && table['triggers'] is List && table['effects'] is List) {
      final trig = (table['triggers'] as List);
      final eff = (table['effects'] as List);
      return '${trig[dice.dN(trig.length) - 1]} -> ${eff[dice.dN(eff.length) - 1]}';
    }
    return _label(t, id);
  });
}

RoomResult generateRoom(DungeonGenContext ctx, Dice dice) {
  final t = ctx.tables;
  final (type, entryKind) = _typeDie(dice.dN(6));
  final d66 = _d66(dice);
  final rangeMap =
      type == RoomType.corridor ? t.corridorFamilies : t.chamberFamilies;
  final catalog = type == RoomType.corridor ? kCorridorShapes : kChamberShapes;
  final family = shapesForRoll(d66, rangeMap, catalog).first.family;

  final lines = <String>[
    '${type == RoomType.corridor ? "Corridor" : "Chamber"} ($family)'
  ];
  var factions = ctx.factions;

  final stockTable = type == RoomType.corridor ? t.b2 : t.c2;
  final stock = stockTable[dice.dN(stockTable.length) - 1];
  final wantsMonster = stock.contains('Monster');
  lines.add(_expand(stock, t, dice));

  if (wantsMonster && t.upperMonsters.isNotEmpty) {
    final mon = t.upperMonsters[dice.dN(t.upperMonsters.length) - 1];
    final n = ctx.effect.stockDouble ? 2 : 1;
    final reaction = t.reaction['${dice.dN(6) + dice.dN(6)}'] ?? '';
    lines.add(
        'Monsters: ${n}x ${mon.text} (${mon.count}) — reaction: $reaction');
    if (mon.organized) {
      final DungeonFaction? fac;
      (factions, fac) =
          assignFaction(factions, mon.text, ctx.roomId, t.factionNames, dice);
      if (fac != null) lines.add('Faction: ${fac.name}');
    }
  }

  return RoomResult(
      type: type,
      entryDoorKind: entryKind,
      shapeFamily: family,
      detail: lines.join('\n'),
      factions: factions);
}
