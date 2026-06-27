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
