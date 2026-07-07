/// Pure 4D6 classic-dungeon room resolution over DungeonTables, for both the
/// dungeon branch (corridor/chamber, B/C tables) and the cave branch
/// (tunnel/cave, E/F tables). Expands {ref:XX} cross-reference tokens
/// (depth-capped, with real H8 treasure rolls), picks the monster table by
/// depth tier (G2/G3/G4 + A2/D2 tier bump), applies the type effect's
/// stockDouble/onStock6/monsterDie, resolves {lvl:*} level/crossover tokens,
/// rolls reaction + faction for organized monsters, and renders the room's
/// detail text. No Flutter, no I/O.
library;

import 'dart:math' show min;

import '../dice.dart';
import 'faction.dart';
import 'footprint.dart';
import 'tables.dart';
import 'treasure.dart';

enum RoomType { corridor, chamber, tunnel, cave }

/// Which side of the complex a room belongs to: the built dungeon (A-C
/// tables) or the natural caves (D-F tables).
enum DungeonBranch { dungeon, cave }

/// Branch of a persisted room-type string ('tunnel'/'cave' -> cave branch;
/// 'corridor'/'chamber'/legacy null -> dungeon branch).
DungeonBranch branchOfRoomType(String? roomType) =>
    roomType == 'tunnel' || roomType == 'cave'
        ? DungeonBranch.cave
        : DungeonBranch.dungeon;

class DungeonGenContext {
  const DungeonGenContext(
      {required this.branch,
      required this.depth,
      required this.effect,
      required this.tables,
      required this.factions,
      required this.roomId,
      this.stone = ''});
  final DungeonBranch branch;

  /// Dungeon level being explored (1 = the entrance level). Drives the
  /// monster tier and the H8 treasure row.
  final int depth;
  final A2Type effect;
  final DungeonTables tables;
  final FactionRegistry factions;

  /// Cavestone (E5) of the current cave network, kept for context/display.
  final String stone;

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
      required this.factions,
      this.levelDelta = 0,
      this.crossoverTo});
  final RoomType type;
  final DoorKind entryDoorKind;
  final String shapeFamily;
  final String detail;
  final FactionRegistry factions;

  /// Level change carried by a {lvl:*} token in the room's detail (down = -1,
  /// updown = +/-1, chasm = -1..-4). 0 = stays on this level.
  final int levelDelta;

  /// Set when a {lvl:cross} token links this room to the OTHER branch.
  final DungeonBranch? crossoverTo;
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

/// Cave-branch type die (E1/F1 headers): same door-kind ladder, tunnels for
/// corridors and caves for chambers.
(RoomType, DoorKind) _caveTypeDie(int d6) => switch (d6) {
      1 => (RoomType.tunnel, DoorKind.locked),
      2 => (RoomType.tunnel, DoorKind.door),
      3 => (RoomType.tunnel, DoorKind.open),
      4 => (RoomType.cave, DoorKind.open),
      5 => (RoomType.cave, DoorKind.door),
      _ => (RoomType.cave, DoorKind.locked),
    };

int _d66(Dice dice) => dice.dN(6) * 10 + dice.dN(6);

String _typeName(RoomType t) => switch (t) {
      RoomType.corridor => 'Corridor',
      RoomType.chamber => 'Chamber',
      RoomType.tunnel => 'Tunnel',
      RoomType.cave => 'Cave',
    };

/// Human labels for the dict-shaped build-element tables (H1/H2/H3/H6), which
/// carry nested sub-tables rather than a flat row list. These render as a
/// word rather than expanding their internal structure (H8 treasure is the
/// exception — it rolls for real).
const _dictRefLabels = <String, String>{
  'H1': 'a coffin',
  'H2': 'a statue',
  'H3': 'a secret room',
  'H6': 'a shrine',
};

/// Strips the zine's "..." continuation decorations off a B4 trigger/effect
/// fragment (e.g. "Pressure Plate ..." / "...Frostbolt") for clean display.
String _trimDots(String s) =>
    s.replaceAll(RegExp(r'^\s*\.+\s*|\s*\.+\s*$'), '');

/// Per-generateRoom {ref:XX} expander carrying the depth/treasure-bonus
/// context an H8 roll needs.
class _Expander {
  const _Expander(this.t, this.dice,
      {required this.depth, required this.bonus});
  final DungeonTables t;
  final Dice dice;
  final int depth;
  final int bonus;

  String _label(String id) => _dictRefLabels[id] ?? t.labelFallbacks[id] ?? id;

  /// Expand {ref:XX} tokens in [text]. Recurses into list-shaped tables up to
  /// [budget] levels; H8 rolls a real treasure line; B4 (a
  /// `{triggers,effects}` dict) renders one "trigger -> effect" trap (each
  /// side recursively expanded — effect rows can carry their own refs, e.g.
  /// "gas {ref:I8}"); H1/H2/H3/H6 render as `_dictRefLabels` words; any OTHER
  /// dict-of-lists table (I1 hides/leads, I2 source/creates, I7
  /// condition/liquid) rolls one row from each sub-list in key order, joined
  /// with " — "; an unknown ref becomes its fallback label; a self-referential
  /// ref stops at [budget].
  String expand(String text, {int budget = 4}) {
    final re = RegExp(r'\{ref:([A-Z]\d+)\}');
    return text.replaceAllMapped(re, (m) {
      final id = m.group(1)!;
      if (budget <= 0) return _label(id);
      if (id == 'H8') {
        return rollTreasure(
            (t.raw['H8'] as Map?)?.cast<String, dynamic>() ?? const {},
            depth: depth,
            bonus: bonus,
            dice: dice);
      }
      final table = t.raw[id];
      if (table is List) {
        final rolled = table[dice.dN(table.length) - 1];
        // Monster tables (G2..G7) hold {text,count,organized} rows — render
        // the name, never the raw map.
        final row = rolled is Map
            ? (rolled['text']?.toString() ?? '')
            : rolled.toString();
        return expand(row, budget: budget - 1);
      }
      if (table is Map &&
          table['triggers'] is List &&
          table['effects'] is List) {
        final trig = (table['triggers'] as List);
        final eff = (table['effects'] as List);
        final trigText = _trimDots(trig[dice.dN(trig.length) - 1].toString());
        final effText = _trimDots(eff[dice.dN(eff.length) - 1].toString());
        return expand('$trigText -> $effText', budget: budget - 1);
      }
      // The narrative build-element dicts stay words (a coffin/statue/...).
      if (_dictRefLabels.containsKey(id)) return _label(id);
      // Generic dict-of-lists (I1/I2/I7): roll one row per sub-list, in the
      // build script's key order, and join.
      if (table is Map &&
          table.isNotEmpty &&
          table.values.every((v) => v is List && v.isNotEmpty)) {
        final parts = <String>[
          for (final v in table.values)
            ((v as List)[dice.dN(v.length) - 1]).toString()
        ];
        return expand(parts.join(' — '), budget: budget - 1);
      }
      return _label(id);
    });
  }
}

/// De-tokenize a descriptive string for display: `{ref:XX}` -> `XX`. The A2
/// dungeon-type notes reference tables BY NAME ("stocking begins at G3") — they
/// must read as names, not roll an entry.
String stripRefTokens(String text) =>
    text.replaceAllMapped(RegExp(r'\{ref:([A-Z]\d+)\}'), (m) => m.group(1)!);

/// Monster rows for [depth]: tier = (depth+1)~/2 clamped 1..3, plus the type
/// effect's tier bump, re-clamped 1..3 -> G2/G3/G4. An empty tier table falls
/// back to the upper-level list.
List<MonsterRow> _tierMonsters(DungeonTables t, int depth, int bump) {
  final tier = (((depth + 1) ~/ 2).clamp(1, 3) + bump).clamp(1, 3);
  final rows = switch (tier) {
    1 => t.upperMonsters,
    2 => t.centralMonsters,
    _ => t.deepMonsters,
  };
  return rows.isEmpty ? t.upperMonsters : rows;
}

final _lvlRe = RegExp(r'\{lvl:(down|updown|chasm|cross)\}');

RoomResult generateRoom(DungeonGenContext ctx, Dice dice) {
  final t = ctx.tables;
  final isCave = ctx.branch == DungeonBranch.cave;
  final (type, entryKind) =
      isCave ? _caveTypeDie(dice.dN(6)) : _typeDie(dice.dN(6));
  final d66 = _d66(dice);
  final rangeMap = switch (type) {
    RoomType.corridor => t.corridorFamilies,
    RoomType.chamber => t.chamberFamilies,
    RoomType.tunnel => t.tunnelFamilies,
    RoomType.cave => t.caveFamilies,
  };
  final catalog = type == RoomType.corridor || type == RoomType.tunnel
      ? kCorridorShapes
      : kChamberShapes;
  final family = shapesForRoll(d66, rangeMap, catalog).first.family;
  final x =
      _Expander(t, dice, depth: ctx.depth, bonus: ctx.effect.treasureBonus);

  final lines = <String>['${_typeName(type)} ($family)'];
  var factions = ctx.factions;

  final stockTable = switch (type) {
    RoomType.corridor => t.b2,
    RoomType.chamber => t.c2,
    RoomType.tunnel => t.e2,
    RoomType.cave => t.f2,
  };
  final stockRoll = dice.dN(stockTable.length);
  // Row 6 is "Nothing (or Type effect)": a type with an on_stock_6 effect
  // (e.g. Crypt burial alcoves, A2-11's cave crossover) replaces it.
  final stock = stockRoll == 6 && ctx.effect.onStock6.isNotEmpty
      ? ctx.effect.onStock6
      : stockTable[stockRoll - 1];
  final wantsMonster = stock.contains('Monster');
  lines.add(x.expand(stock));

  if (wantsMonster) {
    final rows = _tierMonsters(t, ctx.depth, ctx.effect.tierBump);
    if (rows.isNotEmpty) {
      // A monsterDie effect (e.g. Ruins d10) restricts the roll to the
      // table's first N rows.
      final die = ctx.effect.monsterDie == 0
          ? rows.length
          : min(ctx.effect.monsterDie, rows.length);
      final mon = rows[dice.dN(die) - 1];
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
  }

  // Resolve {lvl:*} tokens carried by the expanded detail: the first
  // down/updown/chasm token sets the level change; a cross token links to the
  // other branch (independent of the level change). All tokens are stripped
  // from the display text.
  var detail = lines.join('\n');
  var levelDelta = 0;
  var levelSet = false;
  DungeonBranch? crossoverTo;
  for (final m in _lvlRe.allMatches(detail)) {
    final tok = m.group(1)!;
    if (tok == 'cross') {
      crossoverTo = isCave ? DungeonBranch.dungeon : DungeonBranch.cave;
      continue;
    }
    if (levelSet) continue;
    levelSet = true;
    levelDelta = switch (tok) {
      'down' => -1,
      'updown' => dice.dN(6) == 6 ? 1 : -1,
      _ => -dice.dN(4), // chasm
    };
  }
  detail =
      detail.replaceAll(RegExp(r'\s*\{lvl:(down|updown|chasm|cross)\}'), '');

  return RoomResult(
      type: type,
      entryDoorKind: entryKind,
      shapeFamily: family,
      detail: detail,
      factions: factions,
      levelDelta: levelDelta,
      crossoverTo: crossoverTo);
}
