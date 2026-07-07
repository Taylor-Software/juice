import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/dungeon/faction.dart';

const _names = ['Rotfangs', 'Ashclaw Pack', 'Bonepickers'];

void main() {
  test('first organized monster of a type mints a new faction', () {
    final (reg, fac) = assignFaction(
        const FactionRegistry(), 'Goblins', 'room1', _names, Dice(Random(1)));
    expect(reg.factions, hasLength(1));
    expect(fac!.monsterType, 'Goblins');
    expect(_names, contains(fac.name));
    expect(fac.roomIds, ['room1']);
  });

  test('same type: 5/6 reuses, else mints new (deterministic under seed)', () {
    var reg = const FactionRegistry();
    (reg, _) = assignFaction(reg, 'Goblins', 'r1', _names, Dice(Random(1)));
    var reuse = 0, mint = 0;
    final d = Dice(Random(7));
    for (var i = 0; i < 60; i++) {
      final before = reg.factions.length;
      (reg, _) = assignFaction(reg, 'Goblins', 'r$i', _names, d);
      if (reg.factions.length == before)
        reuse++;
      else
        mint++;
    }
    expect(reuse, greaterThan(mint));
  });

  test('registry round-trips through JSON', () {
    var reg = const FactionRegistry();
    (reg, _) = assignFaction(reg, 'Goblins', 'r1', _names, Dice(Random(1)));
    (reg, _) = assignFaction(reg, 'Orcs', 'r2', _names, Dice(Random(1)));
    final back = FactionRegistry.fromJson(reg.toJson());
    expect(
        back.factions.map((f) => f.monsterType).toSet(), {'Goblins', 'Orcs'});
    expect(back.factions.first.roomIds, isNotEmpty);
  });

  test('name pool exhaustion falls back to a unique numbered name', () {
    var reg = const FactionRegistry();
    // force many NEW mints of the same-ish types with a 1-name pool
    (reg, _) = assignFaction(reg, 'A', 'r', const ['Only'], Dice(Random(1)));
    (reg, _) = assignFaction(reg, 'B', 'r', const ['Only'], Dice(Random(1)));
    final names = reg.factions.map((f) => f.name).toSet();
    expect(names.length, 2); // unique despite a 1-name pool
  });
}
