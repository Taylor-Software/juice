import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/shared/home_shell.dart';

void main() {
  test('OseSheet round-trips toJson/maybeFromJson', () {
    const s = OseSheet(
      className: 'Fighter',
      level: 3,
      xp: '4000',
      alignment: 'Neutral',
      stats: {'str': 15, 'int': 9, 'wis': 8, 'dex': 12, 'con': 14, 'cha': 10},
      saves: {
        'death': 12,
        'wands': 13,
        'paralysis': 14,
        'breath': 15,
        'spells': 16
      },
      maxHp: 18,
      currentHp: 12,
      ac: 5,
      thac0: 17,
      coins: '120 gp',
      notes: 'n',
    );
    final back = OseSheet.maybeFromJson(s.toJson())!;
    expect(back.className, 'Fighter');
    expect(back.stats['str'], 15);
    expect(back.saves['death'], 12);
    expect(back.currentHp, 12);
    expect(back.ac, 5);
    expect(back.thac0, 17);
    expect(OseSheet.maybeFromJson('nope'), isNull);
  });

  test('OseSheet copyWith clamps stats, hp, saves, level', () {
    const s = OseSheet(
      stats: {'str': 10, 'int': 10, 'wis': 10, 'dex': 10, 'con': 10, 'cha': 10},
      saves: {
        'death': 12,
        'wands': 13,
        'paralysis': 14,
        'breath': 15,
        'spells': 16
      },
      maxHp: 8,
      currentHp: 6,
    );
    expect(s.copyWith(stats: {...s.stats, 'str': 20}).stats['str'], 18);
    expect(s.copyWith(stats: {...s.stats, 'str': 0}).stats['str'], 3);
    expect(s.copyWith(currentHp: 99).currentHp, 8);
    expect(s.copyWith(currentHp: -1).currentHp, 0);
    expect(s.copyWith(saves: {...s.saves, 'death': 25}).saves['death'], 20);
    expect(s.copyWith(saves: {...s.saves, 'death': 0}).saves['death'], 2);
    expect(s.copyWith(level: 0).level, 1);
    expect(s.copyWith(level: 25).level, 20);
  });

  test('OseSheet constants are correct', () {
    expect(kOseStats.length, 6);
    expect(kOseSaveKeys.length, 5);
    expect(kOseClasses.length, 7);
    expect(kOseAlignments.length, 3);
    expect(kOseSaveLabels.containsKey('death'), isTrue);
    expect(kOseSaveLabels.containsKey('spells'), isTrue);
  });

  test('OseSheet tolerant parse — unknown class stored as-is', () {
    final s = OseSheet.maybeFromJson({'className': 'Paladin'});
    expect(s, isNotNull);
    expect(s!.className, 'Paladin');
  });

  test('Character round-trips ose + withHpDelta', () {
    const c = Character(
      id: 'c1',
      name: 'Thorin',
      ose: OseSheet(maxHp: 10, currentHp: 10),
    );
    final back = Character.fromJson(c.toJson());
    expect(back.ose, isNotNull);
    expect(c.withHpDelta(-4).ose!.currentHp, 6);
    expect(c.withHpDelta(99).ose!.currentHp, 10);
    expect(c.withHpDelta(-99).ose!.currentHp, 0);
  });

  test('kSystemBlurbs ose contains non-affiliation note', () {
    final blurb = kSystemBlurbs['ose'] ?? '';
    expect(blurb.toLowerCase(), contains('necrotic gnome'));
    expect(blurb.toLowerCase(), contains('not affiliated'));
  });
}
