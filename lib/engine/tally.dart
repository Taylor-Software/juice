// lib/engine/tally.dart
import 'dice.dart';

/// A bidirectional "major task" tracker: [current] moves between 0 (fail) and
/// [target] (win). Distinct from Thread's one-way progress clock.
class Tally {
  const Tally({required this.start, required int current, required int target})
      : target = target < 1 ? 1 : target,
        current = current < 0
            ? 0
            : (current > (target < 1 ? 1 : target)
                ? (target < 1 ? 1 : target)
                : current);

  final int start;
  final int current; // clamped 0..target
  final int target; // >= 1

  bool get failed => current <= 0;
  bool get won => current >= target;
  String get label => '$current($target)';

  Tally adjust(int delta) =>
      Tally(start: start, current: current + delta, target: target);

  Tally copyWith({int? start, int? current, int? target}) => Tally(
        start: start ?? this.start,
        current: current ?? this.current,
        target: target ?? this.target,
      );

  Map<String, dynamic> toJson() =>
      {'start': start, 'current': current, 'target': target};

  static Tally? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final s = json['start'], c = json['current'], t = json['target'];
    if (s is! int || c is! int || t is! int) return null;
    return Tally(start: s, current: c, target: t);
  }

  @override
  bool operator ==(Object other) =>
      other is Tally &&
      other.start == start &&
      other.current == current &&
      other.target == target;

  @override
  int get hashCode => Object.hash(start, current, target);
}

/// The four authored task sizes (label, start, target) — Cairn Solo p.28 facts.
const List<(String, int, int)> kTallyPresets = [
  ('Modest task', 2, 4),
  ('Minor challenge', 3, 6),
  ('Difficult task', 4, 8),
  ('Long/dangerous task', 5, 10),
];

/// Outcome of rolling against a tally's current value (Cairn Solo p.28):
/// roll d{target}; <= current is a clean result, else a complication.
enum TallyRollOutcome { clean, complication }

TallyRollOutcome classifyVsTally(Tally t, int roll) =>
    roll <= t.current ? TallyRollOutcome.clean : TallyRollOutcome.complication;

TallyRollOutcome rollVsTally(Tally t, Dice dice) =>
    classifyVsTally(t, dice.dN(t.target));
