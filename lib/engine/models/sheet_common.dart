/// Shared sheet primitives: stats, tracks, progress, asset meters.
///
/// Part of the `models` library — see models.dart. Split for
/// navigability only; parts share one scope, so the private helpers
/// (`_intOr`, `_strOr`, `_strSet`) and every cross-reference still work.
part of '../models.dart';

/// The hit-point contract shared by every sheet that has a single HP pool.
///
/// Each sheet owns its own pool semantics — what the pool is called
/// (Draw Steel's Stamina), and how damage clamps against its own max — instead
/// of [Character] re-deriving all of it eleven times. Sheets with no single
/// pool deliberately do NOT implement this: the Ironsworn family tracks
/// meters, the custom builder's pool is user-defined, and a funnel holds
/// peasants rather than one character.
abstract interface class HasHpPool {
  /// The pool as `(current, max)`.
  (int, int) get hpPool;

  /// This sheet with its pool moved by [delta], clamped to `0..max`.
  HasHpPool withHp(int delta);
}

/// One labeled stat on a character sheet; value is free text ('17', '+2', 'd8').
class CharStat {
  const CharStat({required this.label, required this.value, this.modFormula});
  final String label;
  final String value;

  /// Optional derived-modifier formula. Null = a plain value with no modifier
  /// (the historical behaviour); set = show a modifier beside numeric values.
  final StatModFormula? modFormula;

  /// The value parsed as an integer, or null when it isn't numeric (freeform
  /// stats stay text). Drives the +/- steppers and the derived modifier.
  int? get numericValue => int.tryParse(value.trim());

  /// The derived modifier under [modFormula], or null when no formula is set
  /// or the value isn't numeric.
  int? get modifier {
    final f = modFormula;
    final n = numericValue;
    return (f == null || n == null) ? null : customStatMod(f, n);
  }

  CharStat copyWith(
          {String? label,
          String? value,
          StatModFormula? modFormula,
          bool clearFormula = false}) =>
      CharStat(
        label: label ?? this.label,
        value: value ?? this.value,
        modFormula: clearFormula ? null : (modFormula ?? this.modFormula),
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'value': value,
        if (modFormula != null) 'mod': modFormula!.name,
      };

  /// Parses one stat entry; returns null for anything that isn't a map.
  /// `is Map` (not `is Map<String, dynamic>`) so Dart literal maps
  /// (e.g. Map<String, String>) parse the same as jsonDecode output.
  static CharStat? maybeFromJson(dynamic j) => j is Map
      ? CharStat(
          label: (j['label'] as String?) ?? '',
          value: (j['value'] as String?) ?? '',
          modFormula: j['mod'] != null
              ? statModFormulaFromName(j['mod'] as String?)
              : null)
      : null;
}

/// A current/max track (HP, momentum, supply…).
class CharTrack {
  const CharTrack(
      {required this.label, required this.current, required this.max});
  final String label;
  final int current;
  final int max;

  /// New track with [delta] applied to current, clamped to 0..max.
  CharTrack adjusted(int delta) => CharTrack(
      label: label, current: (current + delta).clamp(0, max), max: max);

  Map<String, dynamic> toJson() =>
      {'label': label, 'current': current, 'max': max};

  /// Parses one track entry; returns null for anything that isn't a map.
  /// Sanitizes values: `max` floored at 0, `current` clamped into 0..max.
  static CharTrack? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    final max = ((j['max'] as int?) ?? 0).clamp(0, 1 << 31);
    final current = ((j['current'] as int?) ?? 0).clamp(0, max);
    return CharTrack(
        label: (j['label'] as String?) ?? '', current: current, max: max);
  }
}

/// Progress-track rank; mark size (ticks per progress mark) per Ironsworn.
enum ProgressRank { troublesome, dangerous, formidable, extreme, epic }

extension ProgressRankX on ProgressRank {
  /// Ticks added per progress mark (4 ticks = one filled box).
  int get markTicks => switch (this) {
        ProgressRank.troublesome => 12,
        ProgressRank.dangerous => 8,
        ProgressRank.formidable => 4,
        ProgressRank.extreme => 2,
        ProgressRank.epic => 1,
      };

  /// Capitalised display label ('Dangerous').
  String get label => name[0].toUpperCase() + name.substring(1);
}

ProgressRank _progressRankFromName(String? s) => ProgressRank.values
    .firstWhere((r) => r.name == s, orElse: () => ProgressRank.dangerous);

/// A named progress track (vow, later: legacy track). 10 boxes × 4 ticks = 40.
class ProgressTrack {
  const ProgressTrack({
    required this.name,
    this.rank = ProgressRank.dangerous,
    this.ticks = 0,
  });
  final String name;
  final ProgressRank rank;
  final int ticks; // 0..40

  int get boxes => ticks ~/ 4; // filled boxes 0..10
  int get markTicks => rank.markTicks;

  /// New track with [marks] progress marks applied (negative un-marks).
  ProgressTrack marked(int marks) =>
      copyWith(ticks: ticks + marks * rank.markTicks);

  ProgressTrack copyWith({String? name, ProgressRank? rank, int? ticks}) =>
      ProgressTrack(
        name: name ?? this.name,
        rank: rank ?? this.rank,
        ticks: (ticks ?? this.ticks).clamp(0, 40),
      );

  Map<String, dynamic> toJson() =>
      {'name': name, 'rank': rank.name, 'ticks': ticks};

  static ProgressTrack? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    return ProgressTrack(
      name: j['name'] is String ? j['name'] as String : '',
      rank: _progressRankFromName(
          j['rank'] is String ? j['rank'] as String : null),
      ticks: ((j['ticks'] is int ? j['ticks'] as int : 0)).clamp(0, 40),
    );
  }
}

/// A condition meter on an asset (Starforged/SI companion health, vehicle
/// integrity, ammo, …). Denormalized from the Datasworn `controls` so the sheet
/// renders it without the ruleset; [value] is the live tracked value.
class AssetMeter {
  const AssetMeter({
    required this.key,
    required this.label,
    required this.min,
    required this.max,
    required this.value,
  });
  final String key;
  final String label;
  final int min;
  final int max;
  final int value;

  AssetMeter copyWith({int? value}) => AssetMeter(
        key: key,
        label: label,
        min: min,
        max: max,
        value: (value ?? this.value).clamp(min, max),
      );

  Map<String, dynamic> toJson() =>
      {'k': key, 'l': label, 'mn': min, 'mx': max, 'v': value};

  factory AssetMeter.fromJson(Map<String, dynamic> j) => AssetMeter(
        key: j['k'] is String ? j['k'] as String : '',
        label: j['l'] is String ? j['l'] as String : '',
        min: (j['mn'] as num?)?.toInt() ?? 0,
        max: (j['mx'] as num?)?.toInt() ?? 0,
        value: (j['v'] as num?)?.toInt() ?? 0,
      );
}

/// A persisted asset on an Ironsworn sheet. [enabledAbilities] parallels the
/// asset definition's abilities[]; only the toggled-on flags are play state.
class AssetState {
  const AssetState({
    required this.assetId,
    required this.name,
    this.category = '',
    this.enabledAbilities = const [],
    this.meters = const [],
  });
  final String assetId; // datasworn _id
  final String name;
  final String category;
  final List<bool> enabledAbilities;
  final List<AssetMeter> meters;

  AssetState copyWith(
          {List<bool>? enabledAbilities, List<AssetMeter>? meters}) =>
      AssetState(
        assetId: assetId,
        name: name,
        category: category,
        enabledAbilities: enabledAbilities ?? this.enabledAbilities,
        meters: meters ?? this.meters,
      );

  Map<String, dynamic> toJson() => {
        'assetId': assetId,
        'name': name,
        if (category.isNotEmpty) 'category': category,
        'enabledAbilities': enabledAbilities,
        if (meters.isNotEmpty) 'meters': meters.map((m) => m.toJson()).toList(),
      };

  static AssetState? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    final id = j['assetId'];
    if (id is! String || id.isEmpty) return null;
    return AssetState(
      assetId: id,
      name: j['name'] is String ? j['name'] as String : '',
      category: j['category'] is String ? j['category'] as String : '',
      enabledAbilities: j['enabledAbilities'] is List
          ? (j['enabledAbilities'] as List).map((e) => e == true).toList()
          : const [],
      meters: j['meters'] is List
          ? (j['meters'] as List)
              .whereType<Map<dynamic, dynamic>>()
              .map((m) => AssetMeter.fromJson(m.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }
}
