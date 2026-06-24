import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('ArgosaSheet round-trips toJson/maybeFromJson', () {
    const s = ArgosaSheet(
      className: 'Ranger',
      level: 3,
      stats: {
        'str': 12,
        'dex': 14,
        'con': 10,
        'int': 8,
        'per': 11,
        'wil': 9,
        'cha': 13
      },
      maxHp: 14,
      currentHp: 9,
      luck: 8,
      rescues: 2,
      skills: 'Tracking',
      notes: 'n',
    );
    final back = ArgosaSheet.maybeFromJson(s.toJson())!;
    expect(back.className, 'Ranger');
    expect(back.level, 3);
    expect(back.stats['dex'], 14);
    expect(back.currentHp, 9);
    expect(back.luck, 8);
    expect(back.rescues, 2);
    expect(ArgosaSheet.maybeFromJson('nope'), isNull);
  });

  test('ArgosaSheet copyWith clamps level, stats, hp, luck', () {
    const s = ArgosaSheet(
      level: 5,
      maxHp: 20,
      currentHp: 10,
      luck: 6,
      stats: {
        'str': 10,
        'dex': 10,
        'con': 10,
        'int': 10,
        'per': 10,
        'wil': 10,
        'cha': 10
      },
    );
    expect(s.copyWith(level: 0).level, 1);
    expect(s.copyWith(level: 99).level, 9);
    expect(s.copyWith(stats: {...s.stats, 'str': 20}).stats['str'], 18);
    expect(s.copyWith(stats: {...s.stats, 'str': 1}).stats['str'], 3);
    expect(s.copyWith(currentHp: 99).currentHp, 20);
    expect(s.copyWith(currentHp: -1).currentHp, 0);
    expect(s.copyWith(luck: -1).luck, 0);
    expect(s.copyWith(luck: 100).luck, 99);
  });

  test('ArgosaSheet unknown class falls back to first class', () {
    final s = ArgosaSheet.maybeFromJson({'className': 'Wizard'})!;
    expect(s.className, kArgosaClasses.first);
  });

  test('ArgosaSheet.resetLuck = 10 + ceil(level/2)', () {
    expect(const ArgosaSheet(level: 1).resetLuck, 11);
    expect(const ArgosaSheet(level: 2).resetLuck, 11);
    expect(const ArgosaSheet(level: 3).resetLuck, 12);
    expect(const ArgosaSheet(level: 9).resetLuck, 15);
  });

  test('Character round-trips argosa + withHpDelta adjusts currentHp', () {
    const c = Character(
      id: 'c1',
      name: 'Korrin',
      argosa: ArgosaSheet(maxHp: 14, currentHp: 14),
    );
    final back = Character.fromJson(c.toJson());
    expect(back.argosa, isNotNull);
    expect(c.withHpDelta(-4).argosa!.currentHp, 10);
    expect(c.withHpDelta(99).argosa!.currentHp, 14);
    expect(c.withHpDelta(-99).argosa!.currentHp, 0);
  });
}
