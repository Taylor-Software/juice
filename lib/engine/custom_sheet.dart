/// Pure model + logic for the user-defined "Custom / Homebrew" sheet.
/// No Flutter imports — unit-tested without a widget harness.
library;

// ---------------------------------------------------------------------------
// Stat-modifier formulas (the only "math" a stat block needs).
// ---------------------------------------------------------------------------

/// How a stat block derives a modifier from a score.
/// [raw] shows no modifier; the renderer hides the modifier line for it.
enum StatModFormula { raw, fived, dccTight, scoreIsMod, halfFloor }

/// The derived modifier for [score] under [formula]. For [StatModFormula.raw]
/// this is 0 and unused (the renderer shows the score only).
int customStatMod(StatModFormula formula, int score) => switch (formula) {
      StatModFormula.raw => 0,
      StatModFormula.fived => ((score - 10) / 2).floor(),
      StatModFormula.dccTight => _dccTight(score),
      StatModFormula.scoreIsMod => score,
      StatModFormula.halfFloor => (score / 2).floor(),
    };

/// DCC's tightened ability table, capped at +/-3 (also adopted by the DCC
/// sheet when built). Defined over the 3..18 stepper range.
int _dccTight(int s) {
  if (s <= 3) return -3;
  if (s <= 5) return -2;
  if (s <= 8) return -1;
  if (s <= 12) return 0;
  if (s <= 15) return 1;
  if (s <= 17) return 2;
  return 3;
}

StatModFormula statModFormulaFromName(String? n) => StatModFormula.values
    .firstWhere((f) => f.name == n, orElse: () => StatModFormula.raw);

// ---------------------------------------------------------------------------
// Blocks + sheet.
// ---------------------------------------------------------------------------

/// The kinds of block a custom sheet can contain.
enum CustomBlockType {
  stat,
  counter,
  hp,
  roll,
  luck,
  conditions,
  dropdown,
  freeform,
  timer,
  togglechips,
  progress,
}

CustomBlockType? _blockTypeFromName(String? n) =>
    CustomBlockType.values.where((e) => e.name == n).firstOrNull;

/// One configurable block in a custom sheet's schema.
class CustomBlock {
  const CustomBlock({
    required this.id,
    required this.type,
    required this.label,
    this.config = const {},
  });

  /// Stable id, generated once at creation; keys into [CustomSheet.values].
  final String id;
  final CustomBlockType type;
  final String label;

  /// Per-type configuration (e.g. stat keys, dropdown options, roll config).
  final Map<String, dynamic> config;

  CustomBlock copyWith({String? label, Map<String, dynamic>? config}) =>
      CustomBlock(
        id: id,
        type: type,
        label: label ?? this.label,
        config: config ?? this.config,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'label': label,
        if (config.isNotEmpty) 'config': config,
      };

  static CustomBlock? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    final type = _blockTypeFromName(j['type'] as String?);
    if (type == null) return null; // forward-compat: drop unknown types
    final id = j['id'] as String?;
    if (id == null || id.isEmpty) return null; // an empty id collides in values
    return CustomBlock(
      id: id,
      type: type,
      label: (j['label'] as String?) ?? '',
      config: (j['config'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

/// A user-authored sheet: an ordered list of [blocks] (the schema) plus a
/// [values] map of live play state keyed by block id.
class CustomSheet {
  const CustomSheet({this.blocks = const [], this.values = const {}});

  final List<CustomBlock> blocks;
  final Map<String, dynamic> values;

  CustomSheet copyWith({
    List<CustomBlock>? blocks,
    Map<String, dynamic>? values,
  }) =>
      CustomSheet(
        blocks: blocks ?? this.blocks,
        values: values ?? this.values,
      );

  Map<String, dynamic> toJson() => {
        'blocks': blocks.map((b) => b.toJson()).toList(),
        if (values.isNotEmpty) 'values': values,
      };

  static CustomSheet? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    return CustomSheet(
      blocks: ((j['blocks'] as List?) ?? const [])
          .map(CustomBlock.maybeFromJson)
          .whereType<CustomBlock>()
          .toList(),
      values: (j['values'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

// ---------------------------------------------------------------------------
// Roll model. A roll block holds rows (label + own bonus value) and one
// shared RollConfig. resolveRoll is pure: the widget rolls dice and passes
// them in, so outcomes are deterministic in tests.
// ---------------------------------------------------------------------------

enum RollDirection { high, low }

enum RollTargetKind { fixed, prompt, rowValue }

enum RollCrit { none, matchingDice, natural }

/// One degree-of-success band. For [RollDirection.high] [threshold] is a
/// minimum total (integer-valued). For [RollDirection.low] it is a fraction of
/// the target (e.g. 0.5 = "great on half", 1.0 = "success at target").
class RollBand {
  const RollBand({required this.threshold, required this.label});
  final double threshold;
  final String label;
  Map<String, dynamic> toJson() => {'t': threshold, 'l': label};
  static RollBand? fromJson(dynamic j) {
    if (j is! Map) return null;
    return RollBand(
        threshold: (j['t'] as num?)?.toDouble() ?? 0,
        label: (j['l'] as String?) ?? '');
  }
}

class RollConfig {
  const RollConfig({
    this.diceCount = 1,
    this.diceSides = 20,
    this.addBonus = true,
    this.direction = RollDirection.high,
    this.targetKind = RollTargetKind.prompt,
    this.fixedTarget = 10,
    this.bands = const [],
    this.crit = RollCrit.none,
  });

  final int diceCount, diceSides, fixedTarget;
  final bool addBonus;
  final RollDirection direction;
  final RollTargetKind targetKind;
  final List<RollBand> bands;
  final RollCrit crit;

  Map<String, dynamic> toJson() => {
        'dc': diceCount,
        'ds': diceSides,
        'ab': addBonus,
        'dir': direction.name,
        'tk': targetKind.name,
        'ft': fixedTarget,
        if (bands.isNotEmpty) 'bands': bands.map((b) => b.toJson()).toList(),
        'crit': crit.name,
      };

  factory RollConfig.fromJson(dynamic j) {
    if (j is! Map) return const RollConfig();
    return RollConfig(
      diceCount: (j['dc'] as num?)?.toInt() ?? 1,
      diceSides: (j['ds'] as num?)?.toInt() ?? 20,
      addBonus: j['ab'] != false,
      direction: RollDirection.values
          .firstWhere((d) => d.name == j['dir'], orElse: () => RollDirection.high),
      targetKind: RollTargetKind.values.firstWhere((t) => t.name == j['tk'],
          orElse: () => RollTargetKind.prompt),
      fixedTarget: (j['ft'] as num?)?.toInt() ?? 10,
      bands: ((j['bands'] as List?) ?? const [])
          .map(RollBand.fromJson)
          .whereType<RollBand>()
          .toList(),
      crit: RollCrit.values
          .firstWhere((c) => c.name == j['crit'], orElse: () => RollCrit.none),
    );
  }
}

class RollOutcome {
  const RollOutcome(this.total, this.label);
  final int total;
  final String label;
}

/// Resolves a roll. [rowValue] is the row's own bonus/target number, [dice]
/// the already-rolled face values, [promptTarget] the entered DC when
/// [RollTargetKind.prompt].
RollOutcome resolveRoll(RollConfig cfg, int rowValue, List<int> dice,
    {int? promptTarget}) {
  final sum = dice.fold<int>(0, (a, b) => a + b);

  // Natural / matching-dice crits override everything.
  if (cfg.crit == RollCrit.matchingDice &&
      dice.length > 1 &&
      dice.toSet().length == 1) {
    if (dice.first == cfg.diceSides) {
      return RollOutcome(sum + (cfg.addBonus ? rowValue : 0), 'Critical Success');
    }
    if (dice.first == 1) {
      return RollOutcome(sum + (cfg.addBonus ? rowValue : 0), 'Critical Failure');
    }
  }
  if (cfg.crit == RollCrit.natural && dice.length == 1) {
    if (dice.first == cfg.diceSides) {
      return RollOutcome(sum + (cfg.addBonus ? rowValue : 0), 'Critical Success');
    }
    if (dice.first == 1) {
      return RollOutcome(sum + (cfg.addBonus ? rowValue : 0), 'Critical Failure');
    }
  }

  int target() => switch (cfg.targetKind) {
        RollTargetKind.fixed => cfg.fixedTarget,
        RollTargetKind.prompt => promptTarget ?? cfg.fixedTarget,
        RollTargetKind.rowValue => rowValue,
      };

  if (cfg.direction == RollDirection.low) {
    final raw = sum; // roll-under compares the raw dice
    final tgt = target();
    if (cfg.bands.isNotEmpty) {
      final sorted = [...cfg.bands]
        ..sort((a, b) => a.threshold.compareTo(b.threshold)); // low -> high
      for (final band in sorted) {
        if (raw <= (band.threshold * tgt).floor()) {
          return RollOutcome(raw, band.label);
        }
      }
      return RollOutcome(raw, 'Fail');
    }
    return RollOutcome(raw, raw <= tgt ? 'Pass' : 'Fail');
  }

  final total = sum + (cfg.addBonus ? rowValue : 0);
  if (cfg.bands.isNotEmpty) {
    final sorted = [...cfg.bands]
      ..sort((a, b) => b.threshold.compareTo(a.threshold)); // high -> low
    for (final band in sorted) {
      if (total >= band.threshold) return RollOutcome(total, band.label);
    }
    return RollOutcome(total, 'Fail');
  }
  final tgt = target();
  return RollOutcome(total, total >= tgt ? 'Pass' : 'Fail');
}
