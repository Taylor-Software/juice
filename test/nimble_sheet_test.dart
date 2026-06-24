import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('NimbleSheet round-trips + applies defaults/clamps', () {
    const s = NimbleSheet(
      stats: {'str': 2, 'dex': 1, 'int': 0, 'wis': -1},
      saveAdv: {'dex': 1},
      className: 'Hunter',
      ancestry: 'Elf',
      level: 3,
      hitDieSize: 8,
      maxHp: 20,
      currentHp: 14,
      wounds: 2,
      maxWounds: 6,
      speed: 6,
      gearSlotsUsed: 5,
      talents: 'Keen eye',
      notes: 'n',
    );
    final back = NimbleSheet.maybeFromJson(s.toJson())!;
    expect(back.className, 'Hunter');
    expect(back.stats['str'], 2);
    expect(back.saveAdv['dex'], 1);
    expect(back.currentHp, 14);
    expect(back.wounds, 2);
    expect(back.slotCap, 12); // 10 + str(2)
  });

  test('NimbleSheet tolerates junk + unknown class', () {
    final s = NimbleSheet.maybeFromJson({'className': 'Bogus', 'level': 99})!;
    expect(s.className, 'The Cheat'); // unknown -> default
    expect(s.level, 10); // clamped
    expect(NimbleSheet.maybeFromJson('nope'), isNull);
  });

  test('Character round-trips nimble + withHpDelta adjusts its pool', () {
    const c = Character(
        id: 'c1', name: 'Ari', nimble: NimbleSheet(currentHp: 10, maxHp: 12));
    final back = Character.fromJson(c.toJson());
    expect(back.nimble, isNotNull);
    final hurt = c.withHpDelta(-4);
    expect(hurt.nimble!.currentHp, 6);
    final overheal = c.withHpDelta(99);
    expect(overheal.nimble!.currentHp, 12); // clamped to maxHp
  });
}
