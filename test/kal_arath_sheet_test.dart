import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('KalArathSheet round-trips toJson/maybeFromJson', () {
    const s = KalArathSheet(
      archetype: 'Mystic',
      level: 2,
      xp: '3',
      stats: {'str': 1, 'tou': 0, 'agi': 2, 'int': 1, 'pre': -1},
      maxHp: 7,
      currentHp: 4,
      fatePoints: 2,
      damageReduction: 1,
      pact: 'Shadow',
      doom: 'no metal',
      skills: 'sneak',
      notes: 'n',
    );
    final back = KalArathSheet.maybeFromJson(s.toJson())!;
    expect(back.archetype, 'Mystic');
    expect(back.stats['agi'], 2);
    expect(back.stats['pre'], -1);
    expect(back.currentHp, 4);
    expect(back.fatePoints, 2);
    expect(back.pact, 'Shadow');
    expect(KalArathSheet.maybeFromJson('nope'), isNull);
  });

  test('KalArathSheet copyWith clamps stats -1..5, hp, level, fate, dr', () {
    const s = KalArathSheet(
      stats: {'str': 0, 'tou': 0, 'agi': 0, 'int': 0, 'pre': 0},
      maxHp: 6,
      currentHp: 3,
    );
    expect(s.copyWith(stats: {...s.stats, 'str': 9}).stats['str'], 5);
    expect(s.copyWith(stats: {...s.stats, 'str': -5}).stats['str'], -1);
    expect(s.copyWith(currentHp: 99).currentHp, 6);
    expect(s.copyWith(currentHp: -1).currentHp, 0);
    expect(s.copyWith(level: 0).level, 1);
    expect(s.copyWith(level: 99).level, 9);
    expect(s.copyWith(fatePoints: -1).fatePoints, 0);
    expect(s.copyWith(damageReduction: -1).damageReduction, 0);
  });

  test('Kal-Arath constants', () {
    expect(kKalArathStats, ['str', 'tou', 'agi', 'int', 'pre']);
    expect(kKalArathArchetypes.length, 4);
    expect(kKalArathPacts.length, 6);
    expect(kKalArathStatLabels['tou'], 'TOU');
  });

  test('Character round-trips kalArath + withHpDelta', () {
    const c = Character(
      id: 'c1',
      name: 'Vorr',
      kalArath: KalArathSheet(maxHp: 8, currentHp: 8),
    );
    final back = Character.fromJson(c.toJson());
    expect(back.kalArath, isNotNull);
    expect(c.withHpDelta(-3).kalArath!.currentHp, 5);
    expect(c.withHpDelta(99).kalArath!.currentHp, 8);
    expect(c.withHpDelta(-99).kalArath!.currentHp, 0);
  });
}
