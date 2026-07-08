/// Pure model + resolution for a player-constructed yes/no oracle.
/// No Flutter imports — unit-tested without a widget harness.
///
/// A constructed oracle generalizes the built-in Roll High oracle: instead of a
/// hand-authored range matrix, the player picks a dice notation, a roll
/// direction, which outcome bands to include, and (optionally) a chaos factor —
/// and the range table is COMPUTED from the dice distribution + a likelihood
/// chosen live at roll time.
library;

import 'dice.dart';
import 'models.dart';

/// Which end of the range means "yes".
enum OracleDirection { rollHigh, rollLow }

/// How multiple same-size dice combine. [advantage]/[disadvantage] keep the
/// single best/worst die (only meaningful with 2+ dice); [sum] adds them.
enum RollMode { sum, advantage, disadvantage }

/// The six possible answer bands, in severity order (best→worst for rollHigh).
enum OutcomeBand { yesAnd, yes, yesBut, noBut, no, noAnd }

/// Fixed severity order — the tiling walks bands in this sequence.
const kOracleBandOrder = <OutcomeBand>[
  OutcomeBand.yesAnd,
  OutcomeBand.yes,
  OutcomeBand.yesBut,
  OutcomeBand.noBut,
  OutcomeBand.no,
  OutcomeBand.noAnd,
];

extension OutcomeBandInfo on OutcomeBand {
  String get label => switch (this) {
        OutcomeBand.yesAnd => 'Yes, and',
        OutcomeBand.yes => 'Yes',
        OutcomeBand.yesBut => 'Yes, but',
        OutcomeBand.noBut => 'No, but',
        OutcomeBand.no => 'No',
        OutcomeBand.noAnd => 'No, and',
      };

  bool get isYes =>
      this == OutcomeBand.yesAnd ||
      this == OutcomeBand.yes ||
      this == OutcomeBand.yesBut;

  bool get isExceptional => this != OutcomeBand.yes && this != OutcomeBand.no;
}

OutcomeBand? _bandFromName(String n) {
  for (final b in OutcomeBand.values) {
    if (b.name == n) return b;
  }
  return null;
}

/// The seven likelihood tiers, each with a base yes-probability. The tier is a
/// LIVE axis — chosen when the oracle is rolled, not stored on the oracle.
enum OracleLikelihood {
  almostCertain,
  veryLikely,
  likely,
  fiftyFifty,
  unlikely,
  veryUnlikely,
  almostImpossible,
}

extension OracleLikelihoodInfo on OracleLikelihood {
  String get label => switch (this) {
        OracleLikelihood.almostCertain => 'Almost certain',
        OracleLikelihood.veryLikely => 'Very likely',
        OracleLikelihood.likely => 'Likely',
        OracleLikelihood.fiftyFifty => '50 / 50',
        OracleLikelihood.unlikely => 'Unlikely',
        OracleLikelihood.veryUnlikely => 'Very unlikely',
        OracleLikelihood.almostImpossible => 'Almost impossible',
      };

  double get yesProbability => switch (this) {
        OracleLikelihood.almostCertain => 0.90,
        OracleLikelihood.veryLikely => 0.75,
        OracleLikelihood.likely => 0.65,
        OracleLikelihood.fiftyFifty => 0.50,
        OracleLikelihood.unlikely => 0.35,
        OracleLikelihood.veryUnlikely => 0.25,
        OracleLikelihood.almostImpossible => 0.10,
      };
}

/// A parsed dice notation: `NdM(+/-k)` or Fate dice `NdF(+/-k)`. [fate] dice
/// have three faces (-1, 0, +1); ordinary dice have faces 1..[sides].
class OracleDice {
  const OracleDice(this.count, this.sides, this.mod, {this.fate = false});
  final int count;
  final int sides; // ignored when [fate]
  final int mod;
  final bool fate;

  /// Single-die face → probability (uniform).
  Map<int, double> get facePmf => fate
      ? const {-1: 1 / 3, 0: 1 / 3, 1: 1 / 3}
      : {for (var v = 1; v <= sides; v++) v: 1.0 / sides};

  /// Sum-mode span (lowest/highest possible total). Advantage/disadvantage
  /// stay within a single die's face range — see [oracleDicePmf].
  int get min => (fate ? -count : count) + mod;
  int get max => (fate ? count : count * sides) + mod;
}

final _oracleDiceRe =
    RegExp(r'^(\d*)d(f|\d+)([+-]\d+)?$', caseSensitive: false);

/// Parse `d100`, `2d6`, `3d8+1`, `dF`, `2dF+2` (whitespace/case tolerant). Null
/// on garbage or out of range (count 1..20, sides 2..1000).
OracleDice? parseOracleDice(String notation) {
  final m = _oracleDiceRe.firstMatch(notation.replaceAll(RegExp(r'\s+'), ''));
  if (m == null) return null;
  final count = m.group(1)!.isEmpty ? 1 : int.parse(m.group(1)!);
  final mod = m.group(3) == null ? 0 : int.parse(m.group(3)!);
  if (count < 1 || count > 20) return null;
  if (m.group(2)!.toLowerCase() == 'f') {
    return OracleDice(count, 0, mod, fate: true);
  }
  final sides = int.parse(m.group(2)!);
  if (sides < 2 || sides > 1000) return null;
  return OracleDice(count, sides, mod);
}

Map<int, double> _convolve(Map<int, double> face, int count) {
  var dist = <int, double>{0: 1.0};
  for (var i = 0; i < count; i++) {
    final next = <int, double>{};
    dist.forEach((a, pa) {
      face.forEach((f, pf) {
        next[a + f] = (next[a + f] ?? 0) + pa * pf;
      });
    });
    dist = next;
  }
  return dist;
}

/// Distribution of the best (advantage) or worst (disadvantage) of [count] iid
/// single dice, from the single-die [face] pmf.
Map<int, double> _keepOne(Map<int, double> face, int count, bool best) {
  final faces = face.keys.toList()..sort();
  // cdf[v] = P(single <= v)
  final out = <int, double>{};
  var below = 0.0; // P(single < v) as we walk ascending
  var above = 1.0; // P(single >= v)
  for (final v in faces) {
    final pv = face[v]!;
    final le = below + pv; // P(<= v)
    final ge = above; // P(>= v)
    final p = best
        ? _pow(le, count) - _pow(below, count)
        : _pow(ge, count) - _pow(ge - pv, count);
    out[v] = p;
    below = le;
    above = ge - pv;
  }
  return out;
}

double _pow(double b, int n) {
  var r = 1.0;
  for (var i = 0; i < n; i++) {
    r *= b;
  }
  return r;
}

/// Probability mass function of [d] rolled under [mode]: value → probability.
/// [mode] advantage/disadvantage keep the best/worst single die (falling back
/// to [RollMode.sum] with fewer than 2 dice); [mode] sum convolves them. The
/// flat modifier shifts every value.
Map<int, double> oracleDicePmf(OracleDice d, [RollMode mode = RollMode.sum]) {
  final face = d.facePmf;
  final Map<int, double> base;
  if (mode != RollMode.sum && d.count >= 2) {
    base = _keepOne(face, d.count, mode == RollMode.advantage);
  } else {
    base = _convolve(face, d.count);
  }
  return {for (final e in base.entries) e.key + d.mod: e.value};
}

/// A user-constructed yes/no oracle (app-global, reusable across campaigns).
class ConstructedOracle {
  const ConstructedOracle({
    required this.id,
    required this.name,
    this.notation = 'd100',
    this.direction = OracleDirection.rollHigh,
    this.bands = const {
      OutcomeBand.yesAnd,
      OutcomeBand.yes,
      OutcomeBand.yesBut,
      OutcomeBand.noBut,
      OutcomeBand.no,
      OutcomeBand.noAnd,
    },
    this.chaos,
    this.mode = RollMode.sum,
  });

  final String id;
  final String name;
  final String notation;
  final OracleDirection direction;

  /// How multiple same-size dice combine (advantage/disadvantage/sum). Only
  /// applies when the notation rolls 2+ dice — see [advDisAvailable].
  final RollMode mode;

  /// Enabled outcome bands (any subset, at least 2 to be [valid]).
  final Set<OutcomeBand> bands;

  /// Optional chaos factor (1..9); null = off. Nudges the yes-probability and
  /// widens the exceptional edges.
  final int? chaos;

  bool get valid => bands.length >= 2 && parseOracleDice(notation) != null;

  /// True when advantage/disadvantage is meaningful — the notation rolls 2+
  /// (same-size) dice.
  bool get advDisAvailable => (parseOracleDice(notation)?.count ?? 1) >= 2;

  /// The mode actually applied at roll time — [RollMode.sum] whenever
  /// advantage/disadvantage isn't available, regardless of the stored [mode].
  RollMode get effectiveMode => advDisAvailable ? mode : RollMode.sum;

  ConstructedOracle copyWith({
    String? name,
    String? notation,
    OracleDirection? direction,
    Set<OutcomeBand>? bands,
    int? chaos,
    bool clearChaos = false,
    RollMode? mode,
  }) =>
      ConstructedOracle(
        id: id,
        name: name ?? this.name,
        notation: notation ?? this.notation,
        direction: direction ?? this.direction,
        bands: bands ?? this.bands,
        chaos: clearChaos ? null : (chaos ?? this.chaos),
        mode: mode ?? this.mode,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notation': notation,
        if (direction != OracleDirection.rollHigh) 'dir': direction.name,
        'bands': [
          for (final b in kOracleBandOrder)
            if (bands.contains(b)) b.name
        ],
        if (chaos != null) 'chaos': chaos,
        if (mode != RollMode.sum) 'mode': mode.name,
      };

  factory ConstructedOracle.fromJson(Map<String, dynamic> j) {
    final rawBands = (j['bands'] as List?)
            ?.whereType<String>()
            .map(_bandFromName)
            .whereType<OutcomeBand>()
            .toSet() ??
        const <OutcomeBand>{};
    return ConstructedOracle(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? '',
      notation: (j['notation'] as String?) ?? 'd100',
      direction: j['dir'] == 'rollLow'
          ? OracleDirection.rollLow
          : OracleDirection.rollHigh,
      bands: rawBands.isEmpty
          ? const {
              OutcomeBand.yesAnd,
              OutcomeBand.yes,
              OutcomeBand.yesBut,
              OutcomeBand.noBut,
              OutcomeBand.no,
              OutcomeBand.noAnd,
            }
          : rawBands,
      chaos: (j['chaos'] as num?)?.toInt(),
      mode: switch (j['mode']) {
        'advantage' => RollMode.advantage,
        'disadvantage' => RollMode.disadvantage,
        _ => RollMode.sum,
      },
    );
  }

  static ConstructedOracle? maybeFromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    if (map['id'] is! String) return null;
    return ConstructedOracle.fromJson(map);
  }
}

/// One contiguous range of the dice sum mapped to an outcome band.
class OracleBandRange {
  const OracleBandRange(this.band, this.lo, this.hi, this.probability);
  final OutcomeBand band;
  final int lo;
  final int hi;
  final double probability;
}

/// Per-band probability weights for [o] at likelihood [l]. Disabled bands hand
/// their mass to the enabled bands in their own zone (yes-side / no-side);
/// weights normalize to 1 across all enabled bands.
Map<OutcomeBand, double> _bandWeights(ConstructedOracle o, OracleLikelihood l) {
  var p = l.yesProbability;
  final chaos = o.chaos;
  if (chaos != null) {
    p = (p + (chaos - 5) * 0.03).clamp(0.05, 0.95);
  }
  final e = chaos != null ? 0.05 + chaos * 0.006 : 0.07;
  final w = <OutcomeBand, double>{
    OutcomeBand.yesAnd: e,
    OutcomeBand.yes: (p - 2 * e).clamp(0.01, 1.0),
    OutcomeBand.yesBut: e,
    OutcomeBand.noBut: e,
    OutcomeBand.no: ((1 - p) - 2 * e).clamp(0.01, 1.0),
    OutcomeBand.noAnd: e,
  };
  const zones = [
    [OutcomeBand.yesAnd, OutcomeBand.yes, OutcomeBand.yesBut],
    [OutcomeBand.noBut, OutcomeBand.no, OutcomeBand.noAnd],
  ];
  for (final zone in zones) {
    final enabled = zone.where(o.bands.contains).toList();
    final mass = zone.fold<double>(0, (a, b) => a + w[b]!);
    for (final b in zone) {
      if (!o.bands.contains(b)) w[b] = 0;
    }
    if (enabled.isEmpty) continue;
    final cur = enabled.fold<double>(0, (a, b) => a + w[b]!);
    if (cur > 0) {
      for (final b in enabled) {
        w[b] = w[b]! / cur * mass;
      }
    }
  }
  final tot = w.values.fold<double>(0, (a, b) => a + b);
  if (tot > 0) {
    for (final b in w.keys.toList()) {
      w[b] = w[b]! / tot;
    }
  }
  return w;
}

/// Computes the range table for [o] at likelihood [l]: contiguous dice-sum
/// ranges tiled by enabled band, honoring direction + the distribution curve.
/// Returns ranges in display order (high roll first).
List<OracleBandRange> resolveOracle(ConstructedOracle o, OracleLikelihood l) {
  final d = parseOracleDice(o.notation);
  if (d == null) return const [];
  final pmf = oracleDicePmf(d, o.effectiveMode);
  if (pmf.isEmpty) return const [];
  final w = _bandWeights(o, l);
  final order = kOracleBandOrder.where(o.bands.contains).toList();

  // Cumulative thresholds along the severity order.
  final thresh = <double>[];
  var acc = 0.0;
  for (final b in order) {
    acc += w[b] ?? 0;
    thresh.add(acc);
  }

  // Sum values ascending (the actual support of the distribution, which may be
  // negative for Fate dice).
  final ascending = pmf.keys.toList()..sort();
  // Walk from the "yes end" toward the "no end", assigning each value to a band
  // as the running probability crosses each threshold.
  final walk = o.direction == OracleDirection.rollLow
      ? ascending
      : ascending.reversed.toList();
  final assign = <int, int>{};
  var run = 0.0;
  var si = 0;
  for (final v in walk) {
    run += pmf[v] ?? 0;
    while (si < order.length - 1 && run > thresh[si] + 1e-9) {
      si++;
    }
    assign[v] = si;
  }

  final out = <OracleBandRange>[];
  for (var i = 0; i < order.length; i++) {
    int? lo, hi;
    var prob = 0.0;
    for (final v in ascending) {
      if (assign[v] == i) {
        lo ??= v;
        hi = v;
        prob += pmf[v] ?? 0;
      }
    }
    if (lo != null) out.add(OracleBandRange(order[i], lo, hi!, prob));
  }
  out.sort((a, b) => b.hi.compareTo(a.hi));
  return out;
}

/// The result of rolling a constructed oracle: the rolled sum + its band.
class OracleRollOutcome {
  const OracleRollOutcome(this.roll, this.band, this.notation);
  final int roll;
  final OutcomeBand band;
  final String notation;
}

/// Rolls [o]'s real dice with [dice], locates the band via [resolveOracle], and
/// returns the outcome. Falls back to the nearest band if (defensively) the
/// roll lands outside every range.
OracleRollOutcome rollOracle(
    ConstructedOracle o, OracleLikelihood l, Dice dice) {
  final d = parseOracleDice(o.notation) ?? const OracleDice(1, 100, 0);
  int rollOne() => d.fate ? dice.dN(3) - 2 : dice.dN(d.sides);
  final faces = [for (var i = 0; i < d.count; i++) rollOne()];
  final mode = o.effectiveMode;
  final int kept;
  if (mode == RollMode.advantage) {
    kept = faces.reduce((a, b) => a > b ? a : b);
  } else if (mode == RollMode.disadvantage) {
    kept = faces.reduce((a, b) => a < b ? a : b);
  } else {
    kept = faces.fold(0, (a, b) => a + b);
  }
  final sum = kept + d.mod;
  final ranges = resolveOracle(o, l);
  OutcomeBand band = ranges.isEmpty ? OutcomeBand.no : ranges.first.band;
  for (final r in ranges) {
    if (sum >= r.lo && sum <= r.hi) {
      band = r.band;
      break;
    }
  }
  return OracleRollOutcome(sum, band, o.notation);
}

/// Rolls [o] and packages the outcome as a journal-loggable [GenResult].
GenResult oracleGenResult(ConstructedOracle o, OracleLikelihood l, Dice dice) {
  final r = rollOracle(o, l, dice);
  final title = o.name.trim().isEmpty ? 'Oracle' : o.name.trim();
  return GenResult(title: title, summary: r.band.label, rolls: [
    Roll(
        label: 'Answer',
        value: r.band.label,
        detail: '${r.notation}: ${r.roll}'),
    Roll(label: 'Likelihood', value: l.label),
  ]);
}
