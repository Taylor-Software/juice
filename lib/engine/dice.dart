import 'dart:math';

/// Dice primitives. Mirrors the verified Python engine in build_oracle.py.
class Dice {
  Dice([Random? rng]) : _rng = rng ?? Random();
  final Random _rng;

  /// One Fate die: -1, 0, or +1 with equal probability.
  int fate() => _rng.nextInt(3) - 1;

  /// Roll a single dN (1..n inclusive).
  int dN(int n) => _rng.nextInt(n) + 1;

  /// 1d10 returning the *index* 1..10. With skew: +1 advantage (high),
  /// -1 disadvantage (low). Index 10 corresponds to the table's "0" row.
  int d10Index({int skew = 0}) {
    if (skew > 0) return max(dN(10), dN(10));
    if (skew < 0) return min(dN(10), dN(10));
    return dN(10);
  }

  /// 1d100 (1..100).
  int d100() => dN(100);

  /// Pick "left" or "right" for the double-blank Fate Check tiebreak
  /// (in physical play this is the position of the primary die).
  bool coin() => _rng.nextBool();
}

/// Display label for a d10 index: 1..9 then "0" for the tenth slot.
String d10Label(int index) => index == 10 ? '0' : '$index';
