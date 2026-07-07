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
 "B2":["Nothing","Nothing","Nothing","Nothing","Nothing","Nothing"],
 "B5":["Wooden","Wooden","Wooden","Wooden","Wooden","Wooden","Wooden","Wooden","Wooden","Wooden"],
 "C2":["Feature {ref:C3} + Monster","Nothing","Nothing","Feature {ref:C3}","Nothing","Nothing"],
 "G1":{"2":"Ambush","3":"a","4":"a","5":"a","6":"a","7":"Suspicious","8":"a","9":"a","10":"a","11":"a","12":"Friendly"},
 "G2":[{"text":"Goblins","count":"1","organized":true}],
 "faction_names":["Rotfangs"],
 "corridor_families":{"straight":[[11,66]]},
 "chamber_families":{"small":[[11,66]]},
 "label_fallbacks":{},
 "C3":["A fresco","A fresco"]}
''') as Map<String, dynamic>);

void main() {
  test('generateRoom returns a room type + entry door kind + detail text', () {
    final r = generateRoom(
        DungeonGenContext(
            level: 1,
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
              level: 1,
              effect: const A2Type(name: 'Ruins'),
              tables: _tables(),
              factions: const FactionRegistry()),
          Dice(Random(s)));
      if (r.factions.factions.isNotEmpty) {
        expect(r.factions.factions.single.monsterType, 'Goblins');
        expect(r.detail, contains('Rotfangs'));
        return;
      }
    }
    fail('no seed produced an organized-monster chamber');
  });

  test('ref expansion is depth-capped (no infinite loop on self-ref)', () {
    final t = DungeonTables.fromJson(jsonDecode('''
{"A1":${jsonEncode(List.filled(12, 'x'))},"A2":{"2":{"name":"x"},"3":{"name":"x"},"4":{"name":"x"},"5":{"name":"x"},"6":{"name":"x"},"7":{"name":"x"},"8":{"name":"x"},"9":{"name":"x"},"10":{"name":"x"},"11":{"name":"x"},"12":{"name":"x"}},
 "B2":["Nothing","Nothing","Nothing","Nothing","Nothing","Nothing"],
 "B5":["W","W","W","W","W","W","W","W","W","W"],
 "C2":["Feature {ref:C3}","x","x","x","x","x"],
 "G1":{"2":"a","3":"a","4":"a","5":"a","6":"a","7":"a","8":"a","9":"a","10":"a","11":"a","12":"a"},
 "G2":[{"text":"g","count":"1","organized":false}],
 "faction_names":["N"],"corridor_families":{"straight":[[11,66]]},
 "chamber_families":{"small":[[11,66]]},"label_fallbacks":{},
 "C3":["loop {ref:C3}"]}
''') as Map<String, dynamic>);
    final r = generateRoom(
        DungeonGenContext(
            level: 1,
            effect: const A2Type(name: 'x'),
            tables: t,
            factions: const FactionRegistry()),
        Dice(Random(0)));
    expect(r.detail, isNotEmpty);
  });

  test('B4 trap ref expands to "trigger -> effect"', () {
    final t = DungeonTables.fromJson(jsonDecode('''
{"A1":${jsonEncode(List.filled(12, 'x'))},"A2":{"2":{"name":"x"},"3":{"name":"x"},"4":{"name":"x"},"5":{"name":"x"},"6":{"name":"x"},"7":{"name":"x"},"8":{"name":"x"},"9":{"name":"x"},"10":{"name":"x"},"11":{"name":"x"},"12":{"name":"x"}},
 "B2":["Trap {ref:B4}","Trap {ref:B4}","Trap {ref:B4}","Trap {ref:B4}","Trap {ref:B4}","Trap {ref:B4}"],
 "B5":["W","W","W","W","W","W","W","W","W","W"],
 "C2":["Nothing","Nothing","Nothing","Nothing","Nothing","Nothing"],
 "G1":{"2":"a","3":"a","4":"a","5":"a","6":"a","7":"a","8":"a","9":"a","10":"a","11":"a","12":"a"},
 "G2":[{"text":"g","count":"1","organized":false}],
 "faction_names":["N"],"corridor_families":{"straight":[[11,66]]},
 "chamber_families":{"small":[[11,66]]},"label_fallbacks":{},
 "B4":{"triggers":["Tripwire"],"effects":["Sawing Blades"]}}
''') as Map<String, dynamic>);
    // find a corridor result (type die 1-3). Loop seeds until we get a corridor.
    for (var s = 0; s < 50; s++) {
      final r = generateRoom(
          DungeonGenContext(
              level: 1,
              effect: const A2Type(name: 'x'),
              tables: t,
              factions: const FactionRegistry()),
          Dice(Random(s)));
      if (r.type == RoomType.corridor) {
        expect(r.detail, contains('Tripwire -> Sawing Blades'));
        return;
      }
    }
    fail('no corridor seed');
  });
}
