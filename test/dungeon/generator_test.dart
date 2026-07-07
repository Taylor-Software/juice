import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/dungeon/footprint.dart';
import 'package:juice_oracle/engine/dungeon/faction.dart';
import 'package:juice_oracle/engine/dungeon/generator.dart';
import 'package:juice_oracle/engine/dungeon/tables.dart';

DungeonTables _tables() => DungeonTables.fromJson(jsonDecode('''
{"A1":${jsonEncode(List.filled(12, 'Somewhere'))},
 "A2":{"2":{"name":"Vault","stock_double":true},"3":{"name":"X"},"4":{"name":"X"},
 "5":{"name":"X"},"6":{"name":"X"},"7":{"name":"Ruins"},"8":{"name":"X"},
 "9":{"name":"X"},"10":{"name":"Cursed","tier_bump":1},"11":{"name":"X"},"12":{"name":"X"}},
 "B2":["Nothing","Nothing","Nothing","Nothing","Nothing","Nothing (or Type effect)"],
 "B5":["Wooden","Wooden","Wooden","Wooden","Wooden","Wooden","Wooden","Wooden","Wooden","Wooden"],
 "C2":["Feature {ref:C3} + Monster","Nothing","Nothing","Feature {ref:C3}","Nothing","Nothing (or Type effect)"],
 "G1":{"2":"Ambush","3":"a","4":"a","5":"a","6":"a","7":"Suspicious","8":"a","9":"a","10":"a","11":"a","12":"Friendly"},
 "G2":[{"text":"Goblins","count":"1","organized":true}],
 "faction_names":["Rotfangs"],
 "corridor_families":{"straight":[[11,66]]},
 "chamber_families":{"small":[[11,66]]},
 "label_fallbacks":{},
 "C3":["A fresco","A fresco"],
 "D1":${jsonEncode(List.filled(12, 'Cavemouth'))},
 "D2":{"2":{"name":"C"},"3":{"name":"C"},"4":{"name":"C"},"5":{"name":"C"},
 "6":{"name":"C"},"7":{"name":"C"},"8":{"name":"C"},"9":{"name":"C"},
 "10":{"name":"C"},"11":{"name":"C"},"12":{"name":"C"}},
 "E2":["Nothing","Nothing","Nothing","Nothing","Nothing","Nothing"],
 "F2":["Feature {ref:F3} + Monster","Nothing","Nothing","Nothing","Nothing","Nothing"],
 "E5":["Granite","Granite","Granite","Granite","Granite","Granite","Granite","Granite","Granite","Granite"],
 "F3":["Stalagmites","Stalagmites"],
 "tunnel_families":{"straight":[[11,66]]},
 "cave_families":{"small":[[11,66]]},
 "G3":[{"text":"Wight","count":"D8","organized":false}],
 "G4":[{"text":"Vampire","count":"D4","organized":false}]}
''') as Map<String, dynamic>);

/// Base fixture whose B2 + C2 rows are ALL [stock] (so every seed hits it),
/// merged with [extra] tables (e.g. a C3 carrying a {lvl:*} token or a full
/// H8 treasure dict).
DungeonTables _stockTables(String stock, Map<String, dynamic> extra) {
  final rows = jsonEncode(List.filled(6, stock));
  final j = jsonDecode('''
{"A1":${jsonEncode(List.filled(12, 'x'))},
 "A2":{"2":{"name":"x"},"3":{"name":"x"},"4":{"name":"x"},"5":{"name":"x"},"6":{"name":"x"},"7":{"name":"x"},"8":{"name":"x"},"9":{"name":"x"},"10":{"name":"x"},"11":{"name":"x"},"12":{"name":"x"}},
 "B2":$rows,
 "B5":["W","W","W","W","W","W","W","W","W","W"],
 "C2":$rows,
 "G1":{"2":"a","3":"a","4":"a","5":"a","6":"a","7":"a","8":"a","9":"a","10":"a","11":"a","12":"a"},
 "G2":[{"text":"g","count":"1","organized":false}],
 "faction_names":["N"],"corridor_families":{"straight":[[11,66]]},
 "chamber_families":{"small":[[11,66]]},"label_fallbacks":{}}
''') as Map<String, dynamic>;
  j.addAll(extra);
  return DungeonTables.fromJson(j);
}

DungeonGenContext _ctx(DungeonTables t,
        {DungeonBranch branch = DungeonBranch.dungeon,
        int depth = 1,
        A2Type effect = const A2Type(name: 'x')}) =>
    DungeonGenContext(
        branch: branch,
        depth: depth,
        roomId: 'roomX',
        effect: effect,
        tables: t,
        factions: const FactionRegistry());

void main() {
  test('generateRoom returns a room type + entry door kind + detail text', () {
    final r = generateRoom(
        DungeonGenContext(
            branch: DungeonBranch.dungeon,
            depth: 1,
            roomId: 'roomX',
            effect: const A2Type(name: 'Ruins'),
            tables: _tables(),
            factions: const FactionRegistry()),
        Dice(Random(3)));
    expect(r.type, anyOf(RoomType.corridor, RoomType.chamber));
    expect(r.entryDoorKind, isA<DoorKind>());
    expect(r.detail, isNotEmpty);
  });

  test('organized monster in a chamber extends the faction registry', () {
    for (var s = 0; s < 50; s++) {
      final r = generateRoom(
          DungeonGenContext(
              branch: DungeonBranch.dungeon,
              depth: 1,
              roomId: 'roomX',
              effect: const A2Type(name: 'Ruins'),
              tables: _tables(),
              factions: const FactionRegistry()),
          Dice(Random(s)));
      if (r.factions.factions.isNotEmpty) {
        expect(r.factions.factions.single.monsterType, 'Goblins');
        expect(r.detail, contains('Rotfangs'));
        // the minted faction carries the caller-supplied room id (no
        // 'pending' placeholder to reconcile)
        expect(r.factions.factions.single.roomIds, ['roomX']);
        return;
      }
    }
    fail('no seed produced an organized-monster chamber');
  });

  test('a ref to a monster table renders the row text, not the raw map', () {
    final t = _stockTables('Carcasses of {ref:G2}', {
      'G2': [
        {'text': 'Giant Rat', 'count': '2D6', 'organized': false}
      ]
    });
    final r = generateRoom(_ctx(t), Dice(Random(0)));
    expect(r.detail, contains('Carcasses of Giant Rat'));
    expect(r.detail, isNot(contains('organized')));
  });

  test('B4 sides are dot-trimmed and recursively expanded', () {
    final t = _stockTables('Trap {ref:B4}', {
      'label_fallbacks': {'I8': 'gas'},
      'B4': {
        'triggers': ['Pressure Plate ...'],
        'effects': ['... {ref:I8}']
      }
    });
    final r = generateRoom(_ctx(t), Dice(Random(0)));
    expect(r.detail, contains('Pressure Plate -> gas'));
    expect(r.detail, isNot(contains('...')));
    expect(r.detail, isNot(contains('{ref:')));
  });

  test('stripRefTokens renders table names for descriptive notes', () {
    expect(
        stripRefTokens(
            'Monster stocking begins at {ref:G3} instead of {ref:G2}.'),
        'Monster stocking begins at G3 instead of G2.');
  });

  test('an unknown ref renders its id as a plain label (never throws)', () {
    final t = _stockTables('Weird {ref:Z9}', const {});
    final r = generateRoom(_ctx(t), Dice(Random(0)));
    // Z9 is not a table, not a dict label, not a fallback -> raw id shown.
    expect(r.detail, contains('Weird Z9'));
  });

  test('ref expansion is depth-capped (no infinite loop on self-ref)', () {
    final t = _stockTables('Feature {ref:C3}', {
      'C3': ['loop {ref:C3}']
    });
    final r = generateRoom(_ctx(t), Dice(Random(0)));
    expect(r.detail, isNotEmpty);
  });

  test('B4 trap ref expands to "trigger -> effect"', () {
    final t = _stockTables('Trap {ref:B4}', {
      'B4': {
        'triggers': ['Tripwire'],
        'effects': ['Sawing Blades']
      }
    });
    // find a corridor result (type die 1-3). Loop seeds until we get a corridor.
    for (var s = 0; s < 50; s++) {
      final r = generateRoom(_ctx(t), Dice(Random(s)));
      if (r.type == RoomType.corridor) {
        expect(r.detail, contains('Tripwire -> Sawing Blades'));
        return;
      }
    }
    fail('no corridor seed');
  });

  test('cave branch produces only tunnels and caves', () {
    final t = _tables();
    for (var s = 0; s < 30; s++) {
      final r =
          generateRoom(_ctx(t, branch: DungeonBranch.cave), Dice(Random(s)));
      expect(r.type, anyOf(RoomType.tunnel, RoomType.cave));
      expect(r.detail, isNotEmpty);
    }
  });

  test('depth 3 stocks tier-2 monsters (G3)', () {
    final t = _tables();
    for (var s = 0; s < 200; s++) {
      final r = generateRoom(_ctx(t, depth: 3), Dice(Random(s)));
      if (r.detail.contains('Monsters:')) {
        expect(r.detail, contains('Wight'));
        return;
      }
    }
    fail('no seed produced a monster stocking');
  });

  test('depth 5 + tier bump caps at tier 3 (G4)', () {
    final t = _tables();
    for (var s = 0; s < 200; s++) {
      final r = generateRoom(
          _ctx(t, depth: 5, effect: const A2Type(name: 'Cursed', tierBump: 1)),
          Dice(Random(s)));
      if (r.detail.contains('Monsters:')) {
        expect(r.detail, contains('Vampire'));
        return;
      }
    }
    fail('no seed produced a monster stocking');
  });

  test('{lvl:updown} yields levelDelta +/-1 and strips the token', () {
    final t = _stockTables('Feature {ref:C3}', {
      'C3': ['Stairs {lvl:updown}']
    });
    final r = generateRoom(_ctx(t), Dice(Random(0)));
    expect(r.levelDelta, anyOf(1, -1));
    expect(r.detail, contains('Stairs'));
    expect(r.detail, isNot(contains('{lvl:')));
  });

  test('{lvl:chasm} yields levelDelta in -4..-1', () {
    final t = _stockTables('Feature {ref:C3}', {
      'C3': ['Chasm {lvl:chasm}']
    });
    final r = generateRoom(_ctx(t), Dice(Random(0)));
    expect(r.levelDelta, inInclusiveRange(-4, -1));
    expect(r.detail, isNot(contains('{lvl:')));
  });

  test('{lvl:cross} on the dungeon branch crosses over to caves', () {
    final t = _stockTables('Feature {ref:C3}', {
      'C3': ['Collapsed wall {lvl:cross}']
    });
    final r = generateRoom(_ctx(t), Dice(Random(0)));
    expect(r.crossoverTo, DungeonBranch.cave);
    expect(r.levelDelta, 0);
    expect(r.detail, isNot(contains('{lvl:')));
  });

  test('on_stock_6 replaces the "Nothing (or Type effect)" row', () {
    final t = _tables();
    const effect = A2Type(name: 'x', onStock6: 'D4 burial alcoves {ref:H1}');
    for (var s = 0; s < 200; s++) {
      final r = generateRoom(_ctx(t, effect: effect), Dice(Random(s)));
      if (r.detail.contains('burial alcoves')) {
        expect(r.detail, contains('burial alcoves a coffin'));
        expect(r.detail, isNot(contains('Nothing (or Type effect)')));
        return;
      }
    }
    fail('no seed rolled a 6 on the stocking table');
  });

  test('{ref:H8} rolls real treasure (dice resolved to an amount)', () {
    const h8 = {
      'form_d4': ['Coins', 'Coins', 'D6 items', 'D4 gems'],
      'd10_plus_level': [
        'D6 SP',
        '2D6 SP',
        'D6 GP',
        'D6*5 GP',
        'D6*10 GP',
        '2D6*10 GP',
        'D6*25 GP',
        '2D6*25 GP',
        'D6*50 GP',
        'Artifact +1 & 2D6*50 GP',
        'D6*100 GP',
        'Artifact +1 & D6*100 GP',
        '2D6*100 GP',
        'Artifact +2 & D6*250 GP',
        'D6*250 GP',
        'Artifact +2 & D6*500 GP',
        '2D6*1000 GP',
        'Artifact +3 & D6*5000 GP',
      ],
    };
    final t = _stockTables('Treasure {ref:H8}', {'H8': h8});
    for (var s = 0; s < 50; s++) {
      final r = generateRoom(_ctx(t), Dice(Random(s)));
      if (RegExp(r'Treasure: \d+ (GP|SP)').hasMatch(r.detail)) return;
    }
    fail('no seed produced a numeric treasure roll');
  });

  test('branchOfRoomType maps tunnel/cave to the cave branch', () {
    expect(branchOfRoomType('tunnel'), DungeonBranch.cave);
    expect(branchOfRoomType('cave'), DungeonBranch.cave);
    expect(branchOfRoomType('corridor'), DungeonBranch.dungeon);
    expect(branchOfRoomType('chamber'), DungeonBranch.dungeon);
    expect(branchOfRoomType(null), DungeonBranch.dungeon);
  });
}
