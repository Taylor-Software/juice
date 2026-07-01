import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/next_beat.dart';

void main() {
  test('no scene -> only name the scene', () {
    expect(
      nextBeatActions(
          hasScene: false, hasRecentAsk: false, interpretDone: false, aiReady: false),
      [BeatAction.nameScene],
    );
  });

  test('scene, no ask -> ask/inspire/capture', () {
    expect(
      nextBeatActions(
          hasScene: true, hasRecentAsk: false, interpretDone: false, aiReady: true),
      [BeatAction.ask, BeatAction.inspire, BeatAction.capture],
    );
  });

  test('scene + ask, ai ready, not yet interpreted -> interpret leads', () {
    expect(
      nextBeatActions(
          hasScene: true, hasRecentAsk: true, interpretDone: false, aiReady: true),
      [BeatAction.interpret, BeatAction.capture, BeatAction.askAgain],
    );
  });

  test('scene + ask, already interpreted -> no interpret', () {
    final a = nextBeatActions(
        hasScene: true, hasRecentAsk: true, interpretDone: true, aiReady: true);
    expect(a.contains(BeatAction.interpret), isFalse);
    expect(a, [BeatAction.askAgain, BeatAction.capture, BeatAction.inspire]);
  });

  test('scene + ask, ai off -> no interpret even if not done', () {
    final a = nextBeatActions(
        hasScene: true, hasRecentAsk: true, interpretDone: false, aiReady: false);
    expect(a.contains(BeatAction.interpret), isFalse);
    expect(a, [BeatAction.askAgain, BeatAction.capture, BeatAction.inspire]);
  });

  test('never returns more than 3 actions', () {
    for (final scene in [true, false]) {
      for (final ask in [true, false]) {
        for (final done in [true, false]) {
          for (final ai in [true, false]) {
            expect(
                nextBeatActions(
                        hasScene: scene,
                        hasRecentAsk: ask,
                        interpretDone: done,
                        aiReady: ai)
                    .length,
                lessThanOrEqualTo(3));
          }
        }
      }
    }
  });
}
