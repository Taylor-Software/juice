import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/verdant.dart';
import 'package:juice_oracle/state/verdant.dart';

void main() {
  test('defaults', () {
    const j = VerdantJourney();
    expect(j.partySize, 1);
    expect(j.independentFollowers, 0);
    expect(j.day, 1);
    expect(j.watch, 1);
    expect(j.step, 1);
    expect(j.pace, Pace.normal);
    expect(j.transport, isNull);
    expect(j.rushUsedToday, false);
  });

  test('JSON round-trip preserves all fields', () {
    const j = VerdantJourney(
      partySize: 3,
      independentFollowers: 2,
      day: 4,
      watch: 3,
      step: 5,
      safetyLevel: -1,
      pace: Pace.fast,
      transport: 'mount',
      rushUsedToday: true,
      travelingThisRound: true,
      roundNote: 'note',
    );
    final back = VerdantJourney.fromJson(j.toJson());
    expect(back.partySize, 3);
    expect(back.independentFollowers, 2);
    expect(back.day, 4);
    expect(back.watch, 3);
    expect(back.step, 5);
    expect(back.safetyLevel, -1);
    expect(back.pace, Pace.fast);
    expect(back.transport, 'mount');
    expect(back.rushUsedToday, true);
    expect(back.travelingThisRound, true);
    expect(back.roundNote, 'note');
  });

  test('tolerant fromJson: unknown pace/transport + missing keys -> defaults',
      () {
    final j = VerdantJourney.fromJson({'pace': 'zoom', 'transport': 'jetpack'});
    expect(j.pace, Pace.normal);
    expect(j.transport, isNull); // unknown transport dropped
    expect(j.partySize, 1);
  });

  test('newRoundSafety baseline = night ± pace', () {
    // watch 4 (Night) + fast pace -> -2 + -2 = -4.
    const j = VerdantJourney(watch: 4, pace: Pace.fast);
    expect(j.newRoundSafety, -4);
    // watch 1 (Morning) + slow -> +2.
    const k = VerdantJourney(watch: 1, pace: Pace.slow);
    expect(k.newRoundSafety, 2);
  });

  test('er excludes independent followers', () {
    const j = VerdantJourney(partySize: 4, independentFollowers: 3);
    expect(j.er, 6); // 4 + 4~/2, followers ignored
  });
}
