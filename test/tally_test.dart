// test/tally_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/tally.dart';

void main() {
  group('Tally', () {
    test('clamps current into 0..target on construct and adjust', () {
      expect(const Tally(start: 4, current: 9, target: 8).current, 8);
      expect(const Tally(start: 4, current: -3, target: 8).current, 0);
      const t = Tally(start: 4, current: 4, target: 8);
      expect(t.adjust(2).current, 6);
      expect(t.adjust(-10).current, 0);
      expect(t.adjust(100).current, 8);
    });

    test('target floored at 1', () {
      expect(const Tally(start: 0, current: 0, target: 0).target, 1);
    });

    test('failed at 0, won at target', () {
      expect(const Tally(start: 1, current: 0, target: 4).failed, isTrue);
      expect(const Tally(start: 1, current: 0, target: 4).won, isFalse);
      expect(const Tally(start: 3, current: 4, target: 4).won, isTrue);
      expect(const Tally(start: 3, current: 2, target: 4).failed, isFalse);
    });

    test('label is current(target)', () {
      expect(const Tally(start: 4, current: 4, target: 8).label, '4(8)');
    });

    test('JSON round-trips; maybeFromJson tolerant', () {
      const t = Tally(start: 4, current: 5, target: 8);
      expect(Tally.maybeFromJson(t.toJson()), equals(t));
      expect(Tally.maybeFromJson(null), isNull);
      expect(Tally.maybeFromJson(const {'start': 'x'}), isNull);
    });

    test('presets are the four Cairn-Solo sizes', () {
      expect(kTallyPresets.map((p) => (p.$2, p.$3)).toList(),
          [(2, 4), (3, 6), (4, 8), (5, 10)]);
    });
  });

  group('rollVsTally', () {
    test('classify: <= current is clean, else complication', () {
      const t = Tally(start: 4, current: 5, target: 8);
      expect(classifyVsTally(t, 5), TallyRollOutcome.clean);
      expect(classifyVsTally(t, 1), TallyRollOutcome.clean);
      expect(classifyVsTally(t, 6), TallyRollOutcome.complication);
    });
  });
}
