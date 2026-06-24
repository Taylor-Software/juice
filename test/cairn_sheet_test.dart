import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/shared/home_shell.dart';

void main() {
  test('CairnSheet round-trips toJson/maybeFromJson', () {
    const s = CairnSheet(
      background: 'Hunter',
      str: 14,
      dex: 12,
      wil: 10,
      maxHp: 5,
      currentHp: 3,
      armor: 2,
      deprived: true,
      fatigue: 2,
      coins: '12 gp',
      notes: 'n',
    );
    final back = CairnSheet.maybeFromJson(s.toJson())!;
    expect(back.background, 'Hunter');
    expect(back.str, 14);
    expect(back.currentHp, 3);
    expect(back.armor, 2);
    expect(back.deprived, true);
    expect(back.fatigue, 2);
    expect(back.coins, '12 gp');
    expect(CairnSheet.maybeFromJson('nope'), isNull);
  });

  test('CairnSheet copyWith clamps stats, hp, armor, fatigue', () {
    const s = CairnSheet(
      str: 10,
      dex: 10,
      wil: 10,
      maxHp: 6,
      currentHp: 3,
      armor: 1,
      fatigue: 0,
    );
    expect(s.copyWith(str: 20).str, 18);
    expect(s.copyWith(str: 1).str, 3);
    expect(s.copyWith(currentHp: 99).currentHp, 6);
    expect(s.copyWith(currentHp: -1).currentHp, 0);
    expect(s.copyWith(armor: 5).armor, 3);
    expect(s.copyWith(armor: -1).armor, 0);
    expect(s.copyWith(fatigue: 99).fatigue, 10);
    expect(s.copyWith(fatigue: -1).fatigue, 0);
  });

  test('CairnSheet unknown background falls back to first', () {
    final s = CairnSheet.maybeFromJson({'background': 'Wizard'})!;
    expect(s.background, kCairnBackgrounds.first);
  });

  test('CairnSheet kCairnBackgrounds has 20 entries', () {
    expect(kCairnBackgrounds.length, 20);
    expect(kCairnBackgrounds.contains('Hunter'), isTrue);
    expect(kCairnBackgrounds.contains('Herbalist'), isTrue);
  });

  test('Character round-trips cairn + withHpDelta adjusts currentHp', () {
    const c = Character(
      id: 'c1',
      name: 'Wren',
      cairn: CairnSheet(maxHp: 5, currentHp: 5),
    );
    final back = Character.fromJson(c.toJson());
    expect(back.cairn, isNotNull);
    expect(c.withHpDelta(-2).cairn!.currentHp, 3);
    expect(c.withHpDelta(99).cairn!.currentHp, 5);
    expect(c.withHpDelta(-99).cairn!.currentHp, 0);
  });

  test('kSystemBlurbs cairn contains CC BY-SA attribution', () {
    final blurb = kSystemBlurbs['cairn'] ?? '';
    expect(blurb.toLowerCase(), contains('yochai gal'));
    expect(blurb.toLowerCase(), contains('cc by-sa'));
  });
}
