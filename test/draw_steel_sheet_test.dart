import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('DrawSteelSheet round-trips toJson/maybeFromJson', () {
    const s = DrawSteelSheet(
      className: 'Fury',
      ancestry: 'Human',
      level: 3,
      characteristics: {
        'might': 2,
        'agility': 1,
        'reason': 0,
        'intuition': -1,
        'presence': 1
      },
      maxStamina: 30,
      currentStamina: 22,
      recoveries: 3,
      maxRecoveries: 8,
      stability: 1,
      heroicResource: 2,
      skills: 'Climb',
      notes: 'n',
    );
    final back = DrawSteelSheet.maybeFromJson(s.toJson())!;
    expect(back.className, 'Fury');
    expect(back.characteristics['might'], 2);
    expect(back.currentStamina, 22);
    expect(back.stability, 1);
    expect(back.heroicResource, 2);
    expect(back.skills, 'Climb');
  });

  test('DrawSteelSheet copyWith clamps level and stamina', () {
    const s = DrawSteelSheet(maxStamina: 20, currentStamina: 10);
    final over = s.copyWith(level: 99, currentStamina: 999);
    expect(over.level, 10);
    expect(over.currentStamina, 20); // clamped to maxStamina
    final under = s.copyWith(level: 0, currentStamina: -5);
    expect(under.level, 1);
    expect(under.currentStamina, 0);
  });

  test('DrawSteelSheet unknown class falls back to first class', () {
    final s = DrawSteelSheet.maybeFromJson({'className': 'Bogus'})!;
    expect(s.className, kDrawSteelClasses.first);
    expect(DrawSteelSheet.maybeFromJson('nope'), isNull);
  });

  test('DrawSteelSheet.resourceLabel returns known resource or "Resource"', () {
    for (final cls in kDrawSteelClasses) {
      expect(DrawSteelSheet(className: cls).resourceLabel, isNotEmpty);
    }
    expect(
      const DrawSteelSheet(className: '_bogus').resourceLabel,
      'Resource',
    );
  });

  test('Character round-trips drawSteel + withHpDelta adjusts stamina', () {
    const c = Character(
        id: 'c1',
        name: 'Kael',
        drawSteel: DrawSteelSheet(currentStamina: 20, maxStamina: 30));
    final back = Character.fromJson(c.toJson());
    expect(back.drawSteel, isNotNull);
    expect(back.drawSteel!.currentStamina, 20);

    final hurt = c.withHpDelta(-5);
    expect(hurt.drawSteel!.currentStamina, 15);

    final overheal = c.withHpDelta(99);
    expect(overheal.drawSteel!.currentStamina, 30);

    final overkill = c.withHpDelta(-999);
    expect(overkill.drawSteel!.currentStamina, 0);
  });
}
