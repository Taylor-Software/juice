import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('KnaveSheet round-trips toJson/maybeFromJson', () {
    const s = KnaveSheet(
      career: 'Herbalist',
      stats: {'str': 4, 'dex': 3, 'con': 2, 'int': 5, 'wis': 1, 'cha': 3},
      level: 2,
      maxHp: 8,
      currentHp: 5,
      wounds: 1,
      ac: 13,
      coins: '50 gp',
      notes: 'n',
    );
    final back = KnaveSheet.maybeFromJson(s.toJson())!;
    expect(back.career, 'Herbalist');
    expect(back.stats['int'], 5);
    expect(back.currentHp, 5);
    expect(back.wounds, 1);
    expect(back.ac, 13);
    expect(back.coins, '50 gp');
    expect(KnaveSheet.maybeFromJson('nope'), isNull);
  });

  test('KnaveSheet copyWith clamps stats, hp, wounds, ac, level', () {
    const s = KnaveSheet(
      stats: {'str': 3, 'dex': 3, 'con': 3, 'int': 3, 'wis': 3, 'cha': 3},
      maxHp: 6,
      currentHp: 3,
      wounds: 0,
      ac: 11,
    );
    expect(s.copyWith(stats: {...s.stats, 'str': 15}).stats['str'], 10);
    expect(s.copyWith(stats: {...s.stats, 'str': -1}).stats['str'], 0);
    expect(s.copyWith(currentHp: 99).currentHp, 6);
    expect(s.copyWith(currentHp: -1).currentHp, 0);
    expect(s.copyWith(wounds: -1).wounds, 0);
    expect(s.copyWith(ac: -1).ac, 0);
    expect(s.copyWith(level: 0).level, 1);
    expect(s.copyWith(level: 99).level, 20);
  });

  test('KnaveSheet inventorySlots = 10 + con', () {
    const s = KnaveSheet(
      stats: {'str': 0, 'dex': 0, 'con': 3, 'int': 0, 'wis': 0, 'cha': 0},
    );
    expect(s.inventorySlots, 13);
    const s2 = KnaveSheet(
      stats: {'str': 0, 'dex': 0, 'con': 0, 'int': 0, 'wis': 0, 'cha': 0},
    );
    expect(s2.inventorySlots, 10);
  });

  test('KnaveSheet kKnaveStats has 6 entries', () {
    expect(kKnaveStats.length, 6);
    expect(kKnaveStats.contains('str'), isTrue);
    expect(kKnaveStats.contains('cha'), isTrue);
  });

  test('Character round-trips knave + withHpDelta adjusts currentHp', () {
    const c = Character(
      id: 'c1',
      name: 'Quill',
      knave: KnaveSheet(maxHp: 6, currentHp: 6),
    );
    final back = Character.fromJson(c.toJson());
    expect(back.knave, isNotNull);
    expect(c.withHpDelta(-3).knave!.currentHp, 3);
    expect(c.withHpDelta(99).knave!.currentHp, 6);
    expect(c.withHpDelta(-99).knave!.currentHp, 0);
  });
}
