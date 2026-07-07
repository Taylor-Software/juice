/// Plain immutable models for engine output and persisted state.
/// No freezed/codegen — the data is small and stable.
library;

import 'custom_sheet.dart';
import 'dungeon/footprint.dart';
import 'tally.dart';

/// Upper clamp for player-managed numeric sheet fields (HP, slots, pools…):
/// an arbitrary "large enough" ceiling to keep JSON round-trips sane, not a
/// rules value.
const int kFieldClampMax = 1 << 20;

// Tolerant JSON readers shared by the sheets' `maybeFromJson` factories.
int _intOr(dynamic v, int d) => v is int ? v : d;
String _strOr(dynamic v) => v is String ? v : '';
Set<String> _strSet(dynamic v) =>
    v is List ? v.whereType<String>().toSet() : const {};

/// Likelihood applied to a Fate Check.
enum Likelihood { unlikely, normal, likely }

extension LikelihoodLabel on Likelihood {
  String get label => switch (this) {
        Likelihood.unlikely => 'Unlikely',
        Likelihood.normal => 'Normal',
        Likelihood.likely => 'Likely',
      };
  String get key => name; // 'unlikely' | 'normal' | 'likely'
}

/// Result of a Fate Check.
class FateResult {
  const FateResult({
    required this.primary,
    required this.secondary,
    required this.side,
    required this.intensityRoll,
    required this.intensity,
    required this.likelihood,
    required this.result,
  });

  final int primary; // -1, 0, +1
  final int secondary; // -1, 0, +1
  final String? side; // 'left' | 'right' for double-blank, else null
  final int intensityRoll; // 1..6
  final String intensity; // Minimal..Maximum
  final Likelihood likelihood;
  final String result; // e.g. "Yes But", "Invalid Assumption"

  static String _glyph(int v) => v > 0 ? '+' : (v < 0 ? '-' : '0');

  /// Shorthand like "+-4" (primary, secondary, intensity), per the PDF.
  String get shorthand =>
      '${_glyph(primary)}${_glyph(secondary)}$intensityRoll';

  bool get isRandomEvent => result.contains('Random Event');
  bool get isInvalidAssumption => result == 'Invalid Assumption';
}

/// A single rolled table line ("Color: Crimson Red").
class Roll {
  const Roll({required this.label, required this.value, this.detail});
  final String label; // e.g. "Color"
  final String value; // e.g. "Crimson Red"
  final String? detail; // optional extra (e.g. die roll, intensity)

  String get display => detail == null ? value : '$value ($detail)';
}

/// A composite generator result: a titled group of rolls.
class GenResult {
  const GenResult({required this.title, required this.rolls, this.summary});
  final String title;
  final List<Roll> rolls;
  final String? summary; // optional one-line summary

  String get asText {
    final body = rolls.map((r) => '${r.label}: ${r.display}').join('\n');
    return summary == null ? body : '$summary\n$body';
  }

  /// Structured journal payload (spec: cycle4 living-journal §2).
  Map<String, dynamic> toPayload() => {
        'v': 1,
        if (summary != null) 'summary': summary,
        'rolls': [
          for (final r in rolls) {'label': r.label, 'display': r.display}
        ],
      };
}

/// Kind of journal entry: player prose, a tool result, a scene divider, or a
/// freehand sketch.
enum JournalKind { text, result, scene, sketch, session }

/// Persisted journal entry (formerly LogEntry; old JSON parses as `result`).
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.timestamp,
    required this.title,
    required this.body,
    this.threadId,
    this.kind = JournalKind.result,
    this.chaosFactor,
    this.tags = const [],
    this.sourceTool,
    this.payload,
    this.pinned = false,
  });
  final String id;
  final DateTime timestamp;
  final String title;
  final String body;
  final String? threadId;
  final JournalKind kind;

  /// Chaos factor snapshot for scene dividers (Mythic), else null.
  final int? chaosFactor;

  /// Player-applied tags; replaced wholesale via copyWith (pass `[]` to clear).
  final List<String> tags;

  /// Tool-registry id that produced this result (open-in-tool), else null.
  final String? sourceTool;

  /// Structured result payload (v1: summary/rolls/command/args/rerollable);
  /// null for prose and legacy entries. Tolerant: render falls back to flat
  /// text for unknown shapes.
  final Map<String, dynamic>? payload;

  /// Player-pinned flag (shows a ⚑ Pin action on result cards), default false.
  final bool pinned;

  JournalEntry copyWith({
    String? title,
    String? body,
    String? threadId,
    bool clearThreadId = false,
    List<String>? tags,
    Map<String, dynamic>? payload,
    bool? pinned,
  }) =>
      JournalEntry(
        id: id,
        timestamp: timestamp,
        title: title ?? this.title,
        body: body ?? this.body,
        threadId: clearThreadId ? null : (threadId ?? this.threadId),
        kind: kind,
        chaosFactor: chaosFactor,
        tags: tags ?? this.tags,
        sourceTool: sourceTool,
        payload: payload ?? this.payload,
        pinned: pinned ?? this.pinned,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'title': title,
        'body': body,
        'threadId': threadId,
        'kind': kind.name,
        if (chaosFactor != null) 'chaosFactor': chaosFactor,
        'tags': tags,
        if (sourceTool != null) 'sourceTool': sourceTool,
        if (payload != null) 'payload': payload,
        'pinned': pinned,
      };

  factory JournalEntry.fromJson(Map<String, dynamic> j) => JournalEntry(
        id: j['id'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        title: j['title'] as String,
        body: j['body'] as String,
        threadId: j['threadId'] as String?,
        kind: JournalKind.values.asNameMap()[j['kind']] ?? JournalKind.result,
        chaosFactor: j['chaosFactor'] as int?,
        tags: ((j['tags'] as List?) ?? const []).whereType<String>().toList(),
        sourceTool: j['sourceTool'] as String?,
        payload: (j['payload'] as Map?)?.cast<String, dynamic>(),
        pinned: (j['pinned'] as bool?) ?? false,
      );
}

/// Persisted thread (Mythic-style "thread"/vow the player tracks).
class Thread {
  Thread({
    required this.id,
    required this.title,
    this.note = '',
    this.open = true,
    this.pinned = false,
    int progress = 0,
    int progressMax = 10,
    this.tally,
  })  : progressMax = progressMax < 1 ? 1 : progressMax,
        progress = progress.clamp(0, progressMax < 1 ? 1 : progressMax);
  final String id;
  final String title;
  final String note;
  final bool open;
  final bool pinned;

  /// Numeric progress clock (n/[progressMax]); always clamped into 0..max.
  final int progress;

  /// Clock denominator (default 10); always >= 1.
  final int progressMax;

  /// Optional bidirectional success/failure tally (Cairn-Solo style); null when
  /// this thread is a plain storyline. Distinct from the [progress] clock.
  final Tally? tally;

  Thread copyWith({
    String? title,
    String? note,
    bool? open,
    bool? pinned,
    int? progress,
    int? progressMax,
    Tally? tally,
    bool clearTally = false,
  }) =>
      Thread(
        id: id,
        title: title ?? this.title,
        note: note ?? this.note,
        open: open ?? this.open,
        pinned: pinned ?? this.pinned,
        progress: progress ?? this.progress,
        progressMax: progressMax ?? this.progressMax,
        tally: clearTally ? null : (tally ?? this.tally),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'open': open,
        if (pinned) 'pinned': true,
        if (progress > 0) 'progress': progress,
        if (progressMax != 10) 'progressMax': progressMax,
        if (tally != null) 'tally': tally!.toJson(),
      };

  factory Thread.fromJson(Map<String, dynamic> j) => Thread(
        id: j['id'] as String,
        title: j['title'] as String,
        note: (j['note'] as String?) ?? '',
        open: (j['open'] as bool?) ?? true,
        pinned: (j['pinned'] as bool?) ?? false,
        progress: (j['progress'] as int?) ?? 0,
        progressMax: (j['progressMax'] as int?) ?? 10,
        tally:
            Tally.maybeFromJson((j['tally'] as Map?)?.cast<String, dynamic>()),
      );
}

/// One labeled stat on a character sheet; value is free text ('17', '+2', 'd8').
class CharStat {
  const CharStat({required this.label, required this.value});
  final String label;
  final String value;

  Map<String, dynamic> toJson() => {'label': label, 'value': value};

  /// Parses one stat entry; returns null for anything that isn't a map.
  /// `is Map` (not `is Map<String, dynamic>`) so Dart literal maps
  /// (e.g. Map<String, String>) parse the same as jsonDecode output.
  static CharStat? maybeFromJson(dynamic j) => j is Map
      ? CharStat(
          label: (j['label'] as String?) ?? '',
          value: (j['value'] as String?) ?? '')
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

/// Classic Ironsworn debilities (conditions, banes, burdens). Each marked
/// debility lowers max momentum and the burn-reset value by 1.
const kIronswornDebilities = <String, String>{
  'wounded': 'Wounded',
  'shaken': 'Shaken',
  'unprepared': 'Unprepared',
  'encumbered': 'Encumbered',
  'maimed': 'Maimed',
  'corrupted': 'Corrupted',
  'cursed': 'Cursed',
  'tormented': 'Tormented',
};

/// Bespoke Classic Ironsworn sheet. Additive on [Character] like
/// [CharacterEmulation]: null until "New Ironsworn character" writes it.
class IronswornSheet {
  const IronswornSheet({
    this.edge = 1,
    this.heart = 1,
    this.iron = 1,
    this.shadow = 1,
    this.wits = 1,
    this.health = 5,
    this.spirit = 5,
    this.supply = 5,
    this.momentum = 2,
    this.xpEarned = 0,
    this.xpSpent = 0,
    this.bonds = 0,
    this.debilities = const {},
    this.vows = const [],
    this.assets = const [],
  });

  final int edge, heart, iron, shadow, wits; // 1..3
  final int health, spirit, supply; // 0..5
  final int momentum; // -6..momentumMax
  final int xpEarned, xpSpent; // >=0
  final int bonds; // 0..10 progress boxes
  final Set<String> debilities; // ids from kIronswornDebilities
  final List<ProgressTrack> vows;
  final List<AssetState> assets;

  int get momentumMax => 10 - debilities.length;
  int get momentumReset => (2 - debilities.length).clamp(0, 2);

  /// Standard pre-made starting character (3/2/2/1/1, full meters, +2 momentum).
  factory IronswornSheet.premade() => const IronswornSheet(
        edge: 3,
        heart: 2,
        iron: 2,
        shadow: 1,
        wits: 1,
        health: 5,
        spirit: 5,
        supply: 5,
        momentum: 2,
      );

  IronswornSheet copyWith({
    int? edge,
    int? heart,
    int? iron,
    int? shadow,
    int? wits,
    int? health,
    int? spirit,
    int? supply,
    int? momentum,
    int? xpEarned,
    int? xpSpent,
    int? bonds,
    Set<String>? debilities,
    List<ProgressTrack>? vows,
    List<AssetState>? assets,
  }) {
    final dbs = debilities ?? this.debilities;
    final maxM = 10 - dbs.length;
    return IronswornSheet(
      edge: (edge ?? this.edge).clamp(1, 3),
      heart: (heart ?? this.heart).clamp(1, 3),
      iron: (iron ?? this.iron).clamp(1, 3),
      shadow: (shadow ?? this.shadow).clamp(1, 3),
      wits: (wits ?? this.wits).clamp(1, 3),
      health: (health ?? this.health).clamp(0, 5),
      spirit: (spirit ?? this.spirit).clamp(0, 5),
      supply: (supply ?? this.supply).clamp(0, 5),
      momentum: (momentum ?? this.momentum).clamp(-6, maxM),
      xpEarned: (xpEarned ?? this.xpEarned).clamp(0, 1 << 31),
      xpSpent: (xpSpent ?? this.xpSpent).clamp(0, 1 << 31),
      bonds: (bonds ?? this.bonds).clamp(0, 10),
      debilities: dbs,
      vows: vows ?? this.vows,
      assets: assets ?? this.assets,
    );
  }

  Map<String, dynamic> toJson() => {
        'edge': edge,
        'heart': heart,
        'iron': iron,
        'shadow': shadow,
        'wits': wits,
        'health': health,
        'spirit': spirit,
        'supply': supply,
        'momentum': momentum,
        'xpEarned': xpEarned,
        'xpSpent': xpSpent,
        'bonds': bonds,
        if (debilities.isNotEmpty) 'debilities': debilities.toList(),
        if (vows.isNotEmpty) 'vows': vows.map((v) => v.toJson()).toList(),
        if (assets.isNotEmpty) 'assets': assets.map((a) => a.toJson()).toList(),
      };

  static IronswornSheet? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    final dbs = j['debilities'] is List
        ? (j['debilities'] as List)
            .whereType<String>()
            .where(kIronswornDebilities.containsKey)
            .toSet()
        : <String>{};
    final maxM = 10 - dbs.length;
    return IronswornSheet(
      edge: _intOr(j['edge'], 1).clamp(1, 3),
      heart: _intOr(j['heart'], 1).clamp(1, 3),
      iron: _intOr(j['iron'], 1).clamp(1, 3),
      shadow: _intOr(j['shadow'], 1).clamp(1, 3),
      wits: _intOr(j['wits'], 1).clamp(1, 3),
      health: _intOr(j['health'], 5).clamp(0, 5),
      spirit: _intOr(j['spirit'], 5).clamp(0, 5),
      supply: _intOr(j['supply'], 5).clamp(0, 5),
      momentum: _intOr(j['momentum'], 2).clamp(-6, maxM),
      xpEarned: _intOr(j['xpEarned'], 0).clamp(0, 1 << 31),
      xpSpent: _intOr(j['xpSpent'], 0).clamp(0, 1 << 31),
      bonds: _intOr(j['bonds'], 0).clamp(0, 10),
      debilities: dbs,
      vows: j['vows'] is List
          ? (j['vows'] as List)
              .map(ProgressTrack.maybeFromJson)
              .whereType<ProgressTrack>()
              .toList()
          : const [],
      assets: j['assets'] is List
          ? (j['assets'] as List)
              .map(AssetState.maybeFromJson)
              .whereType<AssetState>()
              .toList()
          : const [],
    );
  }
}

/// Read-only asset definition parsed from a loaded ruleset map's
/// `asset_collections` block (emitted by build_datasworn.py).
class IronswornAssetDef {
  const IronswornAssetDef({
    required this.id,
    required this.name,
    required this.category,
    required this.abilities,
    required this.abilityEnabled,
    this.meters = const [],
  });
  final String id;
  final String name;
  final String category;
  final List<String> abilities; // ability text
  final List<bool> abilityEnabled; // default-on flags
  final List<AssetMeter> meters; // condition meters (health/integrity/ammo/…)

  /// A fresh persisted [AssetState] with the definition's default flags + meters.
  AssetState toState() => AssetState(
        assetId: id,
        name: name,
        category: category,
        enabledAbilities: List<bool>.of(abilityEnabled),
        meters: List<AssetMeter>.of(meters),
      );

  /// Parse condition meters from a Datasworn asset's `controls` map. Each
  /// control with `field_type == 'condition_meter'` becomes an [AssetMeter]
  /// seeded at its default `value`; nested toggles (battered, out-of-action) are
  /// not surfaced yet.
  static List<AssetMeter> _metersFromControls(dynamic controls) {
    if (controls is! Map) return const [];
    final out = <AssetMeter>[];
    for (final e in controls.entries) {
      final c = e.value;
      if (c is! Map || c['field_type'] != 'condition_meter') continue;
      final max = (c['max'] as num?)?.toInt();
      if (max == null) continue;
      final min = (c['min'] as num?)?.toInt() ?? 0;
      out.add(AssetMeter(
        key: '${e.key}',
        label: c['label'] is String ? c['label'] as String : '${e.key}',
        min: min,
        max: max,
        value: (c['value'] as num?)?.toInt() ?? max,
      ));
    }
    return out;
  }

  static List<IronswornAssetDef> listFromRuleset(Map<String, dynamic> ruleset) {
    final out = <IronswornAssetDef>[];
    final colls = ruleset['asset_collections'];
    if (colls is! List) return out;
    for (final coll in colls) {
      if (coll is! Map) continue;
      final assets = coll['assets'];
      if (assets is! List) continue;
      final collName = coll['name'] is String ? coll['name'] as String : '';
      for (final a in assets) {
        if (a is! Map) continue;
        final id = a['id'];
        final name = a['name'];
        if (id is! String || name is! String) continue;
        final abilities = <String>[];
        final enabled = <bool>[];
        if (a['abilities'] is List) {
          for (final ab in a['abilities'] as List) {
            if (ab is! Map) continue;
            abilities.add(ab['text'] is String ? ab['text'] as String : '');
            enabled.add(ab['enabled'] == true);
          }
        }
        out.add(IronswornAssetDef(
          id: id,
          name: name,
          category:
              a['category'] is String ? a['category'] as String : collName,
          abilities: abilities,
          abilityEnabled: enabled,
          meters: _metersFromControls(a['controls']),
        ));
      }
    }
    return out;
  }
}

/// Starforged impacts (replace Classic debilities). Each marked impact lowers
/// max momentum and the burn-reset value by 1. Ordered by datasworn category:
/// misfortunes, vehicle troubles, burdens, lasting effects.
const kStarforgedImpacts = <String, String>{
  'wounded': 'Wounded',
  'shaken': 'Shaken',
  'unprepared': 'Unprepared',
  'battered': 'Battered',
  'cursed': 'Cursed',
  'doomed': 'Doomed',
  'tormented': 'Tormented',
  'indebted': 'Indebted',
  'permanently_harmed': 'Permanently Harmed',
  'traumatized': 'Traumatized',
};

/// Bespoke Starforged sheet. Additive on [Character] like [IronswornSheet]:
/// null until "New Starforged character" writes it.
class StarforgedSheet {
  const StarforgedSheet({
    this.edge = 1,
    this.heart = 1,
    this.iron = 1,
    this.shadow = 1,
    this.wits = 1,
    this.health = 5,
    this.spirit = 5,
    this.supply = 5,
    this.momentum = 2,
    this.xpEarned = 0,
    this.xpSpent = 0,
    this.questsLegacy = 0,
    this.bondsLegacy = 0,
    this.discoveriesLegacy = 0,
    this.impacts = const {},
    this.vows = const [],
    this.connections = const [],
    this.assets = const [],
    this.assetRuleset = 'starforged',
  });

  final int edge, heart, iron, shadow, wits; // 1..3
  final int health, spirit, supply; // 0..5
  final int momentum; // -6..momentumMax
  final int xpEarned, xpSpent; // >=0
  final int questsLegacy, bondsLegacy, discoveriesLegacy; // 0..10 boxes
  final Set<String> impacts; // ids from kStarforgedImpacts
  final List<ProgressTrack> vows;
  final List<ProgressTrack> connections;
  final List<AssetState> assets;
  final String assetRuleset; // 'starforged' | 'sundered_isles'

  bool get isSundered => assetRuleset == 'sundered_isles';

  static String _validRuleset(String s) =>
      s == 'sundered_isles' ? 'sundered_isles' : 'starforged';

  int get momentumMax => 10 - impacts.length;
  int get momentumReset => (2 - impacts.length).clamp(0, 2);

  factory StarforgedSheet.premade({String assetRuleset = 'starforged'}) =>
      StarforgedSheet(
        edge: 3,
        heart: 2,
        iron: 2,
        shadow: 1,
        wits: 1,
        health: 5,
        spirit: 5,
        supply: 5,
        momentum: 2,
        assetRuleset: assetRuleset,
      );

  StarforgedSheet copyWith({
    int? edge,
    int? heart,
    int? iron,
    int? shadow,
    int? wits,
    int? health,
    int? spirit,
    int? supply,
    int? momentum,
    int? xpEarned,
    int? xpSpent,
    int? questsLegacy,
    int? bondsLegacy,
    int? discoveriesLegacy,
    Set<String>? impacts,
    List<ProgressTrack>? vows,
    List<ProgressTrack>? connections,
    List<AssetState>? assets,
    String? assetRuleset,
  }) {
    final imp = impacts ?? this.impacts;
    final maxM = 10 - imp.length;
    return StarforgedSheet(
      edge: (edge ?? this.edge).clamp(1, 3),
      heart: (heart ?? this.heart).clamp(1, 3),
      iron: (iron ?? this.iron).clamp(1, 3),
      shadow: (shadow ?? this.shadow).clamp(1, 3),
      wits: (wits ?? this.wits).clamp(1, 3),
      health: (health ?? this.health).clamp(0, 5),
      spirit: (spirit ?? this.spirit).clamp(0, 5),
      supply: (supply ?? this.supply).clamp(0, 5),
      momentum: (momentum ?? this.momentum).clamp(-6, maxM),
      xpEarned: (xpEarned ?? this.xpEarned).clamp(0, 1 << 31),
      xpSpent: (xpSpent ?? this.xpSpent).clamp(0, 1 << 31),
      questsLegacy: (questsLegacy ?? this.questsLegacy).clamp(0, 10),
      bondsLegacy: (bondsLegacy ?? this.bondsLegacy).clamp(0, 10),
      discoveriesLegacy:
          (discoveriesLegacy ?? this.discoveriesLegacy).clamp(0, 10),
      impacts: imp,
      vows: vows ?? this.vows,
      connections: connections ?? this.connections,
      assets: assets ?? this.assets,
      assetRuleset: _validRuleset(assetRuleset ?? this.assetRuleset),
    );
  }

  Map<String, dynamic> toJson() => {
        'edge': edge,
        'heart': heart,
        'iron': iron,
        'shadow': shadow,
        'wits': wits,
        'health': health,
        'spirit': spirit,
        'supply': supply,
        'momentum': momentum,
        'xpEarned': xpEarned,
        'xpSpent': xpSpent,
        'questsLegacy': questsLegacy,
        'bondsLegacy': bondsLegacy,
        'discoveriesLegacy': discoveriesLegacy,
        if (impacts.isNotEmpty) 'impacts': impacts.toList(),
        if (vows.isNotEmpty) 'vows': vows.map((v) => v.toJson()).toList(),
        if (connections.isNotEmpty)
          'connections': connections.map((c) => c.toJson()).toList(),
        if (assets.isNotEmpty) 'assets': assets.map((a) => a.toJson()).toList(),
        if (assetRuleset != 'starforged') 'assetRuleset': assetRuleset,
      };

  static StarforgedSheet? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    List<ProgressTrack> tracks(dynamic v) => v is List
        ? v.map(ProgressTrack.maybeFromJson).whereType<ProgressTrack>().toList()
        : const [];
    final imp = j['impacts'] is List
        ? (j['impacts'] as List)
            .whereType<String>()
            .where(kStarforgedImpacts.containsKey)
            .toSet()
        : <String>{};
    final maxM = 10 - imp.length;
    return StarforgedSheet(
      edge: _intOr(j['edge'], 1).clamp(1, 3),
      heart: _intOr(j['heart'], 1).clamp(1, 3),
      iron: _intOr(j['iron'], 1).clamp(1, 3),
      shadow: _intOr(j['shadow'], 1).clamp(1, 3),
      wits: _intOr(j['wits'], 1).clamp(1, 3),
      health: _intOr(j['health'], 5).clamp(0, 5),
      spirit: _intOr(j['spirit'], 5).clamp(0, 5),
      supply: _intOr(j['supply'], 5).clamp(0, 5),
      momentum: _intOr(j['momentum'], 2).clamp(-6, maxM),
      xpEarned: _intOr(j['xpEarned'], 0).clamp(0, 1 << 31),
      xpSpent: _intOr(j['xpSpent'], 0).clamp(0, 1 << 31),
      questsLegacy: _intOr(j['questsLegacy'], 0).clamp(0, 10),
      bondsLegacy: _intOr(j['bondsLegacy'], 0).clamp(0, 10),
      discoveriesLegacy: _intOr(j['discoveriesLegacy'], 0).clamp(0, 10),
      impacts: imp,
      vows: tracks(j['vows']),
      connections: tracks(j['connections']),
      assets: j['assets'] is List
          ? (j['assets'] as List)
              .map(AssetState.maybeFromJson)
              .whereType<AssetState>()
              .toList()
          : const [],
      assetRuleset: _validRuleset(j['assetRuleset'] is String
          ? j['assetRuleset'] as String
          : 'starforged'),
    );
  }
}

// --- D&D 5e (SRD 5.1 game-mechanic facts only; no SRD prose) ---------------

const kDndClasses = <String>[
  'Barbarian',
  'Bard',
  'Cleric',
  'Druid',
  'Fighter',
  'Monk',
  'Paladin',
  'Ranger',
  'Rogue',
  'Sorcerer',
  'Warlock',
  'Wizard',
];

const kDndClassHitDie = <String, int>{
  'Barbarian': 12,
  'Fighter': 10,
  'Paladin': 10,
  'Ranger': 10,
  'Bard': 8,
  'Cleric': 8,
  'Druid': 8,
  'Monk': 8,
  'Rogue': 8,
  'Warlock': 8,
  'Sorcerer': 6,
  'Wizard': 6,
};

const kDndClassSaves = <String, Set<String>>{
  'Barbarian': {'str', 'con'},
  'Fighter': {'str', 'con'},
  'Cleric': {'wis', 'cha'},
  'Paladin': {'wis', 'cha'},
  'Warlock': {'wis', 'cha'},
  'Sorcerer': {'con', 'cha'},
  'Bard': {'dex', 'cha'},
  'Monk': {'str', 'dex'},
  'Ranger': {'str', 'dex'},
  'Rogue': {'dex', 'int'},
  'Druid': {'int', 'wis'},
  'Wizard': {'int', 'wis'},
};

const kDndAbilities = <String>['str', 'dex', 'con', 'int', 'wis', 'cha'];
const kDndAbilityLabels = <String, String>{
  'str': 'STR',
  'dex': 'DEX',
  'con': 'CON',
  'int': 'INT',
  'wis': 'WIS',
  'cha': 'CHA',
};

/// 18 skills as (id, label, governing-ability) in sheet order.
const kDndSkills = <(String, String, String)>[
  ('athletics', 'Athletics', 'str'),
  ('acrobatics', 'Acrobatics', 'dex'),
  ('sleight_of_hand', 'Sleight of Hand', 'dex'),
  ('stealth', 'Stealth', 'dex'),
  ('arcana', 'Arcana', 'int'),
  ('history', 'History', 'int'),
  ('investigation', 'Investigation', 'int'),
  ('nature', 'Nature', 'int'),
  ('religion', 'Religion', 'int'),
  ('animal_handling', 'Animal Handling', 'wis'),
  ('insight', 'Insight', 'wis'),
  ('medicine', 'Medicine', 'wis'),
  ('perception', 'Perception', 'wis'),
  ('survival', 'Survival', 'wis'),
  ('deception', 'Deception', 'cha'),
  ('intimidation', 'Intimidation', 'cha'),
  ('performance', 'Performance', 'cha'),
  ('persuasion', 'Persuasion', 'cha'),
];

const kDndSkillAbility = <String, String>{
  'athletics': 'str',
  'acrobatics': 'dex',
  'sleight_of_hand': 'dex',
  'stealth': 'dex',
  'arcana': 'int',
  'history': 'int',
  'investigation': 'int',
  'nature': 'int',
  'religion': 'int',
  'animal_handling': 'wis',
  'insight': 'wis',
  'medicine': 'wis',
  'perception': 'wis',
  'survival': 'wis',
  'deception': 'cha',
  'intimidation': 'cha',
  'performance': 'cha',
  'persuasion': 'cha',
};

const kDndConditions = <String, String>{
  'blinded': 'Blinded',
  'charmed': 'Charmed',
  'deafened': 'Deafened',
  'frightened': 'Frightened',
  'grappled': 'Grappled',
  'incapacitated': 'Incapacitated',
  'invisible': 'Invisible',
  'paralyzed': 'Paralyzed',
  'petrified': 'Petrified',
  'poisoned': 'Poisoned',
  'prone': 'Prone',
  'restrained': 'Restrained',
  'stunned': 'Stunned',
  'unconscious': 'Unconscious',
};

const kDndProfBonusByLevel = <int>[
  2,
  2,
  2,
  2,
  3,
  3,
  3,
  3,
  4,
  4,
  4,
  4,
  5,
  5,
  5,
  5,
  6,
  6,
  6,
  6,
];

/// SRD caster classes → spellcasting ability id. Non-casters (Fighter,
/// Barbarian, Monk, Rogue) are absent.
const kDndSpellcastingAbility = <String, String>{
  'Bard': 'cha',
  'Sorcerer': 'cha',
  'Warlock': 'cha',
  'Paladin': 'cha',
  'Cleric': 'wis',
  'Druid': 'wis',
  'Ranger': 'wis',
  'Wizard': 'int',
};
const kDndFullCasterClasses = <String>{
  'Bard',
  'Cleric',
  'Druid',
  'Sorcerer',
  'Wizard',
};
const kDndHalfCasterClasses = <String>{'Paladin', 'Ranger'};

/// Full-caster spell slots: row = character level 1..20, columns = spell
/// levels 1..9.
const kDndFullCasterSlots = <List<int>>[
  [2, 0, 0, 0, 0, 0, 0, 0, 0],
  [3, 0, 0, 0, 0, 0, 0, 0, 0],
  [4, 2, 0, 0, 0, 0, 0, 0, 0],
  [4, 3, 0, 0, 0, 0, 0, 0, 0],
  [4, 3, 2, 0, 0, 0, 0, 0, 0],
  [4, 3, 3, 0, 0, 0, 0, 0, 0],
  [4, 3, 3, 1, 0, 0, 0, 0, 0],
  [4, 3, 3, 2, 0, 0, 0, 0, 0],
  [4, 3, 3, 3, 1, 0, 0, 0, 0],
  [4, 3, 3, 3, 2, 0, 0, 0, 0],
  [4, 3, 3, 3, 2, 1, 0, 0, 0],
  [4, 3, 3, 3, 2, 1, 0, 0, 0],
  [4, 3, 3, 3, 2, 1, 1, 0, 0],
  [4, 3, 3, 3, 2, 1, 1, 0, 0],
  [4, 3, 3, 3, 2, 1, 1, 1, 0],
  [4, 3, 3, 3, 2, 1, 1, 1, 0],
  [4, 3, 3, 3, 2, 1, 1, 1, 1],
  [4, 3, 3, 3, 3, 1, 1, 1, 1],
  [4, 3, 3, 3, 3, 2, 1, 1, 1],
  [4, 3, 3, 3, 3, 2, 2, 1, 1],
];

/// Half-caster spell slots (Paladin/Ranger): row = level 1..20, columns =
/// spell levels 1..5.
const kDndHalfCasterSlots = <List<int>>[
  [0, 0, 0, 0, 0],
  [2, 0, 0, 0, 0],
  [3, 0, 0, 0, 0],
  [3, 0, 0, 0, 0],
  [4, 2, 0, 0, 0],
  [4, 2, 0, 0, 0],
  [4, 3, 0, 0, 0],
  [4, 3, 0, 0, 0],
  [4, 3, 2, 0, 0],
  [4, 3, 2, 0, 0],
  [4, 3, 3, 0, 0],
  [4, 3, 3, 0, 0],
  [4, 3, 3, 1, 0],
  [4, 3, 3, 1, 0],
  [4, 3, 3, 2, 0],
  [4, 3, 3, 2, 0],
  [4, 3, 3, 3, 1],
  [4, 3, 3, 3, 1],
  [4, 3, 3, 3, 2],
  [4, 3, 3, 3, 2],
];

/// Warlock Pact Magic: row = level 1..20 → (slot count, slot spell-level).
const kDndPactSlots = <(int, int)>[
  (1, 1),
  (2, 1),
  (2, 2),
  (2, 2),
  (2, 3),
  (2, 3),
  (2, 4),
  (2, 4),
  (2, 5),
  (2, 5),
  (3, 5),
  (3, 5),
  (3, 5),
  (3, 5),
  (3, 5),
  (3, 5),
  (4, 5),
  (4, 5),
  (4, 5),
  (4, 5),
];

/// Bespoke D&D 5e (P1) sheet. Additive on [Character] like [IronswornSheet].
class DndSheet {
  const DndSheet({
    this.abilities = const {
      'str': 10,
      'dex': 10,
      'con': 10,
      'int': 10,
      'wis': 10,
      'cha': 10
    },
    this.className = 'Fighter',
    this.subclass = '',
    this.level = 1,
    this.race = '',
    this.background = '',
    this.alignment = '',
    this.ac = 10,
    this.currentHp = 1,
    this.maxHp = 1,
    this.tempHp = 0,
    this.hitDiceRemaining = 1,
    this.speed = 30,
    this.initiativeOverride = 0,
    this.saveProficiencies = const {},
    this.skillProficiencies = const {},
    this.skillExpertise = const {},
    this.conditions = const {},
    this.exhaustionLevel = 0,
    this.deathSaveSuccesses = 0,
    this.deathSaveFailures = 0,
    this.inspiration = false,
    this.xp = 0,
    this.featuresText = '',
    this.spellSlotsUsed = const [0, 0, 0, 0, 0, 0, 0, 0, 0],
    this.pactSlotsUsed = 0,
    this.preparedSpells = '',
    this.spellIds = const [],
  });

  final Map<String, int> abilities; // keys = kDndAbilities, each 1..30
  final String className, subclass, race, background, alignment;
  final int level; // 1..20
  final int ac, currentHp, maxHp, tempHp, hitDiceRemaining, speed;
  final int initiativeOverride; // 0 = use DEX mod
  final Set<String> saveProficiencies, skillProficiencies, skillExpertise;
  final Set<String> conditions;
  final int exhaustionLevel; // 0..6
  final int deathSaveSuccesses, deathSaveFailures; // 0..3
  final bool inspiration;
  final int xp;
  final String featuresText;
  final List<int> spellSlotsUsed; // length 9, expended per spell level
  final int pactSlotsUsed; // Warlock Pact Magic
  final String preparedSpells; // freeform
  final List<String> spellIds; // structured spell picks (content registry ids)

  int score(String a) => abilities[a] ?? 10;
  int abilityMod(String a) => ((score(a) - 10) / 2).floor();
  int get proficiencyBonus => kDndProfBonusByLevel[(level - 1).clamp(0, 19)];
  int get hitDie => kDndClassHitDie[className] ?? 8;
  int get initiative =>
      initiativeOverride != 0 ? initiativeOverride : abilityMod('dex');
  int saveBonus(String a) =>
      abilityMod(a) + (saveProficiencies.contains(a) ? proficiencyBonus : 0);
  int skillBonus(String id) {
    final ab = kDndSkillAbility[id] ?? 'str';
    final mult = skillExpertise.contains(id)
        ? 2
        : (skillProficiencies.contains(id) ? 1 : 0);
    return abilityMod(ab) + proficiencyBonus * mult;
  }

  int get passivePerception => 10 + skillBonus('perception');

  bool get isCaster => kDndSpellcastingAbility.containsKey(className);
  String? get spellcastingAbility => kDndSpellcastingAbility[className];
  int? get spellcastingMod =>
      isCaster ? abilityMod(spellcastingAbility!) : null;
  int? get spellSaveDC =>
      isCaster ? 8 + proficiencyBonus + spellcastingMod! : null;
  int? get spellAttackBonus =>
      isCaster ? proficiencyBonus + spellcastingMod! : null;

  /// Max slots at [spellLevel] (1..9) from the class's table; 0 if none.
  /// Warlock uses pact magic instead and returns 0 here.
  int slotMax(int spellLevel) {
    final row = (level - 1).clamp(0, 19);
    if (kDndFullCasterClasses.contains(className)) {
      return (spellLevel >= 1 && spellLevel <= 9)
          ? kDndFullCasterSlots[row][spellLevel - 1]
          : 0;
    }
    if (kDndHalfCasterClasses.contains(className)) {
      return (spellLevel >= 1 && spellLevel <= 5)
          ? kDndHalfCasterSlots[row][spellLevel - 1]
          : 0;
    }
    return 0;
  }

  int get pactSlotCount =>
      className == 'Warlock' ? kDndPactSlots[(level - 1).clamp(0, 19)].$1 : 0;
  int get pactSlotLevel =>
      className == 'Warlock' ? kDndPactSlots[(level - 1).clamp(0, 19)].$2 : 0;

  /// Normalize an expended-slots list to exactly 9 non-negative ints.
  static List<int> _normSlots(List<int> v) => [
        for (var i = 0; i < 9; i++)
          (i < v.length ? v[i] : 0).clamp(0, kFieldClampMax)
      ];

  factory DndSheet.premade() => const DndSheet(
        abilities: {
          'str': 15,
          'dex': 13,
          'con': 14,
          'int': 8,
          'wis': 12,
          'cha': 10
        },
        className: 'Fighter',
        level: 1,
        ac: 16,
        currentHp: 12, // d10 max (10) + CON mod (+2)
        maxHp: 12,
        hitDiceRemaining: 1,
        speed: 30,
        saveProficiencies: {'str', 'con'},
        skillProficiencies: {'athletics', 'perception'},
      );

  DndSheet copyWith({
    Map<String, int>? abilities,
    String? className,
    String? subclass,
    String? race,
    String? background,
    String? alignment,
    int? level,
    int? ac,
    int? currentHp,
    int? maxHp,
    int? tempHp,
    int? hitDiceRemaining,
    int? speed,
    int? initiativeOverride,
    Set<String>? saveProficiencies,
    Set<String>? skillProficiencies,
    Set<String>? skillExpertise,
    Set<String>? conditions,
    int? exhaustionLevel,
    int? deathSaveSuccesses,
    int? deathSaveFailures,
    bool? inspiration,
    int? xp,
    String? featuresText,
    List<int>? spellSlotsUsed,
    int? pactSlotsUsed,
    String? preparedSpells,
    List<String>? spellIds,
  }) {
    final lvl = (level ?? this.level).clamp(1, 20);
    final ab = abilities ?? this.abilities;
    final cls = (className ?? this.className);
    return DndSheet(
      abilities: {
        for (final a in kDndAbilities) a: (ab[a] ?? 10).clamp(1, 30),
      },
      className: kDndClassHitDie.containsKey(cls) ? cls : 'Fighter',
      subclass: subclass ?? this.subclass,
      race: race ?? this.race,
      background: background ?? this.background,
      alignment: alignment ?? this.alignment,
      level: lvl,
      ac: (ac ?? this.ac).clamp(0, 99),
      currentHp: (currentHp ?? this.currentHp).clamp(0, kFieldClampMax),
      maxHp: (maxHp ?? this.maxHp).clamp(0, kFieldClampMax),
      tempHp: (tempHp ?? this.tempHp).clamp(0, kFieldClampMax),
      hitDiceRemaining:
          (hitDiceRemaining ?? this.hitDiceRemaining).clamp(0, lvl),
      speed: (speed ?? this.speed).clamp(0, 999),
      initiativeOverride: initiativeOverride ?? this.initiativeOverride,
      saveProficiencies: (saveProficiencies ?? this.saveProficiencies)
          .where(kDndAbilities.contains)
          .toSet(),
      skillProficiencies: (skillProficiencies ?? this.skillProficiencies)
          .where(kDndSkillAbility.containsKey)
          .toSet(),
      skillExpertise: (skillExpertise ?? this.skillExpertise)
          .where(kDndSkillAbility.containsKey)
          .toSet(),
      conditions: (conditions ?? this.conditions)
          .where(kDndConditions.containsKey)
          .toSet(),
      exhaustionLevel: (exhaustionLevel ?? this.exhaustionLevel).clamp(0, 6),
      deathSaveSuccesses:
          (deathSaveSuccesses ?? this.deathSaveSuccesses).clamp(0, 3),
      deathSaveFailures:
          (deathSaveFailures ?? this.deathSaveFailures).clamp(0, 3),
      inspiration: inspiration ?? this.inspiration,
      xp: (xp ?? this.xp).clamp(0, 1 << 31),
      featuresText: featuresText ?? this.featuresText,
      spellSlotsUsed: _normSlots(spellSlotsUsed ?? this.spellSlotsUsed),
      pactSlotsUsed:
          (pactSlotsUsed ?? this.pactSlotsUsed).clamp(0, kFieldClampMax),
      preparedSpells: preparedSpells ?? this.preparedSpells,
      spellIds: spellIds ?? this.spellIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'abilities': abilities,
        'className': className,
        if (subclass.isNotEmpty) 'subclass': subclass,
        'level': level,
        if (race.isNotEmpty) 'race': race,
        if (background.isNotEmpty) 'background': background,
        if (alignment.isNotEmpty) 'alignment': alignment,
        'ac': ac,
        'currentHp': currentHp,
        'maxHp': maxHp,
        if (tempHp != 0) 'tempHp': tempHp,
        'hitDiceRemaining': hitDiceRemaining,
        'speed': speed,
        if (initiativeOverride != 0) 'initiativeOverride': initiativeOverride,
        if (saveProficiencies.isNotEmpty)
          'saveProficiencies': saveProficiencies.toList(),
        if (skillProficiencies.isNotEmpty)
          'skillProficiencies': skillProficiencies.toList(),
        if (skillExpertise.isNotEmpty)
          'skillExpertise': skillExpertise.toList(),
        if (conditions.isNotEmpty) 'conditions': conditions.toList(),
        if (exhaustionLevel != 0) 'exhaustionLevel': exhaustionLevel,
        if (deathSaveSuccesses != 0) 'deathSaveSuccesses': deathSaveSuccesses,
        if (deathSaveFailures != 0) 'deathSaveFailures': deathSaveFailures,
        if (inspiration) 'inspiration': true,
        if (xp != 0) 'xp': xp,
        if (featuresText.isNotEmpty) 'featuresText': featuresText,
        if (spellSlotsUsed.any((x) => x != 0)) 'spellSlotsUsed': spellSlotsUsed,
        if (pactSlotsUsed != 0) 'pactSlotsUsed': pactSlotsUsed,
        if (preparedSpells.isNotEmpty) 'preparedSpells': preparedSpells,
        if (spellIds.isNotEmpty) 'spellIds': spellIds,
      };

  static DndSheet? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    final rawAb = j['abilities'];
    final ab = <String, int>{
      for (final a in kDndAbilities)
        a: (rawAb is Map ? _intOr(rawAb[a], 10) : 10).clamp(1, 30),
    };
    final cls = _strOr(j['className']);
    return DndSheet(
      abilities: ab,
      className: kDndClassHitDie.containsKey(cls) ? cls : 'Fighter',
      subclass: _strOr(j['subclass']),
      race: _strOr(j['race']),
      background: _strOr(j['background']),
      alignment: _strOr(j['alignment']),
      level: _intOr(j['level'], 1).clamp(1, 20),
      ac: _intOr(j['ac'], 10).clamp(0, 99),
      currentHp: _intOr(j['currentHp'], 1).clamp(0, kFieldClampMax),
      maxHp: _intOr(j['maxHp'], 1).clamp(0, kFieldClampMax),
      tempHp: _intOr(j['tempHp'], 0).clamp(0, kFieldClampMax),
      hitDiceRemaining: _intOr(j['hitDiceRemaining'], 1)
          .clamp(0, _intOr(j['level'], 1).clamp(1, 20)),
      speed: _intOr(j['speed'], 30).clamp(0, 999),
      initiativeOverride: _intOr(j['initiativeOverride'], 0),
      saveProficiencies:
          _strSet(j['saveProficiencies']).where(kDndAbilities.contains).toSet(),
      skillProficiencies: _strSet(j['skillProficiencies'])
          .where(kDndSkillAbility.containsKey)
          .toSet(),
      skillExpertise: _strSet(j['skillExpertise'])
          .where(kDndSkillAbility.containsKey)
          .toSet(),
      conditions:
          _strSet(j['conditions']).where(kDndConditions.containsKey).toSet(),
      exhaustionLevel: _intOr(j['exhaustionLevel'], 0).clamp(0, 6),
      deathSaveSuccesses: _intOr(j['deathSaveSuccesses'], 0).clamp(0, 3),
      deathSaveFailures: _intOr(j['deathSaveFailures'], 0).clamp(0, 3),
      inspiration: j['inspiration'] == true,
      xp: _intOr(j['xp'], 0).clamp(0, 1 << 31),
      featuresText: _strOr(j['featuresText']),
      spellSlotsUsed: _normSlots(j['spellSlotsUsed'] is List
          ? [for (final x in j['spellSlotsUsed'] as List) x is int ? x : 0]
          : const []),
      pactSlotsUsed: _intOr(j['pactSlotsUsed'], 0).clamp(0, kFieldClampMax),
      preparedSpells: _strOr(j['preparedSpells']),
      spellIds: ((j['spellIds'] as List?) ?? const []).cast<String>(),
    );
  }
}

// --- Nimble (facts-only: authored class/stat names only) --------------------

const kNimbleStats = <String>['str', 'dex', 'int', 'wis'];
const kNimbleClasses = <String>[
  'The Cheat',
  'Commander',
  'Hunter',
  'Mage',
  'Oathsworn',
  'Shadowmancer',
  'Shepherd',
  'Songweaver',
  'Stormshifter',
  'Zephyr',
];

/// Facts-only Nimble sheet. Authored class/stat NAMES only (non-copyrightable);
/// all values are player-editable. Stats are MODIFIERS (small ± numbers).
class NimbleSheet {
  const NimbleSheet({
    this.stats = const {'str': 0, 'dex': 0, 'int': 0, 'wis': 0},
    this.saveAdv = const {},
    this.className = 'The Cheat',
    this.ancestry = '',
    this.level = 1,
    this.hitDieSize = 6,
    this.maxHp = 1,
    this.currentHp = 1,
    this.wounds = 0,
    this.maxWounds = 6,
    this.speed = 6,
    this.gearSlotsUsed = 0,
    this.talents = '',
    this.notes = '',
  });

  final Map<String, int> stats; // keys = kNimbleStats; values are modifiers
  final Map<String, int> saveAdv; // per stat: 1 adv / -1 dis / 0 none
  final String className, ancestry;
  final int level,
      hitDieSize,
      maxHp,
      currentHp,
      wounds,
      maxWounds,
      speed,
      gearSlotsUsed;
  final String talents, notes;

  int get slotCap => 10 + (stats['str'] ?? 0);

  NimbleSheet copyWith({
    Map<String, int>? stats,
    Map<String, int>? saveAdv,
    String? className,
    String? ancestry,
    int? level,
    int? hitDieSize,
    int? maxHp,
    int? currentHp,
    int? wounds,
    int? maxWounds,
    int? speed,
    int? gearSlotsUsed,
    String? talents,
    String? notes,
  }) {
    final st = stats ?? this.stats;
    final sv = saveAdv ?? this.saveAdv;
    final cls = className ?? this.className;
    return NimbleSheet(
      stats: {for (final k in kNimbleStats) k: (st[k] ?? 0).clamp(-9, 9)},
      saveAdv: {
        for (final k in kNimbleStats)
          if ((sv[k] ?? 0) != 0) k: (sv[k] ?? 0).clamp(-1, 1),
      },
      className: kNimbleClasses.contains(cls) ? cls : 'The Cheat',
      ancestry: ancestry ?? this.ancestry,
      level: (level ?? this.level).clamp(1, 10),
      hitDieSize: (hitDieSize ?? this.hitDieSize).clamp(1, 100),
      maxHp: (maxHp ?? this.maxHp).clamp(0, kFieldClampMax),
      currentHp: (currentHp ?? this.currentHp).clamp(0, kFieldClampMax),
      wounds: (wounds ?? this.wounds).clamp(0, 99),
      maxWounds: (maxWounds ?? this.maxWounds).clamp(1, 99),
      speed: (speed ?? this.speed).clamp(0, 99),
      gearSlotsUsed: (gearSlotsUsed ?? this.gearSlotsUsed).clamp(0, 999),
      talents: talents ?? this.talents,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'stats': stats,
        if (saveAdv.isNotEmpty) 'saveAdv': saveAdv,
        'className': className,
        'ancestry': ancestry,
        'level': level,
        'hitDieSize': hitDieSize,
        'maxHp': maxHp,
        'currentHp': currentHp,
        'wounds': wounds,
        'maxWounds': maxWounds,
        'speed': speed,
        'gearSlotsUsed': gearSlotsUsed,
        'talents': talents,
        'notes': notes,
      };

  static NimbleSheet? maybeFromJson(Object? j) {
    if (j is! Map) return null;
    int i(String k, int d) => (j[k] as num?)?.toInt() ?? d;
    Map<String, int> intMap(String k) => {
          for (final e in ((j[k] as Map?) ?? const {}).entries)
            '${e.key}': (e.value as num?)?.toInt() ?? 0,
        };
    return const NimbleSheet().copyWith(
      stats: intMap('stats'),
      saveAdv: intMap('saveAdv'),
      className: j['className'] as String?,
      ancestry: j['ancestry'] as String?,
      level: i('level', 1),
      hitDieSize: i('hitDieSize', 6),
      maxHp: i('maxHp', 1),
      currentHp: i('currentHp', 1),
      wounds: i('wounds', 0),
      maxWounds: i('maxWounds', 6),
      speed: i('speed', 6),
      gearSlotsUsed: i('gearSlotsUsed', 0),
      talents: j['talents'] as String?,
      notes: j['notes'] as String?,
    );
  }
}

// --- Draw Steel (facts-only: class/characteristic NAMES only; published under
// the Draw Steel Creator License — not affiliated with MCDM Productions, LLC)

const kDrawSteelCharacteristics = <String>[
  'might',
  'agility',
  'reason',
  'intuition',
  'presence',
];

/// The nine classes from Draw Steel: Heroes (MCDM Productions).
/// Verified against https://steelcompendium.io (Steel Compendium).
const kDrawSteelClasses = <String>[
  'Censor',
  'Conduit',
  'Elementalist',
  'Fury',
  'Null',
  'Shadow',
  'Tactician',
  'Talent',
  'Troubadour',
];

/// Heroic resource name per class. Verified against Steel Compendium class pages.
const kDrawSteelHeroicResource = <String, String>{
  'Censor': 'Wrath',
  'Conduit': 'Piety',
  'Elementalist': 'Essence',
  'Fury': 'Ferocity',
  'Null': 'Discipline',
  'Shadow': 'Insight',
  'Tactician': 'Focus',
  'Talent': 'Clarity',
  'Troubadour': 'Drama',
};

class DrawSteelSheet {
  const DrawSteelSheet({
    this.className = 'Censor',
    this.ancestry = '',
    this.level = 1,
    this.characteristics = const {
      'might': 0,
      'agility': 0,
      'reason': 0,
      'intuition': 0,
      'presence': 0,
    },
    this.maxStamina = 1,
    this.currentStamina = 1,
    this.recoveries = 0,
    this.maxRecoveries = 0,
    this.stability = 0,
    this.heroicResource = 0,
    this.skills = '',
    this.notes = '',
  });

  final String className;
  final String ancestry;
  final int level;
  final Map<String, int> characteristics;
  final int maxStamina;
  final int currentStamina;
  final int recoveries;
  final int maxRecoveries;
  final int stability;
  final int heroicResource;
  final String skills;
  final String notes;

  String get resourceLabel => kDrawSteelHeroicResource[className] ?? 'Resource';

  DrawSteelSheet copyWith({
    String? className,
    String? ancestry,
    int? level,
    Map<String, int>? characteristics,
    int? maxStamina,
    int? currentStamina,
    int? recoveries,
    int? maxRecoveries,
    int? stability,
    int? heroicResource,
    String? skills,
    String? notes,
  }) {
    final cls = className ?? this.className;
    final ms = (maxStamina ?? this.maxStamina).clamp(0, kFieldClampMax);
    final ch = characteristics ?? this.characteristics;
    return DrawSteelSheet(
      className:
          kDrawSteelClasses.contains(cls) ? cls : kDrawSteelClasses.first,
      ancestry: ancestry ?? this.ancestry,
      level: (level ?? this.level).clamp(1, 10),
      characteristics: {
        for (final k in kDrawSteelCharacteristics) k: (ch[k] ?? 0).clamp(-5, 5),
      },
      maxStamina: ms,
      currentStamina: (currentStamina ?? this.currentStamina).clamp(0, ms),
      recoveries: (recoveries ?? this.recoveries).clamp(0, kFieldClampMax),
      maxRecoveries:
          (maxRecoveries ?? this.maxRecoveries).clamp(0, kFieldClampMax),
      stability: (stability ?? this.stability).clamp(0, 99),
      heroicResource:
          (heroicResource ?? this.heroicResource).clamp(0, kFieldClampMax),
      skills: skills ?? this.skills,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'className': className,
        'ancestry': ancestry,
        'level': level,
        'characteristics': characteristics,
        'maxStamina': maxStamina,
        'currentStamina': currentStamina,
        'recoveries': recoveries,
        'maxRecoveries': maxRecoveries,
        'stability': stability,
        'heroicResource': heroicResource,
        if (skills.isNotEmpty) 'skills': skills,
        if (notes.isNotEmpty) 'notes': notes,
      };

  static DrawSteelSheet? maybeFromJson(Object? j) {
    if (j is! Map) return null;
    int i(String k, int d) => (j[k] as num?)?.toInt() ?? d;
    Map<String, int> intMap(String k) => {
          for (final e in ((j[k] as Map?) ?? const {}).entries)
            '${e.key}': (e.value as num?)?.toInt() ?? 0,
        };
    return const DrawSteelSheet().copyWith(
      className: j['className'] as String?,
      ancestry: j['ancestry'] as String?,
      level: i('level', 1),
      characteristics: intMap('characteristics'),
      maxStamina: i('maxStamina', 1),
      currentStamina: i('currentStamina', 1),
      recoveries: i('recoveries', 0),
      maxRecoveries: i('maxRecoveries', 0),
      stability: i('stability', 0),
      heroicResource: i('heroicResource', 0),
      skills: j['skills'] as String?,
      notes: j['notes'] as String?,
    );
  }
}

// ── Tales of Argosa ──────────────────────────────────────────────────────────

const kArgosaStats = <String>['str', 'dex', 'con', 'int', 'per', 'wil', 'cha'];

const kArgosaStatLabels = <String, String>{
  'str': 'Strength',
  'dex': 'Dexterity',
  'con': 'Constitution',
  'int': 'Intelligence',
  'per': 'Perception',
  'wil': 'Willpower',
  'cha': 'Charisma',
};

const kArgosaClasses = <String>[
  'Artificer',
  'Barbarian',
  'Bard',
  'Cultist',
  'Fighter',
  'Magic-User',
  'Monk',
  'Ranger',
  'Rogue',
];

class ArgosaSheet {
  const ArgosaSheet({
    this.className = 'Fighter',
    this.level = 1,
    this.stats = const {
      'str': 10,
      'dex': 10,
      'con': 10,
      'int': 10,
      'per': 10,
      'wil': 10,
      'cha': 10,
    },
    this.maxHp = 1,
    this.currentHp = 1,
    this.luck = 11,
    this.rescues = 0,
    this.skills = '',
    this.notes = '',
  });

  final String className;
  final int level;
  final Map<String, int> stats;
  final int maxHp;
  final int currentHp;
  final int luck;
  final int rescues;
  final String skills;
  final String notes;

  int get resetLuck => 10 + (level / 2).ceil();

  ArgosaSheet copyWith({
    String? className,
    int? level,
    Map<String, int>? stats,
    int? maxHp,
    int? currentHp,
    int? luck,
    int? rescues,
    String? skills,
    String? notes,
  }) {
    final cls = className ?? this.className;
    final mh = (maxHp ?? this.maxHp).clamp(0, kFieldClampMax);
    final st = stats ?? this.stats;
    return ArgosaSheet(
      className: kArgosaClasses.contains(cls) ? cls : kArgosaClasses.first,
      level: (level ?? this.level).clamp(1, 9),
      stats: {
        for (final k in kArgosaStats)
          k: ((st[k] ?? 10) as num).round().clamp(3, 18),
      },
      maxHp: mh,
      currentHp: (currentHp ?? this.currentHp).clamp(0, mh),
      luck: (luck ?? this.luck).clamp(0, 99),
      rescues: (rescues ?? this.rescues).clamp(0, 99),
      skills: skills ?? this.skills,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'className': className,
        'level': level,
        'stats': stats,
        'maxHp': maxHp,
        'currentHp': currentHp,
        'luck': luck,
        'rescues': rescues,
        'skills': skills,
        'notes': notes,
      };

  static ArgosaSheet? maybeFromJson(dynamic j) {
    if (j is! Map<String, dynamic>) return null;
    final st = (j['stats'] as Map?) ?? {};
    return ArgosaSheet(
      className: kArgosaClasses.contains(j['className'])
          ? j['className'] as String
          : kArgosaClasses.first,
      level: ((j['level'] as num?)?.round() ?? 1).clamp(1, 9),
      stats: {
        for (final k in kArgosaStats)
          k: ((st[k] ?? 10) as num).round().clamp(3, 18),
      },
      maxHp: (j['maxHp'] as num?)?.round() ?? 1,
      currentHp: (j['currentHp'] as num?)?.round() ?? 1,
      luck: ((j['luck'] as num?)?.round() ?? 11).clamp(0, 99),
      rescues: ((j['rescues'] as num?)?.round() ?? 0).clamp(0, 99),
      skills: j['skills'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
    );
  }
}

// ── Cairn ────────────────────────────────────────────────────────────────────

const kCairnStats = <String>['str', 'dex', 'wil'];

const kCairnStatLabels = <String, String>{
  'str': 'STR',
  'dex': 'DEX',
  'wil': 'WIL',
};

const kCairnBackgrounds = <String>[
  'Alchemist',
  'Blacksmith',
  'Burglar',
  'Butcher',
  'Carpenter',
  'Cleric',
  'Gambler',
  'Gravedigger',
  'Herbalist',
  'Hunter',
  'Magician',
  'Mercenary',
  'Merchant',
  'Miner',
  'Outlaw',
  'Performer',
  'Pickpocket',
  'Ranger',
  'Servant',
  'Smuggler',
];

class CairnSheet {
  const CairnSheet({
    this.background = 'Hunter',
    this.str = 10,
    this.dex = 10,
    this.wil = 10,
    this.maxHp = 4,
    this.currentHp = 4,
    this.armor = 0,
    this.deprived = false,
    this.fatigue = 0,
    this.coins = '',
    this.notes = '',
  });

  final String background;
  final int str;
  final int dex;
  final int wil;
  final int maxHp;
  final int currentHp;
  final int armor;
  final bool deprived;
  final int fatigue;
  final String coins;
  final String notes;

  CairnSheet copyWith({
    String? background,
    int? str,
    int? dex,
    int? wil,
    int? maxHp,
    int? currentHp,
    int? armor,
    bool? deprived,
    int? fatigue,
    String? coins,
    String? notes,
  }) {
    final bg = background ?? this.background;
    final mh = (maxHp ?? this.maxHp).clamp(0, kFieldClampMax);
    return CairnSheet(
      background: kCairnBackgrounds.contains(bg) ? bg : kCairnBackgrounds.first,
      str: (str ?? this.str).clamp(3, 18),
      dex: (dex ?? this.dex).clamp(3, 18),
      wil: (wil ?? this.wil).clamp(3, 18),
      maxHp: mh,
      currentHp: (currentHp ?? this.currentHp).clamp(0, mh),
      armor: (armor ?? this.armor).clamp(0, 3),
      deprived: deprived ?? this.deprived,
      fatigue: (fatigue ?? this.fatigue).clamp(0, 10),
      coins: coins ?? this.coins,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'background': background,
        'str': str,
        'dex': dex,
        'wil': wil,
        'maxHp': maxHp,
        'currentHp': currentHp,
        'armor': armor,
        'deprived': deprived,
        'fatigue': fatigue,
        'coins': coins,
        'notes': notes,
      };

  static CairnSheet? maybeFromJson(dynamic j) {
    if (j is! Map<String, dynamic>) return null;
    final bg = j['background'] as String?;
    return CairnSheet(
      background:
          kCairnBackgrounds.contains(bg) ? bg! : kCairnBackgrounds.first,
      str: ((j['str'] as num?)?.round() ?? 10).clamp(3, 18),
      dex: ((j['dex'] as num?)?.round() ?? 10).clamp(3, 18),
      wil: ((j['wil'] as num?)?.round() ?? 10).clamp(3, 18),
      maxHp: (j['maxHp'] as num?)?.round() ?? 4,
      currentHp: (j['currentHp'] as num?)?.round() ?? 4,
      armor: ((j['armor'] as num?)?.round() ?? 0).clamp(0, 3),
      deprived: j['deprived'] as bool? ?? false,
      fatigue: ((j['fatigue'] as num?)?.round() ?? 0).clamp(0, 10),
      coins: j['coins'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
    );
  }
}

// ── Knave ────────────────────────────────────────────────────────────────────

const kKnaveStats = <String>['str', 'dex', 'con', 'int', 'wis', 'cha'];

const kKnaveStatLabels = <String, String>{
  'str': 'STR',
  'dex': 'DEX',
  'con': 'CON',
  'int': 'INT',
  'wis': 'WIS',
  'cha': 'CHA',
};

class KnaveSheet {
  const KnaveSheet({
    this.career = '',
    this.stats = const {
      'str': 0,
      'dex': 0,
      'con': 0,
      'int': 0,
      'wis': 0,
      'cha': 0,
    },
    this.level = 1,
    this.maxHp = 4,
    this.currentHp = 4,
    this.wounds = 0,
    this.ac = 11,
    this.coins = '',
    this.notes = '',
  });

  final String career;
  final Map<String, int> stats;
  final int level;
  final int maxHp;
  final int currentHp;
  final int wounds;
  final int ac;
  final String coins;
  final String notes;

  int get inventorySlots => 10 + (stats['con'] ?? 0);

  KnaveSheet copyWith({
    String? career,
    Map<String, int>? stats,
    int? level,
    int? maxHp,
    int? currentHp,
    int? wounds,
    int? ac,
    String? coins,
    String? notes,
  }) {
    final mh = (maxHp ?? this.maxHp).clamp(0, kFieldClampMax);
    final st = stats ?? this.stats;
    return KnaveSheet(
      career: career ?? this.career,
      stats: {
        for (final k in kKnaveStats)
          k: ((st[k] ?? 0) as num).round().clamp(0, 10)
      },
      level: (level ?? this.level).clamp(1, 20),
      maxHp: mh,
      currentHp: (currentHp ?? this.currentHp).clamp(0, mh),
      wounds: (wounds ?? this.wounds).clamp(0, 99),
      ac: (ac ?? this.ac).clamp(0, 99),
      coins: coins ?? this.coins,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'career': career,
        'stats': stats,
        'level': level,
        'maxHp': maxHp,
        'currentHp': currentHp,
        'wounds': wounds,
        'ac': ac,
        'coins': coins,
        'notes': notes,
      };

  static KnaveSheet? maybeFromJson(dynamic j) {
    if (j is! Map<String, dynamic>) return null;
    final st = (j['stats'] as Map?) ?? {};
    return KnaveSheet(
      career: j['career'] as String? ?? '',
      stats: {
        for (final k in kKnaveStats)
          k: ((st[k] ?? 0) as num).round().clamp(0, 10),
      },
      level: ((j['level'] as num?)?.round() ?? 1).clamp(1, 20),
      maxHp: (j['maxHp'] as num?)?.round() ?? 4,
      currentHp: (j['currentHp'] as num?)?.round() ?? 4,
      wounds: ((j['wounds'] as num?)?.round() ?? 0).clamp(0, 99),
      ac: ((j['ac'] as num?)?.round() ?? 11).clamp(0, 99),
      coins: j['coins'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
    );
  }
}

// ── Old-School Essentials (B/X) ──────────────────────────────────────────────

const kOseStats = <String>['str', 'int', 'wis', 'dex', 'con', 'cha'];

const kOseStatLabels = <String, String>{
  'str': 'STR',
  'int': 'INT',
  'wis': 'WIS',
  'dex': 'DEX',
  'con': 'CON',
  'cha': 'CHA',
};

const kOseClasses = <String>[
  'Cleric',
  'Fighter',
  'Magic-User',
  'Thief',
  'Dwarf',
  'Elf',
  'Halfling',
];

const kOseSaveKeys = <String>[
  'death',
  'wands',
  'paralysis',
  'breath',
  'spells',
];

const kOseSaveLabels = <String, String>{
  'death': 'Death/Poison',
  'wands': 'Wands',
  'paralysis': 'Paralysis/Petrify',
  'breath': 'Breath',
  'spells': 'Spells/Rods/Staves',
};

const kOseAlignments = <String>['Lawful', 'Neutral', 'Chaotic'];

// --- Dungeon Crawl Classics (facts-only) ---------------------------------
const kDccClasses = <String>[
  'Warrior',
  'Wizard',
  'Cleric',
  'Thief',
  'Elf',
  'Dwarf',
  'Halfling',
];
const kDccClassHitDie = <String, int>{
  'Warrior': 12,
  'Wizard': 4,
  'Cleric': 8,
  'Thief': 6,
  'Elf': 6,
  'Dwarf': 10,
  'Halfling': 6,
};
const kDccAlignments = <String>['Lawful', 'Neutral', 'Chaotic'];
const kDccStats = <String>['str', 'agi', 'sta', 'per', 'int', 'lck'];
const kDccStatLabels = <String, String>{
  'str': 'STR',
  'agi': 'AGI',
  'sta': 'STA',
  'per': 'PER',
  'int': 'INT',
  'lck': 'LCK',
};
const kDccSaveKeys = <String>['fort', 'ref', 'wil'];
const kDccSaveLabels = <String, String>{
  'fort': 'Fortitude',
  'ref': 'Reflex',
  'wil': 'Will',
};
const kDccDeedDieClasses = <String>{'Warrior', 'Dwarf'};
const kDccCasterClasses = <String>{'Wizard', 'Elf', 'Cleric'};
const kDccSpellburnStats = <String, List<String>>{
  'Wizard': ['str', 'agi', 'sta'],
  'Elf': ['str', 'agi', 'sta'],
  'Cleric': ['per'],
};
const kDccActionDice = <String>['d20', 'd24', 'd30'];
const kDccDeedDice = <String>['d3', 'd4', 'd5', 'd6', 'd7'];

/// A Mighty Deed succeeds on a deed die of 3 or higher.
const int kDccDeedSuccessMin = 3;

/// DCC ability-modifier table (3-18, capped at +/-3). Distinct from the D&D 5e
/// `((score-10)/2).floor()` curve. Non-copyrightable game-mechanic fact.
int dccAbilityMod(int score) {
  final s = score.clamp(3, 18);
  if (s <= 3) return -3;
  if (s <= 5) return -2;
  if (s <= 8) return -1;
  if (s <= 12) return 0;
  if (s <= 15) return 1;
  if (s <= 17) return 2;
  return 3;
}

/// Bespoke Dungeon Crawl Classics sheet. Authors only game-mechanic facts
/// (stats, classes, hit dice, dice-chain values); occupation/spells/notes
/// are freeform.
class DccSheet {
  const DccSheet({
    this.className = 'Warrior',
    this.level = 1,
    this.alignment = 'Neutral',
    this.occupation = '',
    this.luckySign = '',
    this.stats = const {
      'str': 10,
      'agi': 10,
      'sta': 10,
      'per': 10,
      'int': 10,
      'lck': 10,
    },
    this.lckMax = 10,
    this.currentHp = 4,
    this.maxHp = 4,
    this.ac = 10,
    this.attackBonus = 0,
    this.actionDie = 'd20',
    this.initNote = '',
    this.saves = const {'fort': 0, 'ref': 0, 'wil': 0},
    this.deedDie = 'd3',
    this.burns = const {'str': 0, 'agi': 0, 'sta': 0, 'per': 0},
    this.disapprovalRange = 1,
    this.notes = '',
  });

  final String className, alignment, occupation, luckySign;
  final int level;
  final Map<String, int> stats; // kDccStats, each 3..18
  final int lckMax;
  final int currentHp, maxHp, ac, attackBonus;
  final String actionDie, initNote;
  final Map<String, int> saves; // kDccSaveKeys bonuses
  final String deedDie;
  final Map<String, int> burns; // spellburn per stat
  final int disapprovalRange;
  final String notes;

  int mod(String k) => dccAbilityMod(stats[k] ?? 10);
  int burned(String k) => burns[k] ?? 0;
  int effectiveScore(String k) => (stats[k] ?? 10) - burned(k);
  bool get hasDeedDie => kDccDeedDieClasses.contains(className);
  bool get isCaster => kDccCasterClasses.contains(className);
  bool get isCleric => className == 'Cleric';
  List<String> get burnableStats => kDccSpellburnStats[className] ?? const [];
  int get totalSpellburn => burnableStats.fold(0, (sum, k) => sum + burned(k));
  String? get castingStat => isCleric ? 'per' : (isCaster ? 'int' : null);

  /// Thieves and Halflings regain spent Luck on rest (shown as a sheet note).
  bool get luckyRecoveryClass =>
      className == 'Thief' || className == 'Halfling';

  factory DccSheet.premade() => const DccSheet();

  DccSheet copyWith({
    String? className,
    int? level,
    String? alignment,
    String? occupation,
    String? luckySign,
    Map<String, int>? stats,
    int? lckMax,
    int? currentHp,
    int? maxHp,
    int? ac,
    int? attackBonus,
    String? actionDie,
    String? initNote,
    Map<String, int>? saves,
    String? deedDie,
    Map<String, int>? burns,
    int? disapprovalRange,
    String? notes,
  }) {
    final mh = (maxHp ?? this.maxHp).clamp(0, kFieldClampMax);
    final st = stats ?? this.stats;
    final sv = saves ?? this.saves;
    final bn = burns ?? this.burns;
    final cls = className ?? this.className;
    return DccSheet(
      className: kDccClassHitDie.containsKey(cls) ? cls : 'Warrior',
      level: (level ?? this.level).clamp(1, 10),
      alignment: kDccAlignments.contains(alignment ?? this.alignment)
          ? (alignment ?? this.alignment)
          : 'Neutral',
      occupation: occupation ?? this.occupation,
      luckySign: luckySign ?? this.luckySign,
      stats: {
        for (final k in kDccStats)
          k: ((st[k] ?? 10) as num).round().clamp(3, 18),
      },
      lckMax: (lckMax ?? this.lckMax).clamp(3, 18),
      currentHp: (currentHp ?? this.currentHp).clamp(0, mh),
      maxHp: mh,
      ac: (ac ?? this.ac).clamp(0, 30),
      attackBonus: (attackBonus ?? this.attackBonus).clamp(-5, 20),
      actionDie: kDccActionDice.contains(actionDie ?? this.actionDie)
          ? (actionDie ?? this.actionDie)
          : 'd20',
      initNote: initNote ?? this.initNote,
      saves: {
        for (final k in kDccSaveKeys)
          k: ((sv[k] ?? 0) as num).round().clamp(-5, 20),
      },
      deedDie: kDccDeedDice.contains(deedDie ?? this.deedDie)
          ? (deedDie ?? this.deedDie)
          : 'd3',
      burns: {
        for (final k in const ['str', 'agi', 'sta', 'per'])
          k: ((bn[k] ?? 0) as num).round().clamp(0, 18),
      },
      disapprovalRange:
          (disapprovalRange ?? this.disapprovalRange).clamp(1, 20),
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'className': className,
        'level': level,
        'alignment': alignment,
        'occupation': occupation,
        'luckySign': luckySign,
        'stats': stats,
        'lckMax': lckMax,
        'currentHp': currentHp,
        'maxHp': maxHp,
        'ac': ac,
        'attackBonus': attackBonus,
        'actionDie': actionDie,
        'initNote': initNote,
        'saves': saves,
        'deedDie': deedDie,
        'burns': burns,
        'disapprovalRange': disapprovalRange,
        'notes': notes,
      };

  static DccSheet? maybeFromJson(dynamic j) {
    if (j is! Map<String, dynamic>) return null;
    final st = (j['stats'] as Map?) ?? const {};
    final sv = (j['saves'] as Map?) ?? const {};
    final bn = (j['burns'] as Map?) ?? const {};
    return DccSheet(
      className: j['className'] as String? ?? 'Warrior',
      level: ((j['level'] as num?)?.round() ?? 1).clamp(1, 10),
      alignment: j['alignment'] as String? ?? 'Neutral',
      occupation: j['occupation'] as String? ?? '',
      luckySign: j['luckySign'] as String? ?? '',
      stats: {
        for (final k in kDccStats)
          k: ((st[k] ?? 10) as num).round().clamp(3, 18),
      },
      lckMax: ((j['lckMax'] as num?)?.round() ?? 10).clamp(3, 18),
      currentHp:
          ((j['currentHp'] as num?)?.round() ?? 4).clamp(0, kFieldClampMax),
      maxHp: ((j['maxHp'] as num?)?.round() ?? 4).clamp(0, kFieldClampMax),
      ac: ((j['ac'] as num?)?.round() ?? 10).clamp(0, 30),
      attackBonus: ((j['attackBonus'] as num?)?.round() ?? 0).clamp(-5, 20),
      // Validate the dice tokens: the widget parses sides via substring(1),
      // so a corrupted/hand-edited value must not survive to int.parse.
      actionDie: kDccActionDice.contains(j['actionDie'])
          ? j['actionDie'] as String
          : 'd20',
      initNote: j['initNote'] as String? ?? '',
      saves: {
        for (final k in kDccSaveKeys)
          k: ((sv[k] ?? 0) as num).round().clamp(-5, 20),
      },
      deedDie:
          kDccDeedDice.contains(j['deedDie']) ? j['deedDie'] as String : 'd3',
      burns: {
        for (final k in const ['str', 'agi', 'sta', 'per'])
          k: ((bn[k] ?? 0) as num).round().clamp(0, 18),
      },
      disapprovalRange:
          ((j['disapprovalRange'] as num?)?.round() ?? 1).clamp(1, 20),
      notes: j['notes'] as String? ?? '',
    );
  }
}

class OseSheet {
  const OseSheet({
    this.className = 'Fighter',
    this.level = 1,
    this.xp = '',
    this.alignment = 'Neutral',
    this.stats = const {
      'str': 10,
      'int': 10,
      'wis': 10,
      'dex': 10,
      'con': 10,
      'cha': 10,
    },
    this.saves = const {
      'death': 12,
      'wands': 13,
      'paralysis': 14,
      'breath': 15,
      'spells': 16,
    },
    this.maxHp = 4,
    this.currentHp = 4,
    this.ac = 9,
    this.thac0 = 19,
    this.coins = '',
    this.notes = '',
  });

  final String className;
  final int level;
  final String xp;
  final String alignment;
  final Map<String, int> stats;
  final Map<String, int> saves;
  final int maxHp;
  final int currentHp;
  final int ac;
  final int thac0;
  final String coins;
  final String notes;

  OseSheet copyWith({
    String? className,
    int? level,
    String? xp,
    String? alignment,
    Map<String, int>? stats,
    Map<String, int>? saves,
    int? maxHp,
    int? currentHp,
    int? ac,
    int? thac0,
    String? coins,
    String? notes,
  }) {
    final mh = (maxHp ?? this.maxHp).clamp(0, kFieldClampMax);
    final st = stats ?? this.stats;
    final sv = saves ?? this.saves;
    return OseSheet(
      className: className ?? this.className,
      level: (level ?? this.level).clamp(1, 20),
      xp: xp ?? this.xp,
      alignment: alignment ?? this.alignment,
      stats: {
        for (final k in kOseStats)
          k: ((st[k] ?? 10) as num).round().clamp(3, 18),
      },
      saves: {
        for (final k in kOseSaveKeys)
          k: ((sv[k] ?? 12) as num).round().clamp(2, 20),
      },
      maxHp: mh,
      currentHp: (currentHp ?? this.currentHp).clamp(0, mh),
      ac: ac ?? this.ac,
      thac0: thac0 ?? this.thac0,
      coins: coins ?? this.coins,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'className': className,
        'level': level,
        'xp': xp,
        'alignment': alignment,
        'stats': stats,
        'saves': saves,
        'maxHp': maxHp,
        'currentHp': currentHp,
        'ac': ac,
        'thac0': thac0,
        'coins': coins,
        'notes': notes,
      };

  static OseSheet? maybeFromJson(dynamic j) {
    if (j is! Map<String, dynamic>) return null;
    final st = (j['stats'] as Map?) ?? {};
    final sv = (j['saves'] as Map?) ?? {};
    return OseSheet(
      className: j['className'] as String? ?? 'Fighter',
      level: ((j['level'] as num?)?.round() ?? 1).clamp(1, 20),
      xp: j['xp'] as String? ?? '',
      alignment: j['alignment'] as String? ?? 'Neutral',
      stats: {
        for (final k in kOseStats)
          k: ((st[k] ?? 10) as num).round().clamp(3, 18),
      },
      saves: {
        for (final k in kOseSaveKeys)
          k: ((sv[k] ?? 12) as num).round().clamp(2, 20),
      },
      maxHp: (j['maxHp'] as num?)?.round() ?? 4,
      currentHp: (j['currentHp'] as num?)?.round() ?? 4,
      ac: (j['ac'] as num?)?.round() ?? 9,
      thac0: (j['thac0'] as num?)?.round() ?? 19,
      coins: j['coins'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
    );
  }
}

// ── Kal-Arath ────────────────────────────────────────────────────────────────

const kKalArathStats = <String>['str', 'tou', 'agi', 'int', 'pre'];

const kKalArathStatLabels = <String, String>{
  'str': 'STR',
  'tou': 'TOU',
  'agi': 'AGI',
  'int': 'INT',
  'pre': 'PRE',
};

const kKalArathArchetypes = <String>['Warrior', 'Rogue', 'Mystic', 'Explorer'];

const kKalArathPacts = <String>[
  'Blood',
  'Destruction',
  'Corruption',
  'Illumination',
  'Shadow',
  'Domination',
];

/// Facts-only Kal-Arath character sheet. Field names are non-copyrightable
/// game-mechanic facts. No rulebook prose or attribution (Kal-Arath © Castle
/// Grief is personal-use only; richer content deferred pending permission).
class KalArathSheet {
  const KalArathSheet({
    this.archetype = 'Warrior',
    this.level = 1,
    this.xp = '',
    this.stats = const {
      'str': 0,
      'tou': 0,
      'agi': 0,
      'int': 0,
      'pre': 0,
    },
    this.maxHp = 4,
    this.currentHp = 4,
    this.fatePoints = 1,
    this.damageReduction = 0,
    this.pact = '',
    this.doom = '',
    this.skills = '',
    this.notes = '',
  });

  final String archetype;
  final int level;
  final String xp;
  final Map<String, int> stats;
  final int maxHp;
  final int currentHp;
  final int fatePoints;
  final int damageReduction;
  final String pact;
  final String doom;
  final String skills;
  final String notes;

  KalArathSheet copyWith({
    String? archetype,
    int? level,
    String? xp,
    Map<String, int>? stats,
    int? maxHp,
    int? currentHp,
    int? fatePoints,
    int? damageReduction,
    String? pact,
    String? doom,
    String? skills,
    String? notes,
  }) {
    final mh = (maxHp ?? this.maxHp).clamp(0, kFieldClampMax);
    final st = stats ?? this.stats;
    return KalArathSheet(
      archetype: archetype ?? this.archetype,
      level: (level ?? this.level).clamp(1, 9),
      xp: xp ?? this.xp,
      stats: {
        for (final k in kKalArathStats)
          k: ((st[k] ?? 0) as num).round().clamp(-1, 5)
      },
      maxHp: mh,
      currentHp: (currentHp ?? this.currentHp).clamp(0, mh),
      fatePoints: (fatePoints ?? this.fatePoints).clamp(0, 99),
      damageReduction: (damageReduction ?? this.damageReduction).clamp(0, 99),
      pact: pact ?? this.pact,
      doom: doom ?? this.doom,
      skills: skills ?? this.skills,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'archetype': archetype,
        'level': level,
        'xp': xp,
        'stats': stats,
        'maxHp': maxHp,
        'currentHp': currentHp,
        'fatePoints': fatePoints,
        'damageReduction': damageReduction,
        'pact': pact,
        'doom': doom,
        'skills': skills,
        'notes': notes,
      };

  static KalArathSheet? maybeFromJson(dynamic j) {
    if (j is! Map<String, dynamic>) return null;
    final st = (j['stats'] as Map?) ?? {};
    return KalArathSheet(
      archetype: j['archetype'] as String? ?? 'Warrior',
      level: ((j['level'] as num?)?.round() ?? 1).clamp(1, 9),
      xp: j['xp'] as String? ?? '',
      stats: {
        for (final k in kKalArathStats)
          k: ((st[k] ?? 0) as num).round().clamp(-1, 5),
      },
      maxHp: (j['maxHp'] as num?)?.round() ?? 4,
      currentHp: (j['currentHp'] as num?)?.round() ?? 4,
      fatePoints: ((j['fatePoints'] as num?)?.round() ?? 1).clamp(0, 99),
      damageReduction:
          ((j['damageReduction'] as num?)?.round() ?? 0).clamp(0, 99),
      pact: j['pact'] as String? ?? '',
      doom: j['doom'] as String? ?? '',
      skills: j['skills'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
    );
  }
}

// --- Shadowdark (facts-only: names/rules/dice — no rulebook prose) ----------

const kShadowdarkClasses = <String>['Fighter', 'Priest', 'Thief', 'Wizard'];
const kShadowdarkAncestries = <String>[
  'Dwarf',
  'Elf',
  'Goblin',
  'Half-Orc',
  'Halfling',
  'Human',
];
const kShadowdarkAlignments = <String>['Lawful', 'Neutral', 'Chaotic'];
const kShadowdarkClassHitDie = <String, int>{
  'Fighter': 8,
  'Priest': 6,
  'Thief': 4,
  'Wizard': 4,
};
const kShadowdarkCastingAbility = <String, String>{
  'Priest': 'wis',
  'Wizard': 'int',
};

/// Bespoke lean Shadowdark sheet. Authors only game-mechanic facts; title,
/// deity, talents, and spells are freeform (no rulebook text shipped).
class ShadowdarkSheet {
  const ShadowdarkSheet({
    this.abilities = const {
      'str': 10,
      'dex': 10,
      'con': 10,
      'int': 10,
      'wis': 10,
      'cha': 10
    },
    this.className = 'Fighter',
    this.ancestry = 'Human',
    this.alignment = 'Neutral',
    this.level = 1,
    this.xp = 0,
    this.ac = 10,
    this.currentHp = 1,
    this.maxHp = 1,
    this.gearSlotsUsed = 0,
    this.torch = 0,
    this.luckToken = false,
    this.title = '',
    this.deity = '',
    this.background = '',
    this.talentsText = '',
    this.spellsText = '',
  });

  final Map<String, int> abilities; // keys = kDndAbilities, each 1..20
  final String className, ancestry, alignment;
  final int level; // 1..10
  final int xp, ac, currentHp, maxHp, gearSlotsUsed;

  /// Light countdown for the active light source (0 = unlit/out). A neutral
  /// player-controlled timer — tick down per turn, reset on a fresh light.
  final int torch;
  final bool luckToken;
  final String title, deity, background, talentsText, spellsText;

  int score(String a) => abilities[a] ?? 10;
  int abilityMod(String a) => ((score(a) - 10) / 2).floor();
  int get gearSlotCapacity => score('str') > 10 ? score('str') : 10;
  int get hitDie => kShadowdarkClassHitDie[className] ?? 8;
  bool get isCaster => kShadowdarkCastingAbility.containsKey(className);
  String? get castingAbility => kShadowdarkCastingAbility[className];
  int? get castingMod => isCaster ? abilityMod(castingAbility!) : null;

  factory ShadowdarkSheet.premade() => const ShadowdarkSheet(
        className: 'Fighter',
        ancestry: 'Human',
        alignment: 'Neutral',
        level: 1,
        ac: 10,
        currentHp: 8, // Fighter d8
        maxHp: 8,
      );

  ShadowdarkSheet copyWith({
    Map<String, int>? abilities,
    String? className,
    String? ancestry,
    String? alignment,
    int? level,
    int? xp,
    int? ac,
    int? currentHp,
    int? maxHp,
    int? gearSlotsUsed,
    int? torch,
    bool? luckToken,
    String? title,
    String? deity,
    String? background,
    String? talentsText,
    String? spellsText,
  }) {
    final ab = abilities ?? this.abilities;
    final cls = className ?? this.className;
    final anc = ancestry ?? this.ancestry;
    final al = alignment ?? this.alignment;
    return ShadowdarkSheet(
      abilities: {
        for (final a in kDndAbilities) a: (ab[a] ?? 10).clamp(1, 20),
      },
      className: kShadowdarkClassHitDie.containsKey(cls) ? cls : 'Fighter',
      ancestry: kShadowdarkAncestries.contains(anc) ? anc : 'Human',
      alignment: kShadowdarkAlignments.contains(al) ? al : 'Neutral',
      level: (level ?? this.level).clamp(1, 10),
      xp: (xp ?? this.xp).clamp(0, 1 << 31),
      ac: (ac ?? this.ac).clamp(0, 99),
      currentHp: (currentHp ?? this.currentHp).clamp(0, kFieldClampMax),
      maxHp: (maxHp ?? this.maxHp).clamp(0, kFieldClampMax),
      gearSlotsUsed: (gearSlotsUsed ?? this.gearSlotsUsed).clamp(0, 999),
      torch: (torch ?? this.torch).clamp(0, 9999),
      luckToken: luckToken ?? this.luckToken,
      title: title ?? this.title,
      deity: deity ?? this.deity,
      background: background ?? this.background,
      talentsText: talentsText ?? this.talentsText,
      spellsText: spellsText ?? this.spellsText,
    );
  }

  Map<String, dynamic> toJson() => {
        'abilities': abilities,
        'className': className,
        'ancestry': ancestry,
        'alignment': alignment,
        'level': level,
        if (xp != 0) 'xp': xp,
        'ac': ac,
        'currentHp': currentHp,
        'maxHp': maxHp,
        if (gearSlotsUsed != 0) 'gearSlotsUsed': gearSlotsUsed,
        if (torch != 0) 'torch': torch,
        if (luckToken) 'luckToken': true,
        if (title.isNotEmpty) 'title': title,
        if (deity.isNotEmpty) 'deity': deity,
        if (background.isNotEmpty) 'background': background,
        if (talentsText.isNotEmpty) 'talentsText': talentsText,
        if (spellsText.isNotEmpty) 'spellsText': spellsText,
      };

  static ShadowdarkSheet? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    final rawAb = j['abilities'];
    final ab = <String, int>{
      for (final a in kDndAbilities)
        a: (rawAb is Map ? _intOr(rawAb[a], 10) : 10).clamp(1, 20),
    };
    final cls = _strOr(j['className']);
    final anc = _strOr(j['ancestry']);
    final al = _strOr(j['alignment']);
    return ShadowdarkSheet(
      abilities: ab,
      className: kShadowdarkClassHitDie.containsKey(cls) ? cls : 'Fighter',
      ancestry: kShadowdarkAncestries.contains(anc) ? anc : 'Human',
      alignment: kShadowdarkAlignments.contains(al) ? al : 'Neutral',
      level: _intOr(j['level'], 1).clamp(1, 10),
      xp: _intOr(j['xp'], 0).clamp(0, 1 << 31),
      ac: _intOr(j['ac'], 10).clamp(0, 99),
      currentHp: _intOr(j['currentHp'], 1).clamp(0, kFieldClampMax),
      maxHp: _intOr(j['maxHp'], 1).clamp(0, kFieldClampMax),
      gearSlotsUsed: _intOr(j['gearSlotsUsed'], 0).clamp(0, 999),
      torch: _intOr(j['torch'], 0).clamp(0, 9999),
      luckToken: j['luckToken'] == true,
      title: _strOr(j['title']),
      deity: _strOr(j['deity']),
      background: _strOr(j['background']),
      talentsText: _strOr(j['talentsText']),
      spellsText: _strOr(j['spellsText']),
    );
  }
}

/// One attack line on a combatant stat block: a name plus freeform [detail]
/// (e.g. "+4, 1d6+2 slashing"). Display-only — no expression parsing.
class Attack {
  const Attack({required this.name, this.detail = ''});
  final String name;
  final String detail;

  Attack copyWith({String? name, String? detail}) =>
      Attack(name: name ?? this.name, detail: detail ?? this.detail);

  Map<String, dynamic> toJson() =>
      {'name': name, if (detail.isNotEmpty) 'detail': detail};

  factory Attack.fromJson(dynamic j) => j is Map
      ? Attack(
          name: (j['name'] as String?) ?? '',
          detail: (j['detail'] as String?) ?? '')
      : const Attack(name: '');
}

/// One named trait/action on a stat block (D&D traits, actions, legendary acts).
class StatTrait {
  const StatTrait({required this.name, this.text = ''});
  final String name;
  final String text;

  Map<String, dynamic> toJson() =>
      {'name': name, if (text.isNotEmpty) 'text': text};

  factory StatTrait.fromJson(dynamic j) => j is Map
      ? StatTrait(
          name: (j['name'] as String?) ?? '',
          text: (j['text'] as String?) ?? '')
      : const StatTrait(name: '');
}

/// A combatant's user-authored stat block. Facts-only; the GM types everything.
/// HP is NOT here — it lives on the combatant's track / linked character.
class StatBlock {
  const StatBlock({
    this.ac = 0,
    this.attacks = const [],
    this.saves = '',
    this.speed = '',
    this.notes = '',
    this.cr,
    this.creatureType,
    this.size,
    this.abilities,
    this.traits,
  });
  final int ac;
  final List<Attack> attacks;
  final String saves, speed, notes;
  final String? cr;
  final String? creatureType;
  final String? size;
  final Map<String, int>? abilities;
  final List<StatTrait>? traits;

  bool get isEmpty =>
      ac == 0 &&
      attacks.isEmpty &&
      saves.isEmpty &&
      speed.isEmpty &&
      notes.isEmpty &&
      cr == null &&
      creatureType == null &&
      size == null &&
      (abilities == null || abilities!.isEmpty) &&
      (traits == null || traits!.isEmpty);

  StatBlock copyWith({
    int? ac,
    List<Attack>? attacks,
    String? saves,
    String? speed,
    String? notes,
    String? cr,
    String? creatureType,
    String? size,
    Map<String, int>? abilities,
    List<StatTrait>? traits,
  }) =>
      StatBlock(
        ac: ac ?? this.ac,
        attacks: attacks ?? this.attacks,
        saves: saves ?? this.saves,
        speed: speed ?? this.speed,
        notes: notes ?? this.notes,
        cr: cr ?? this.cr,
        creatureType: creatureType ?? this.creatureType,
        size: size ?? this.size,
        abilities: abilities ?? this.abilities,
        traits: traits ?? this.traits,
      );

  Map<String, dynamic> toJson() => {
        if (ac != 0) 'ac': ac,
        if (attacks.isNotEmpty)
          'attacks': attacks.map((a) => a.toJson()).toList(),
        if (saves.isNotEmpty) 'saves': saves,
        if (speed.isNotEmpty) 'speed': speed,
        if (notes.isNotEmpty) 'notes': notes,
        if (cr != null) 'cr': cr,
        if (creatureType != null) 'creatureType': creatureType,
        if (size != null) 'size': size,
        if (abilities != null && abilities!.isNotEmpty) 'abilities': abilities,
        if (traits != null && traits!.isNotEmpty)
          'traits': traits!.map((t) => t.toJson()).toList(),
      };

  /// Tolerant: non-map -> null; attack entries without a name are dropped.
  static StatBlock? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    final abil = j['abilities'];
    final trts = j['traits'];
    return StatBlock(
      ac: (j['ac'] as num?)?.toInt() ?? 0,
      attacks: ((j['attacks'] as List?) ?? const [])
          .map(Attack.fromJson)
          .where((a) => a.name.isNotEmpty)
          .toList(),
      saves: (j['saves'] as String?) ?? '',
      speed: (j['speed'] as String?) ?? '',
      notes: (j['notes'] as String?) ?? '',
      cr: j['cr'] as String?,
      creatureType: j['creatureType'] as String?,
      size: j['size'] as String?,
      abilities: abil is Map
          ? abil.map((k, v) => MapEntry(k as String, (v as num?)?.toInt() ?? 0))
          : null,
      traits: trts is List
          ? trts
              .map(StatTrait.fromJson)
              .where((t) => t.name.isNotEmpty)
              .toList()
          : null,
    );
  }
}

/// A saved bestiary creature: a named [StatBlock] plus a default [maxHp] used to
/// seed a combatant's HP track when added to an encounter. App-global library
/// (see BestiaryNotifier); reusable across campaigns, not part of campaign export.
class Creature {
  const Creature({
    required this.id,
    required this.name,
    this.statBlock = const StatBlock(),
    this.maxHp = 0,
    this.edition,
  });
  final String id;
  final String name;
  final StatBlock statBlock;
  final int maxHp;
  final String? edition;

  Creature copyWith({
    String? name,
    StatBlock? statBlock,
    int? maxHp,
    String? edition,
  }) =>
      Creature(
        id: id,
        name: name ?? this.name,
        statBlock: statBlock ?? this.statBlock,
        maxHp: maxHp ?? this.maxHp,
        edition: edition ?? this.edition,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (!statBlock.isEmpty) 'statBlock': statBlock.toJson(),
        if (maxHp > 0) 'maxHp': maxHp,
        if (edition != null) 'edition': edition,
      };

  static Creature? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    final id = j['id'] as String?;
    final name = j['name'] as String?;
    if (id == null || id.isEmpty || name == null) return null;
    return Creature(
      id: id,
      name: name,
      statBlock: StatBlock.maybeFromJson(j['statBlock']) ?? const StatBlock(),
      maxHp: (j['maxHp'] as num?)?.toInt() ?? 0,
      edition: j['edition'] as String?,
    );
  }
}

/// One combatant in the encounter. Linked combatants ([characterId] != null)
/// read/write the character's first track; ad-hoc ones own [track].
class Combatant {
  const Combatant({
    required this.id,
    required this.name,
    this.characterId,
    required this.initiative,
    this.track,
    this.tags = const [],
    this.defeated = false,
    this.statBlock,
    this.initMod = 0,
  });
  final String id;
  final String name;
  final String? characterId;
  final int initiative;
  final CharTrack? track; // null for linked combatants
  final List<String> tags;
  final bool defeated;
  final StatBlock? statBlock;

  /// Per-combatant initiative modifier: `rollInitiativeForAll` rolls `d20 +
  /// initMod` for unset combatants and tie-breaks by it. 0 = none.
  final int initMod;

  Combatant copyWith({
    int? initiative,
    CharTrack? track,
    List<String>? tags,
    bool? defeated,
    StatBlock? statBlock,
    bool clearStatBlock = false,
    int? initMod,
  }) =>
      Combatant(
        id: id,
        name: name,
        characterId: characterId,
        initiative: initiative ?? this.initiative,
        track: track ?? this.track,
        tags: tags ?? this.tags,
        defeated: defeated ?? this.defeated,
        statBlock: clearStatBlock ? null : (statBlock ?? this.statBlock),
        initMod: initMod ?? this.initMod,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'characterId': characterId,
        'initiative': initiative,
        'track': track?.toJson(),
        'tags': tags,
        'defeated': defeated,
        if (statBlock != null && !statBlock!.isEmpty)
          'statBlock': statBlock!.toJson(),
        if (initMod != 0) 'initMod': initMod,
      };

  /// Tolerant like [Character]: missing tags -> [], missing defeated ->
  /// false, track via [CharTrack.maybeFromJson].
  factory Combatant.fromJson(Map<String, dynamic> j) => Combatant(
        id: j['id'] as String,
        name: j['name'] as String,
        characterId: j['characterId'] as String?,
        initiative: (j['initiative'] as int?) ?? 0,
        track: CharTrack.maybeFromJson(j['track']),
        tags: ((j['tags'] as List?) ?? const []).whereType<String>().toList(),
        defeated: (j['defeated'] as bool?) ?? false,
        statBlock: StatBlock.maybeFromJson(j['statBlock']),
        initMod: (j['initMod'] as int?) ?? 0,
      );
}

/// Turn-ordered encounter. [combatants] order IS the turn order.
class EncounterState {
  const EncounterState({
    this.combatants = const [],
    this.turnIndex = 0,
    this.round = 1,
    this.locationRef,
  });
  final List<Combatant> combatants;
  final int turnIndex;
  final int round;
  final LocationRef? locationRef;

  EncounterState copyWith({
    List<Combatant>? combatants,
    int? turnIndex,
    int? round,
    LocationRef? locationRef,
    bool clearLocationRef = false,
  }) =>
      EncounterState(
        combatants: combatants ?? this.combatants,
        turnIndex: turnIndex ?? this.turnIndex,
        round: round ?? this.round,
        locationRef:
            clearLocationRef ? null : (locationRef ?? this.locationRef),
      );

  Map<String, dynamic> toJson() => {
        'combatants': combatants.map((c) => c.toJson()).toList(),
        'turnIndex': turnIndex,
        'round': round,
        if (locationRef != null) 'locationRef': locationRef!.toJson(),
      };

  /// Tolerant defaults; turnIndex sanitized into the combatant range
  /// (mirrors CharTrack.maybeFromJson's value sanitizing).
  factory EncounterState.fromJson(Map<String, dynamic> j) {
    final combatants = ((j['combatants'] as List?) ?? const [])
        .map((e) =>
            e is Map ? Combatant.fromJson(Map<String, dynamic>.from(e)) : null)
        .whereType<Combatant>()
        .toList();
    final maxTurn = combatants.isEmpty ? 0 : combatants.length - 1;
    return EncounterState(
      combatants: combatants,
      turnIndex: ((j['turnIndex'] as int?) ?? 0).clamp(0, maxTurn),
      round: (j['round'] as int?) ?? 1,
      locationRef: j['locationRef'] == null
          ? null
          : LocationRef.fromJson(
              Map<String, dynamic>.from(j['locationRef'] as Map)),
    );
  }
}

/// A mapped dungeon room on the integer grid (one cell per room).
/// Lonelog Dungeon-Crawling addon room-status palette (suggested, not closed).
const kDungeonRoomStatuses = [
  'unexplored',
  'active',
  'cleared',
  'looted',
  'locked',
  'trapped',
  'safe',
  'collapsed',
];

class DungeonRoom {
  const DungeonRoom({
    required this.id,
    required this.x,
    required this.y,
    required this.title,
    this.detail = '',
    this.status = '',
    this.footprint = const [(0, 0)],
    this.doors = const [],
    this.roomType,
  });
  final String id;
  final int x;
  final int y;
  final String title; // e.g. the room's oracle headline
  final String detail; // full GenResult.asText (+ appended linger lines)
  final String status; // Lonelog room status (cleared/looted/…); '' = unset
  final List<(int, int)> footprint; // cell offsets from (x,y); default [(0,0)]
  final List<DoorEdge> doors; // door edges, cells are offsets from (x,y)
  final String? roomType; // 'corridor' | 'chamber' | null (legacy)

  DungeonRoom copyWith({
    String? title,
    String? detail,
    String? status,
    List<(int, int)>? footprint,
    List<DoorEdge>? doors,
    String? roomType,
  }) =>
      DungeonRoom(
        id: id,
        x: x,
        y: y,
        title: title ?? this.title,
        detail: detail ?? this.detail,
        status: status ?? this.status,
        footprint: footprint ?? this.footprint,
        doors: doors ?? this.doors,
        roomType: roomType ?? this.roomType,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'title': title,
        'detail': detail,
        if (status.isNotEmpty) 'status': status,
        if (footprint.length != 1 || footprint.first != (0, 0))
          'fp': [
            for (final c in footprint) [c.$1, c.$2]
          ],
        if (doors.isNotEmpty) 'dr': [for (final d in doors) d.toJson()],
        if (roomType != null) 'rt': roomType,
      };

  /// Parses one room entry; null for anything without a map shape and id
  /// (mirrors CharStat.maybeFromJson tolerance).
  static DungeonRoom? maybeFromJson(dynamic j) {
    if (j is! Map || j['id'] is! String) return null;
    return DungeonRoom(
      id: j['id'] as String,
      x: (j['x'] as int?) ?? 0,
      y: (j['y'] as int?) ?? 0,
      title: (j['title'] as String?) ?? '',
      detail: (j['detail'] as String?) ?? '',
      status: (j['status'] as String?) ?? '',
      footprint: (j['fp'] as List?)
              ?.map((e) => ((e as List)[0] as int, e[1] as int))
              .toList() ??
          const [(0, 0)],
      doors: (j['dr'] as List?)
              ?.map(
                  (e) => DoorEdge.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
      roomType: j['rt'] as String?,
    );
  }
}

/// One ring sub-hex of a local-zoom flower (H4a).
class LocalCell {
  const LocalCell(
      {required this.slot, required this.terrain, required this.feature});
  final int slot; // 0..5 ring position
  final String terrain; // hexcrawl terrain key
  final String feature; // a localFeatures entry

  Map<String, dynamic> toJson() =>
      {'slot': slot, 'terrain': terrain, 'feature': feature};

  static LocalCell? maybeFromJson(dynamic j) {
    if (j is! Map || j['slot'] is! int) return null;
    return LocalCell(
      slot: j['slot'] as int,
      terrain: (j['terrain'] as String?) ?? '',
      feature: (j['feature'] as String?) ?? '',
    );
  }
}

/// One interior area of a site (H4c). A minimal grid cell — no corridors.
class SiteArea {
  const SiteArea({required this.x, required this.y, required this.name});
  final int x;
  final int y;
  final String name; // a siteAreaTypes entry

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'name': name};

  static SiteArea? maybeFromJson(dynamic j) {
    if (j is! Map || j['x'] is! int || j['y'] is! int) return null;
    return SiteArea(
        x: j['x'] as int, y: j['y'] as int, name: (j['name'] as String?) ?? '');
  }
}

/// A revealed wilderness hex (flat-top, odd-q offset coordinates: odd
/// columns are shifted half a hex down).
class HexCell {
  const HexCell({
    required this.col,
    required this.row,
    required this.envRow,
    this.lost = false,
    this.terrain,
    this.pois = const [],
    this.site,
    this.local = const [],
    this.siteLines = const [],
    this.siteAreas = const [],
  });
  final int col;
  final int row;
  final int envRow; // 1..10 -> wilderness_environment table
  final bool lost;
  final String? terrain; // Verdant terrain key, e.g. 'forest'; null = Juice env
  final List<int> pois; // Verdant Points of Interest numbers (1..12)
  final String? site; // hexcrawl site-type on this hex; null = none
  final List<LocalCell> local; // local-zoom flower ring (H4a); [] = not zoomed
  final List<String> siteLines; // site writeup lines (H4b); [] = none
  final List<SiteArea> siteAreas; // site interior areas (H4c); [] = none

  HexCell copyWith({
    int? envRow,
    bool? lost,
    String? terrain,
    bool clearTerrain = false,
    List<int>? pois,
    String? site,
    bool clearSite = false,
    List<LocalCell>? local,
    bool clearLocal = false,
    List<String>? siteLines,
    bool clearSiteLines = false,
    List<SiteArea>? siteAreas,
    bool clearSiteAreas = false,
  }) =>
      HexCell(
        col: col,
        row: row,
        envRow: envRow ?? this.envRow,
        lost: lost ?? this.lost,
        terrain: clearTerrain ? null : (terrain ?? this.terrain),
        pois: pois ?? this.pois,
        site: clearSite ? null : (site ?? this.site),
        local: clearLocal ? const [] : (local ?? this.local),
        siteLines: clearSiteLines ? const [] : (siteLines ?? this.siteLines),
        siteAreas: clearSiteAreas ? const [] : (siteAreas ?? this.siteAreas),
      );

  Map<String, dynamic> toJson() => {
        'col': col,
        'row': row,
        'envRow': envRow,
        'lost': lost,
        if (terrain != null) 'terrain': terrain,
        if (pois.isNotEmpty) 'pois': pois,
        if (site != null) 'site': site,
        if (local.isNotEmpty) 'local': local.map((e) => e.toJson()).toList(),
        if (siteLines.isNotEmpty) 'siteLines': siteLines,
        if (siteAreas.isNotEmpty)
          'siteAreas': siteAreas.map((e) => e.toJson()).toList(),
      };

  /// Parses one hex entry; null for anything without a map shape and int
  /// coordinates. envRow clamps into the table range 1..10.
  static HexCell? maybeFromJson(dynamic j) {
    if (j is! Map || j['col'] is! int || j['row'] is! int) return null;
    return HexCell(
      col: j['col'] as int,
      row: j['row'] as int,
      envRow: ((j['envRow'] as int?) ?? 1).clamp(1, 10),
      lost: (j['lost'] as bool?) ?? false,
      terrain: j['terrain'] as String?,
      pois: ((j['pois'] as List?) ?? const []).whereType<int>().toList(),
      site: j['site'] as String?,
      local: ((j['local'] as List?) ?? const [])
          .map(LocalCell.maybeFromJson)
          .whereType<LocalCell>()
          .toList(),
      siteLines:
          ((j['siteLines'] as List?) ?? const []).whereType<String>().toList(),
      siteAreas: ((j['siteAreas'] as List?) ?? const [])
          .map(SiteArea.maybeFromJson)
          .whereType<SiteArea>()
          .toList(),
    );
  }
}

/// A reference to a place on the session's single map: a dungeon room id,
/// or a hex by (col,row). Empty when none set.
class LocationRef {
  const LocationRef({this.roomId, this.hexCol, this.hexRow});
  final String? roomId;
  final int? hexCol;
  final int? hexRow;

  bool get isEmpty => roomId == null && hexCol == null && hexRow == null;

  Map<String, dynamic> toJson() => {
        if (roomId != null) 'roomId': roomId,
        if (hexCol != null) 'hexCol': hexCol,
        if (hexRow != null) 'hexRow': hexRow,
      };

  factory LocationRef.fromJson(Map<String, dynamic> j) => LocationRef(
        roomId: j['roomId'] as String?,
        hexCol: (j['hexCol'] as num?)?.toInt(),
        hexRow: (j['hexRow'] as num?)?.toInt(),
      );
}

/// The play-state spine: what's "current" in the active campaign. Pointers
/// are nullable; null means no focus (consumers fall back to defaults).
class PlayContext {
  const PlayContext({
    this.activeCharacterId,
    this.activeSceneId,
    this.activeLocation,
  });
  final String? activeCharacterId;
  final String? activeSceneId;
  final LocationRef? activeLocation;

  Map<String, dynamic> toJson() => {
        if (activeCharacterId != null) 'activeCharacterId': activeCharacterId,
        if (activeSceneId != null) 'activeSceneId': activeSceneId,
        if (activeLocation != null) 'activeLocation': activeLocation!.toJson(),
      };

  factory PlayContext.fromJson(Map<String, dynamic> j) => PlayContext(
        activeCharacterId: j['activeCharacterId'] as String?,
        activeSceneId: j['activeSceneId'] as String?,
        activeLocation: j['activeLocation'] == null
            ? null
            : LocationRef.fromJson(
                Map<String, dynamic>.from(j['activeLocation'] as Map)),
      );
}

/// Persisted map state: dungeon graph + revealed hex field.
class MapState {
  const MapState({
    this.rooms = const [],
    this.corridors = const [],
    this.currentRoomId,
    this.hexes = const [],
    this.currentHexCol,
    this.currentHexRow,
  });
  final List<DungeonRoom> rooms;
  final List<List<String>> corridors; // [idA, idB] pairs
  final String? currentRoomId;
  final List<HexCell> hexes;
  final int? currentHexCol;
  final int? currentHexRow;

  /// [clearCurrentRoomId] / [clearCurrentHex] null out the nullable trio
  /// (the hex current is one position, so its col/row clear together).
  MapState copyWith({
    List<DungeonRoom>? rooms,
    List<List<String>>? corridors,
    String? currentRoomId,
    bool clearCurrentRoomId = false,
    List<HexCell>? hexes,
    int? currentHexCol,
    int? currentHexRow,
    bool clearCurrentHex = false,
  }) =>
      MapState(
        rooms: rooms ?? this.rooms,
        corridors: corridors ?? this.corridors,
        currentRoomId:
            clearCurrentRoomId ? null : (currentRoomId ?? this.currentRoomId),
        hexes: hexes ?? this.hexes,
        currentHexCol:
            clearCurrentHex ? null : (currentHexCol ?? this.currentHexCol),
        currentHexRow:
            clearCurrentHex ? null : (currentHexRow ?? this.currentHexRow),
      );

  Map<String, dynamic> toJson() => {
        'rooms': rooms.map((r) => r.toJson()).toList(),
        'corridors': corridors,
        'currentRoomId': currentRoomId,
        'hexes': hexes.map((h) => h.toJson()).toList(),
        'currentHexCol': currentHexCol,
        'currentHexRow': currentHexRow,
      };

  /// Tolerant: malformed room/hex entries are skipped; corridor entries
  /// must be 2-string lists, else skipped.
  factory MapState.fromJson(Map<String, dynamic> j) => MapState(
        rooms: ((j['rooms'] as List?) ?? const [])
            .map(DungeonRoom.maybeFromJson)
            .whereType<DungeonRoom>()
            .toList(),
        corridors: [
          for (final e in (j['corridors'] as List?) ?? const [])
            if (e is List && e.length == 2 && e.every((id) => id is String))
              List<String>.from(e),
        ],
        currentRoomId: j['currentRoomId'] as String?,
        hexes: ((j['hexes'] as List?) ?? const [])
            .map(HexCell.maybeFromJson)
            .whereType<HexCell>()
            .toList(),
        currentHexCol: j['currentHexCol'] as int?,
        currentHexRow: j['currentHexRow'] as int?,
      );
}

/// Party-emulator state on a character (PET agenda/focus/tokens, Triple-O
/// trait marks, Sidekick mood + hexflower position). Additive: stays null
/// until the Party Emulator first writes it.
class CharacterEmulation {
  const CharacterEmulation({
    this.agendaKey,
    this.focusKey,
    this.mood,
    this.tokens = 0,
    this.prominentTags = const [],
    this.usedTags = const [],
    this.hexIndex,
  });

  /// 2..12 key into pet.agenda; null = not rolled yet.
  final int? agendaKey;

  /// 2..12 key into pet.focus; null = not rolled yet.
  final int? focusKey;

  /// Sidekick mood id ('default'…); null = not set.
  final String? mood;

  /// PET tokens earned by playing the agenda.
  final int tokens;

  /// Tags marked prominent (Triple-O doubles growth) — marks on
  /// [Character.tags], the one Trait list.
  final List<String> prominentTags;

  /// Tags checked off by PET tag spends until session reset.
  final List<String> usedTags;

  /// 0..18 Sidekick hexflower position; null = not placed.
  final int? hexIndex;

  /// Lists replace wholesale; clear flags null the nullable fields
  /// (house pattern: clearThreadId).
  CharacterEmulation copyWith({
    int? agendaKey,
    bool clearAgenda = false,
    int? focusKey,
    bool clearFocus = false,
    String? mood,
    bool clearMood = false,
    int? tokens,
    List<String>? prominentTags,
    List<String>? usedTags,
    int? hexIndex,
    bool clearHex = false,
  }) =>
      CharacterEmulation(
        agendaKey: clearAgenda ? null : (agendaKey ?? this.agendaKey),
        focusKey: clearFocus ? null : (focusKey ?? this.focusKey),
        mood: clearMood ? null : (mood ?? this.mood),
        tokens: tokens ?? this.tokens,
        prominentTags: prominentTags ?? this.prominentTags,
        usedTags: usedTags ?? this.usedTags,
        hexIndex: clearHex ? null : (hexIndex ?? this.hexIndex),
      );

  /// Null fields are omitted, keeping persisted characters compact.
  Map<String, dynamic> toJson() => {
        if (agendaKey != null) 'agendaKey': agendaKey,
        if (focusKey != null) 'focusKey': focusKey,
        if (mood != null) 'mood': mood,
        'tokens': tokens,
        'prominentTags': prominentTags,
        'usedTags': usedTags,
        if (hexIndex != null) 'hexIndex': hexIndex,
      };

  /// Parses the emulation block; null for anything that isn't a map.
  /// Tolerant: junk-typed fields fall back to their defaults.
  static CharacterEmulation? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    int? intOrNull(dynamic v) => v is int ? v : null;
    List<String> strings(dynamic v) =>
        v is List ? v.whereType<String>().toList() : const [];
    return CharacterEmulation(
      agendaKey: intOrNull(j['agendaKey']),
      focusKey: intOrNull(j['focusKey']),
      mood: j['mood'] is String ? j['mood'] as String : null,
      tokens: intOrNull(j['tokens']) ?? 0,
      prominentTags: strings(j['prominentTags']),
      usedTags: strings(j['usedTags']),
      hexIndex: intOrNull(j['hexIndex']),
    );
  }
}

enum CharacterRole { pc, companion, npc }

CharacterRole _roleFromName(String? n) => switch (n) {
      'companion' => CharacterRole.companion,
      'npc' => CharacterRole.npc,
      _ => CharacterRole.pc,
    };

/// Authored, system-agnostic status conditions (facts-only). Free-text custom
/// conditions are also allowed.
const kConditions = <String>[
  'poisoned',
  'hurt',
  'afraid',
  'hidden',
  'prone',
  'restrained',
  'stunned',
  'exhausted',
  'sick',
  'marked',
  'blessed',
];

/// One 0-level funnel character. Stats/flavor are keyed by the seed
/// FunnelProfile (see lib/engine/funnel.dart); both are free-shaped maps so the
/// funnel is system-agnostic. All descriptive content is user-entered.
class FunnelPeasant {
  const FunnelPeasant({
    this.name = '',
    this.hp = 0,
    this.alive = true,
    this.graduated = false,
    this.stats = const {},
    this.flavor = const {},
  });

  final String name;
  final int hp;
  final bool alive;
  final bool graduated; // already promoted → not graduable again
  final Map<String, int> stats;
  final Map<String, String> flavor;

  FunnelPeasant copyWith({
    String? name,
    int? hp,
    bool? alive,
    bool? graduated,
    Map<String, int>? stats,
    Map<String, String>? flavor,
  }) =>
      FunnelPeasant(
        name: name ?? this.name,
        hp: (hp ?? this.hp).clamp(0, kFieldClampMax),
        alive: alive ?? this.alive,
        graduated: graduated ?? this.graduated,
        stats: stats ?? this.stats,
        flavor: flavor ?? this.flavor,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'hp': hp,
        'alive': alive,
        'graduated': graduated,
        'stats': stats,
        'flavor': flavor,
      };

  factory FunnelPeasant.fromJson(Map<String, dynamic> j) => FunnelPeasant(
        name: j['name'] as String? ?? '',
        hp: ((j['hp'] as num?)?.round() ?? 0).clamp(0, kFieldClampMax),
        alive: j['alive'] as bool? ?? true,
        graduated: j['graduated'] as bool? ?? false,
        stats: ((j['stats'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, (v as num).round())),
        flavor: ((j['flavor'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, v as String)),
      );
}

/// A standalone 0-level funnel roster entity. `seedSystem` is the sheet system
/// whose FunnelProfile shaped the peasants' stat/flavor keys (see
/// lib/engine/funnel.dart). Graduating a survivor spawns a *separate* hero
/// Character; the funnel persists (the promoted peasant is marked graduated).
class FunnelSheet {
  const FunnelSheet(
      {this.seedSystem = '', this.seedVariant = '', this.peasants = const []});

  final String seedSystem;

  /// Sub-discriminator within [seedSystem]. For a custom funnel, the chosen
  /// template id (locked at creation); '' for every other system.
  final String seedVariant;
  final List<FunnelPeasant> peasants;

  factory FunnelSheet.premade(String seedSystem, List<FunnelPeasant> seed,
          {String seedVariant = ''}) =>
      FunnelSheet(
          seedSystem: seedSystem, seedVariant: seedVariant, peasants: seed);

  FunnelSheet copyWith(
          {String? seedSystem,
          String? seedVariant,
          List<FunnelPeasant>? peasants}) =>
      FunnelSheet(
        seedSystem: seedSystem ?? this.seedSystem,
        seedVariant: seedVariant ?? this.seedVariant,
        peasants: peasants ?? this.peasants,
      );

  /// Returns a copy with peasant [i] flagged graduated.
  FunnelSheet markGraduated(int i) {
    final list = [...peasants];
    list[i] = list[i].copyWith(graduated: true);
    return copyWith(peasants: list);
  }

  int get aliveCount => peasants.where((p) => p.alive && !p.graduated).length;
  int get graduatedCount => peasants.where((p) => p.graduated).length;

  Map<String, dynamic> toJson() => {
        'seedSystem': seedSystem,
        if (seedVariant.isNotEmpty) 'seedVariant': seedVariant,
        'peasants': peasants.map((p) => p.toJson()).toList(),
      };

  static FunnelSheet? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    final m = j.cast<String, dynamic>();
    return FunnelSheet(
      seedSystem: m['seedSystem'] as String? ?? '',
      seedVariant: m['seedVariant'] as String? ?? '',
      peasants: ((m['peasants'] as List?) ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => FunnelPeasant.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// A character's HP pool `(current, max)` resolved the same way
/// [Character.withHpDelta] applies damage: the active sheet's pool, else the
/// first generic track, else null (pool-less sheets). Shared by the roster, the
/// encounter tracker, and the run-screen.
(int, int)? characterHpPool(Character c) {
  if (c.dnd != null) return (c.dnd!.currentHp, c.dnd!.maxHp);
  if (c.shadowdark != null) {
    return (c.shadowdark!.currentHp, c.shadowdark!.maxHp);
  }
  if (c.nimble != null) return (c.nimble!.currentHp, c.nimble!.maxHp);
  if (c.drawSteel != null) {
    return (c.drawSteel!.currentStamina, c.drawSteel!.maxStamina);
  }
  if (c.argosa != null) return (c.argosa!.currentHp, c.argosa!.maxHp);
  if (c.cairn != null) return (c.cairn!.currentHp, c.cairn!.maxHp);
  if (c.knave != null) return (c.knave!.currentHp, c.knave!.maxHp);
  if (c.ose != null) return (c.ose!.currentHp, c.ose!.maxHp);
  if (c.kalArath != null) return (c.kalArath!.currentHp, c.kalArath!.maxHp);
  if (c.dcc != null) return (c.dcc!.currentHp, c.dcc!.maxHp);
  if (c.tracks.isNotEmpty) return (c.tracks.first.current, c.tracks.first.max);
  return null;
}

/// Persisted character/NPC the player tracks, with an optional sheet
/// (stats, tracks, tags). Legacy JSON without those keys parses fine.
class Character {
  const Character({
    required this.id,
    required this.name,
    this.note = '',
    this.stats = const [],
    this.tracks = const [],
    this.tags = const [],
    this.emulation,
    this.ironsworn,
    this.starforged,
    this.dnd,
    this.shadowdark,
    this.nimble,
    this.drawSteel,
    this.argosa,
    this.cairn,
    this.knave,
    this.ose,
    this.kalArath,
    this.custom,
    this.dcc,
    this.funnel,
    this.starred = false,
    this.role = CharacterRole.pc,
    this.conditions = const [],
  });
  final String id;
  final String name;
  final String note;
  final List<CharStat> stats;
  final List<CharTrack> tracks;
  final List<String> tags;

  /// Party-emulator state; null until the Party tool writes it.
  final CharacterEmulation? emulation;

  /// Bespoke Classic Ironsworn sheet; null unless this is an Ironsworn PC.
  final IronswornSheet? ironsworn;

  /// Bespoke Starforged sheet; null unless this is a Starforged PC.
  final StarforgedSheet? starforged;

  /// Bespoke D&D 5e sheet; null unless this is a D&D PC.
  final DndSheet? dnd;

  /// Bespoke Shadowdark sheet; null unless this is a Shadowdark PC.
  final ShadowdarkSheet? shadowdark;

  /// Bespoke Nimble sheet; null unless this is a Nimble PC.
  final NimbleSheet? nimble;

  /// Bespoke Draw Steel sheet; null unless this is a Draw Steel hero.
  final DrawSteelSheet? drawSteel;

  /// Bespoke Tales of Argosa sheet; null unless this is an Argosa PC.
  final ArgosaSheet? argosa;

  /// Bespoke Cairn sheet; null unless this is a Cairn PC.
  final CairnSheet? cairn;

  /// Bespoke Knave sheet; null unless this is a Knave PC.
  final KnaveSheet? knave;

  /// Bespoke Old-School Essentials sheet; null unless this is an OSE PC.
  final OseSheet? ose;

  /// Bespoke Kal-Arath sheet; null unless this is a Kal-Arath wanderer.
  final KalArathSheet? kalArath;

  /// User-defined custom/homebrew sheet; null unless this is a custom PC.
  final CustomSheet? custom;

  /// Bespoke DCC sheet; null unless this is a DCC character.
  final DccSheet? dcc;

  /// Standalone 0-level funnel; null unless this roster entry is a funnel.
  final FunnelSheet? funnel;

  /// Whether this character is starred in the campaign header.
  final bool starred;

  /// Roster role: pc (default), companion, or npc. Omitted from JSON when pc.
  final CharacterRole role;

  /// Active status conditions (system-agnostic). Omitted from JSON when empty.
  final List<String> conditions;

  /// Creates a pre-made character seeded for [systemKey]. Used by
  /// [CharacterNotifier.addPreMadeSheet] to collapse per-system boilerplate.
  factory Character.forSheet(String systemKey, String id) {
    return switch (systemKey) {
      'ironsworn' => Character(
          id: id,
          name: 'New Ironsworn character',
          ironsworn: IronswornSheet.premade()),
      'starforged' => Character(
          id: id,
          name: 'New Starforged character',
          starforged: StarforgedSheet.premade()),
      'sundered_isles' => Character(
          id: id,
          name: 'New Sundered Isles character',
          starforged: StarforgedSheet.premade(assetRuleset: 'sundered_isles')),
      'dnd' =>
        Character(id: id, name: 'New D&D character', dnd: DndSheet.premade()),
      'shadowdark' => Character(
          id: id,
          name: 'New Shadowdark character',
          shadowdark: ShadowdarkSheet.premade()),
      'nimble' => Character(
          id: id, name: 'New Nimble character', nimble: const NimbleSheet()),
      'draw-steel' => Character(
          id: id,
          name: 'New Draw Steel hero',
          drawSteel: const DrawSteelSheet()),
      'argosa' => Character(
          id: id, name: 'New Argosa character', argosa: const ArgosaSheet()),
      'cairn' => Character(
          id: id, name: 'New Cairn character', cairn: const CairnSheet()),
      'knave' =>
        Character(id: id, name: 'New Knave', knave: const KnaveSheet()),
      'ose' => Character(id: id, name: 'New Adventurer', ose: const OseSheet()),
      'kal-arath' => Character(
          id: id, name: 'New Wanderer', kalArath: const KalArathSheet()),
      'custom' => Character(
          id: id, name: 'New Custom character', custom: const CustomSheet()),
      'dcc' =>
        Character(id: id, name: 'New DCC character', dcc: DccSheet.premade()),
      _ => throw StateError('Character.forSheet: unknown system "$systemKey"'),
    };
  }

  /// Lists are replaced wholesale when provided; null keeps the current list.
  Character copyWith({
    String? name,
    String? note,
    List<CharStat>? stats,
    List<CharTrack>? tracks,
    List<String>? tags,
    CharacterEmulation? emulation,
    bool clearEmulation = false,
    IronswornSheet? ironsworn,
    bool clearIronsworn = false,
    StarforgedSheet? starforged,
    bool clearStarforged = false,
    DndSheet? dnd,
    bool clearDnd = false,
    ShadowdarkSheet? shadowdark,
    bool clearShadowdark = false,
    NimbleSheet? nimble,
    bool clearNimble = false,
    DrawSteelSheet? drawSteel,
    bool clearDrawSteel = false,
    ArgosaSheet? argosa,
    bool clearArgosa = false,
    CairnSheet? cairn,
    bool clearCairn = false,
    KnaveSheet? knave,
    bool clearKnave = false,
    OseSheet? ose,
    bool clearOse = false,
    KalArathSheet? kalArath,
    bool clearKalArath = false,
    CustomSheet? custom,
    bool clearCustom = false,
    DccSheet? dcc,
    bool clearDcc = false,
    FunnelSheet? funnel,
    bool clearFunnel = false,
    bool? starred,
    CharacterRole? role,
    List<String>? conditions,
  }) =>
      Character(
        id: id,
        name: name ?? this.name,
        note: note ?? this.note,
        stats: stats ?? this.stats,
        tracks: tracks ?? this.tracks,
        tags: tags ?? this.tags,
        emulation: clearEmulation ? null : (emulation ?? this.emulation),
        ironsworn: clearIronsworn ? null : (ironsworn ?? this.ironsworn),
        starforged: clearStarforged ? null : (starforged ?? this.starforged),
        dnd: clearDnd ? null : (dnd ?? this.dnd),
        shadowdark: clearShadowdark ? null : (shadowdark ?? this.shadowdark),
        nimble: clearNimble ? null : (nimble ?? this.nimble),
        drawSteel: clearDrawSteel ? null : (drawSteel ?? this.drawSteel),
        argosa: clearArgosa ? null : (argosa ?? this.argosa),
        cairn: clearCairn ? null : (cairn ?? this.cairn),
        knave: clearKnave ? null : (knave ?? this.knave),
        ose: clearOse ? null : (ose ?? this.ose),
        kalArath: clearKalArath ? null : (kalArath ?? this.kalArath),
        custom: clearCustom ? null : (custom ?? this.custom),
        dcc: clearDcc ? null : (dcc ?? this.dcc),
        funnel: clearFunnel ? null : (funnel ?? this.funnel),
        starred: starred ?? this.starred,
        role: role ?? this.role,
        conditions: conditions ?? this.conditions,
      );

  /// Applies an HP [delta] (negative = damage) to whichever HP pool this
  /// character uses: the D&D / Shadowdark sheet's currentHp (clamped to its
  /// maxHp), else the first track (via [CharTrack.adjusted]). Characters with
  /// no HP pool (e.g. Ironsworn / Starforged, which use condition meters) are
  /// returned unchanged. Used by the party-wide effect broadcast.
  Character withHpDelta(int delta) {
    if (delta == 0) return this;
    if (dnd != null) {
      return copyWith(
          dnd: dnd!.copyWith(
              currentHp: (dnd!.currentHp + delta).clamp(0, dnd!.maxHp)));
    }
    if (shadowdark != null) {
      return copyWith(
          shadowdark: shadowdark!.copyWith(
              currentHp:
                  (shadowdark!.currentHp + delta).clamp(0, shadowdark!.maxHp)));
    }
    if (nimble != null) {
      return copyWith(
          nimble: nimble!.copyWith(
              currentHp: (nimble!.currentHp + delta).clamp(0, nimble!.maxHp)));
    }
    if (drawSteel != null) {
      return copyWith(
          drawSteel: drawSteel!.copyWith(
              currentStamina: (drawSteel!.currentStamina + delta)
                  .clamp(0, drawSteel!.maxStamina)));
    }
    if (argosa != null) {
      return copyWith(
          argosa: argosa!.copyWith(
              currentHp: (argosa!.currentHp + delta).clamp(0, argosa!.maxHp)));
    }
    if (cairn != null) {
      return copyWith(
          cairn: cairn!.copyWith(
              currentHp: (cairn!.currentHp + delta).clamp(0, cairn!.maxHp)));
    }
    if (knave != null) {
      return copyWith(
          knave: knave!.copyWith(
              currentHp: (knave!.currentHp + delta).clamp(0, knave!.maxHp)));
    }
    if (ose != null) {
      return copyWith(
          ose: ose!.copyWith(
              currentHp: (ose!.currentHp + delta).clamp(0, ose!.maxHp)));
    }
    if (kalArath != null) {
      return copyWith(
          kalArath: kalArath!.copyWith(
              currentHp:
                  (kalArath!.currentHp + delta).clamp(0, kalArath!.maxHp)));
    }
    if (dcc != null) {
      return copyWith(
          dcc: dcc!.copyWith(
              currentHp: (dcc!.currentHp + delta).clamp(0, dcc!.maxHp)));
    }
    if (tracks.isNotEmpty) {
      final updated = [...tracks];
      updated[0] = tracks.first.adjusted(delta);
      return copyWith(tracks: updated);
    }
    return this;
  }

  /// 'emulation', 'starred', 'role', and 'conditions' are written only when
  /// non-null/non-default so existing characters and campaign files stay
  /// byte-stable until the features are used.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'note': note,
        'stats': stats.map((s) => s.toJson()).toList(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'tags': tags,
        if (emulation != null) 'emulation': emulation!.toJson(),
        if (ironsworn != null) 'ironsworn': ironsworn!.toJson(),
        if (starforged != null) 'starforged': starforged!.toJson(),
        if (dnd != null) 'dnd': dnd!.toJson(),
        if (shadowdark != null) 'shadowdark': shadowdark!.toJson(),
        if (nimble != null) 'nimble': nimble!.toJson(),
        if (drawSteel != null) 'drawSteel': drawSteel!.toJson(),
        if (argosa != null) 'argosa': argosa!.toJson(),
        if (cairn != null) 'cairn': cairn!.toJson(),
        if (knave != null) 'knave': knave!.toJson(),
        if (ose != null) 'ose': ose!.toJson(),
        if (kalArath != null) 'kalArath': kalArath!.toJson(),
        if (custom != null) 'custom': custom!.toJson(),
        if (dcc != null) 'dcc': dcc!.toJson(),
        if (funnel != null) 'funnel': funnel!.toJson(),
        if (starred) 'starred': true,
        if (role != CharacterRole.pc) 'role': role.name,
        if (conditions.isNotEmpty) 'conditions': conditions,
      };

  factory Character.fromJson(Map<String, dynamic> j) => Character(
        id: j['id'] as String,
        name: j['name'] as String,
        note: (j['note'] as String?) ?? '',
        stats: ((j['stats'] as List?) ?? const [])
            .map(CharStat.maybeFromJson)
            .whereType<CharStat>()
            .toList(),
        tracks: ((j['tracks'] as List?) ?? const [])
            .map(CharTrack.maybeFromJson)
            .whereType<CharTrack>()
            .toList(),
        tags: ((j['tags'] as List?) ?? const []).whereType<String>().toList(),
        emulation: CharacterEmulation.maybeFromJson(j['emulation']),
        ironsworn: IronswornSheet.maybeFromJson(j['ironsworn']),
        starforged: StarforgedSheet.maybeFromJson(j['starforged']),
        dnd: DndSheet.maybeFromJson(j['dnd']),
        shadowdark: ShadowdarkSheet.maybeFromJson(j['shadowdark']),
        nimble: NimbleSheet.maybeFromJson(j['nimble']),
        drawSteel: DrawSteelSheet.maybeFromJson(j['drawSteel']),
        argosa: ArgosaSheet.maybeFromJson(j['argosa']),
        cairn: CairnSheet.maybeFromJson(j['cairn']),
        knave: KnaveSheet.maybeFromJson(j['knave']),
        ose: OseSheet.maybeFromJson(j['ose']),
        kalArath: KalArathSheet.maybeFromJson(j['kalArath']),
        custom: CustomSheet.maybeFromJson(j['custom']),
        dcc: DccSheet.maybeFromJson(j['dcc']),
        funnel: FunnelSheet.maybeFromJson(j['funnel']),
        starred: (j['starred'] as bool?) ?? false,
        role: _roleFromName(j['role'] as String?),
        conditions: ((j['conditions'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
      );
}

/// Persisted crawl-mode state: wilderness position + NPC dialog marker.
class CrawlState {
  const CrawlState({
    this.envRow,
    this.lost = false,
    this.dialogRow = 2,
    this.dialogCol = 2,
    this.chaosFactor = 5,
  });

  /// Current wilderness environment row 1..10; null until first travel step.
  final int? envRow;

  /// Lost per the Juice Lost/Found cycle (encounter rolls drop to d6).
  final bool lost;

  /// NPC dialog marker on the 5x5 grid (center "Fact" = 2,2).
  final int dialogRow;
  final int dialogCol;

  /// Mythic GME 2e Chaos Factor (1..9, default 5).
  final int chaosFactor;

  CrawlState copyWith({
    int? envRow,
    bool clearEnvRow = false,
    bool? lost,
    int? dialogRow,
    int? dialogCol,
    int? chaosFactor,
  }) =>
      CrawlState(
        envRow: clearEnvRow ? null : (envRow ?? this.envRow),
        lost: lost ?? this.lost,
        dialogRow: dialogRow ?? this.dialogRow,
        dialogCol: dialogCol ?? this.dialogCol,
        chaosFactor: chaosFactor ?? this.chaosFactor,
      );

  Map<String, dynamic> toJson() => {
        'envRow': envRow,
        'lost': lost,
        'dialogRow': dialogRow,
        'dialogCol': dialogCol,
        'chaosFactor': chaosFactor,
      };

  factory CrawlState.fromJson(Map<String, dynamic> j) => CrawlState(
        envRow: j['envRow'] as int?,
        lost: (j['lost'] as bool?) ?? false,
        dialogRow: (j['dialogRow'] as int?) ?? 2,
        dialogCol: (j['dialogCol'] as int?) ?? 2,
        chaosFactor: (j['chaosFactor'] as int?) ?? 5,
      );
}

/// The optional systems a campaign can enable; dice, encounter, the
/// tracker, and help are always available (core).
const kAllSystems = {'juice', 'mythic', 'ironsworn', 'party', 'verdant'};

/// Canonical set of every campaign system id. The single source of truth that
/// kSystemCategory, kSystemBlurbs, and the creation/edit dialogs are checked
/// against. kAllSystems (the 5 legacy-default ids) is a SUBSET of this.
const kKnownSystems = <String>{
  'juice',
  'mythic',
  'ironsworn',
  'party',
  'verdant',
  'lonelog',
  'hexcrawl',
  'dnd',
  'shadowdark',
  'nimble',
  'draw-steel',
  'argosa',
  'cairn',
  'knave',
  'ose',
  'kal-arath',
  'dcc',
  'funnel',
  'cards',
  'custom',
};

/// The four buckets a system belongs to for grouped campaign setup.
enum SystemCategory { ruleset, oracle, exploration, tools }

/// Every system's category. Ruleset is single-select at creation (a campaign
/// runs one game); the model still permits multiple. A completeness test keeps
/// this in lockstep with kKnownSystems.
const kSystemCategory = <String, SystemCategory>{
  'ironsworn': SystemCategory.ruleset,
  'dnd': SystemCategory.ruleset,
  'shadowdark': SystemCategory.ruleset,
  'nimble': SystemCategory.ruleset,
  'draw-steel': SystemCategory.ruleset,
  'argosa': SystemCategory.ruleset,
  'cairn': SystemCategory.ruleset,
  'knave': SystemCategory.ruleset,
  'ose': SystemCategory.ruleset,
  'kal-arath': SystemCategory.ruleset,
  'custom': SystemCategory.ruleset,
  'dcc': SystemCategory.ruleset,
  'juice': SystemCategory.oracle,
  'mythic': SystemCategory.oracle,
  'cards': SystemCategory.oracle,
  'verdant': SystemCategory.exploration,
  'hexcrawl': SystemCategory.exploration,
  'party': SystemCategory.tools,
  'lonelog': SystemCategory.tools,
  'funnel': SystemCategory.tools,
};

/// Human display labels for system keys (incl. opt-in systems not in
/// [kAllSystems]). Used to badge a campaign's profile.
const kSystemLabels = <String, String>{
  'juice': 'Juice',
  'mythic': 'Mythic',
  'ironsworn': 'Ironsworn',
  'party': 'Party',
  'verdant': 'Verdant',
  'lonelog': 'Lonelog',
  'hexcrawl': 'Hexcrawl',
  'dnd': 'D&D',
  'shadowdark': 'Shadowdark',
  'nimble': 'Nimble',
  'cards': 'Cards',
};

// -- Card-deck oracles (facts-only: card identities, no divinatory meanings) --

const _kPlayingRanks = [
  'Ace', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'Jack', 'Queen',
  'King' //
];
const _kPlayingSuits = ['Spades', 'Hearts', 'Diamonds', 'Clubs'];

/// Standard 52-card deck (no jokers), e.g. "Ace of Spades".
final List<String> kPlayingDeck = [
  for (final s in _kPlayingSuits)
    for (final r in _kPlayingRanks) '$r of $s',
];

/// The two jokers, by identity only (no asserted meaning). Used by the opt-in
/// 54-card variant.
const kPlayingJokers = ['Red Joker', 'Black Joker'];

/// The standard deck plus the two jokers (54 cards), for the opt-in variant.
final List<String> kPlayingDeckWithJokers = [
  ...kPlayingDeck,
  ...kPlayingJokers
];

/// The 22 Major Arcana, in canonical order.
const kTarotMajor = [
  'The Fool',
  'The Magician',
  'The High Priestess',
  'The Empress',
  'The Emperor',
  'The Hierophant',
  'The Lovers',
  'The Chariot',
  'Strength',
  'The Hermit',
  'Wheel of Fortune',
  'Justice',
  'The Hanged Man',
  'Death',
  'Temperance',
  'The Devil',
  'The Tower',
  'The Star',
  'The Moon',
  'The Sun',
  'Judgement',
  'The World',
];

const _kTarotRanks = [
  'Ace', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', //
  'Eight', 'Nine', 'Ten', 'Page', 'Knight', 'Queen', 'King'
];
const _kTarotSuits = ['Wands', 'Cups', 'Swords', 'Pentacles'];

/// The 78-card tarot deck: 22 Major Arcana + 56 Minor (14 ranks × 4 suits).
final List<String> kTarotDeck = [
  ...kTarotMajor,
  for (final s in _kTarotSuits)
    for (final r in _kTarotRanks) '$r of $s',
];

/// A shuffled deck's state: [order] is a permutation of card indices; [drawn]
/// is how many have been consumed from the front. A draw pops `order[drawn]`;
/// when exhausted the deck reshuffles. Persisted per campaign.
class DeckState {
  const DeckState({this.order = const [], this.drawn = 0});
  final List<int> order;
  final int drawn;

  int get remaining =>
      order.isEmpty ? 0 : (order.length - drawn).clamp(0, order.length);

  /// Cards left for display: an un-shuffled deck (empty order) reads as full
  /// ([total]), since the first draw lazily shuffles the whole deck.
  int remainingOf(int total) => order.isEmpty ? total : remaining;

  Map<String, dynamic> toJson() => {'order': order, 'drawn': drawn};

  factory DeckState.fromJson(dynamic j) {
    if (j is! Map) return const DeckState();
    return DeckState(
      order: ((j['order'] as List?) ?? const []).whereType<int>().toList(),
      drawn: (j['drawn'] as int?) ?? 0,
    );
  }
}

/// Per-campaign deck state for the card oracles (standard 52 + tarot 78).
class DecksState {
  const DecksState({
    this.standard = const DeckState(),
    this.tarot = const DeckState(),
    this.jokers = false,
  });
  final DeckState standard;
  final DeckState tarot;
  final bool jokers;

  DecksState copyWith({DeckState? standard, DeckState? tarot, bool? jokers}) =>
      DecksState(
        standard: standard ?? this.standard,
        tarot: tarot ?? this.tarot,
        jokers: jokers ?? this.jokers,
      );

  Map<String, dynamic> toJson() => {
        'standard': standard.toJson(),
        'tarot': tarot.toJson(),
        'jokers': jokers,
      };

  factory DecksState.fromJson(Map<String, dynamic> j) => DecksState(
        standard: DeckState.fromJson(j['standard']),
        tarot: DeckState.fromJson(j['tarot']),
        jokers: j['jokers'] == true, // tolerant: missing/non-bool → false
      );
}

/// A compact, stable, human summary of a campaign's enabled [systems], e.g.
/// "D&D · Mythic". The most distinctive systems (sheets) lead.
String formatSystems(Set<String> systems) {
  const order = [
    'dnd',
    'shadowdark',
    'nimble',
    'ironsworn',
    'mythic',
    'juice',
    'party',
    'verdant',
    'lonelog',
    'hexcrawl',
  ];
  final labels = [
    for (final k in order)
      if (systems.contains(k)) kSystemLabels[k]!,
    // Any unknown keys keep their raw id, appended in encounter order.
    for (final k in systems)
      if (!order.contains(k)) kSystemLabels[k] ?? k,
  ];
  return labels.join(' · ');
}

/// The player's current focus for a campaign: running the world (gm) or
/// playing their character(s) (party). Declutters role-specific sub-options.
enum CampaignMode { gm, party }

CampaignMode _modeFromName(String? n) =>
    // Unknown/absent → party (forward-compat default).
    n == 'gm' ? CampaignMode.gm : CampaignMode.party;

/// A campaign/session: an isolated journal, threads, characters, crawl.
class SessionMeta {
  const SessionMeta(
      {required this.id,
      required this.name,
      this.systems,
      this.mode = CampaignMode.party,
      this.identityColor,
      this.identityIcon,
      this.genre,
      this.dndEdition});
  final String id;
  final String name;

  /// Enabled optional systems; null means all (legacy campaigns).
  final List<String>? systems;

  /// Player focus mode (default party; legacy campaigns → party).
  final CampaignMode mode;

  /// Per-campaign identity accent (ARGB int); null falls back to terracotta.
  final int? identityColor;

  /// Per-campaign identity icon key (see kIdentityIcons); null → default.
  final String? identityIcon;

  /// Display genre/mood mirrored from CampaignSettings at create/import time;
  /// null when unset. A cheap, sync display field for campaign-list subtitles —
  /// CampaignSettings.genre remains the interpreter's source of truth.
  final String? genre;

  /// Per-campaign D&D SRD edition preference ("5.1" | "5.2"); null → latest
  /// ('5.2'). Filters edition-tagged content so one edition shows at a time.
  final String? dndEdition;

  /// Resolved set: the declared systems, or every system when unset.
  Set<String> get enabledSystems => systems?.toSet() ?? kAllSystems;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (systems != null) 'systems': systems,
        if (mode != CampaignMode.party) 'mode': mode.name,
        if (identityColor != null) 'identityColor': identityColor,
        if (identityIcon != null) 'identityIcon': identityIcon,
        if (genre != null) 'genre': genre,
        if (dndEdition != null) 'dndEdition': dndEdition,
      };

  // id is immutable — not overridable via copyWith.
  SessionMeta copyWith({
    String? name,
    List<String>? systems,
    CampaignMode? mode,
    int? identityColor,
    String? identityIcon,
    String? genre,
    String? dndEdition,
  }) =>
      SessionMeta(
        id: id,
        name: name ?? this.name,
        systems: systems ?? this.systems,
        mode: mode ?? this.mode,
        identityColor: identityColor ?? this.identityColor,
        identityIcon: identityIcon ?? this.identityIcon,
        genre: genre ?? this.genre,
        dndEdition: dndEdition ?? this.dndEdition,
      );

  factory SessionMeta.fromJson(Map<String, dynamic> j) => SessionMeta(
        id: j['id'] as String,
        name: j['name'] as String,
        systems: (j['systems'] as List?)?.whereType<String>().toList(),
        mode: _modeFromName(j['mode'] as String?),
        identityColor: (j['identityColor'] as num?)?.toInt(),
        identityIcon: j['identityIcon'] as String?,
        genre: j['genre'] as String?,
        dndEdition: j['dndEdition'] as String?,
      );
}

/// The handoff identity-hue palette (ARGB ints) for per-campaign accents.
/// Assigned at create time, varied across campaigns. See UX-refresh #11.
const kIdentityHues = <int>[
  0xFF9A4A22, // Terracotta
  0xFF5B7A52, // Sage
  0xFF4A5A8A, // Indigo
  0xFF8A4A6A, // Plum
  0xFFB5762A, // Gold
];

/// Picks an identity hue varied by [existingCount] (round-robin) folded with a
/// hash of [sessionId] so re-creates don't collide on the same index. Pure.
int identityHueFor(String sessionId, int existingCount) {
  final h = sessionId.codeUnits.fold<int>(0, (a, c) => (a + c) & 0x7fffffff);
  return kIdentityHues[(existingCount + h) % kIdentityHues.length];
}

/// Identity-icon keys (UI resolves them to IconData via kIdentityIcons). The
/// per-ruleset keys mirror the campaign-preset icons; everything else falls
/// back to a sensible default. Kept as plain strings so models stays
/// Flutter-free.
const _kRulesetIconKey = <String, String>{
  'ironsworn': 'bolt',
  'dnd': 'castle',
  'shadowdark': 'dark_mode',
  'nimble': 'flash_on',
  'draw-steel': 'shield',
  'argosa': 'fort',
  'cairn': 'terrain',
  'knave': 'content_cut',
  'ose': 'auto_stories',
  'kal-arath': 'whatshot',
};

/// Derives a default identity-icon key from a campaign's [systems]: the
/// ruleset's icon if one is enabled, else an oracle/book fallback by mode. Pure.
String identityIconKeyFor(Set<String> systems, CampaignMode mode) {
  for (final s in systems) {
    final k = _kRulesetIconKey[s];
    if (k != null) return k;
  }
  if (mode == CampaignMode.gm) return 'book';
  return 'casino';
}

/// Registry of sessions plus the active one.
class SessionsState {
  const SessionsState({required this.active, required this.sessions});
  final String active;
  final List<SessionMeta> sessions;

  SessionMeta get activeMeta => sessions.firstWhere(
        (s) => s.id == active,
        orElse: () => sessions.first,
      );

  Map<String, dynamic> toJson() => {
        'active': active,
        'sessions': sessions.map((s) => s.toJson()).toList(),
      };

  factory SessionsState.fromJson(Map<String, dynamic> j) => SessionsState(
        active: j['active'] as String,
        sessions: (j['sessions'] as List)
            .map((e) => SessionMeta.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// -- Campaign settings (genre/tone for the oracle interpreter) ---------------
class CampaignSettings {
  const CampaignSettings({
    this.genre = '',
    this.tone = '',
    this.defaultOracle = 'juice',
    this.headerCollapsed = false,
  });
  final String genre;
  final String tone;
  final String defaultOracle;
  final bool headerCollapsed;

  CampaignSettings copyWith({
    String? genre,
    String? tone,
    String? defaultOracle,
    bool? headerCollapsed,
  }) =>
      CampaignSettings(
        genre: genre ?? this.genre,
        tone: tone ?? this.tone,
        defaultOracle: defaultOracle ?? this.defaultOracle,
        headerCollapsed: headerCollapsed ?? this.headerCollapsed,
      );

  factory CampaignSettings.fromJson(Map<String, dynamic> j) => CampaignSettings(
        genre: j['genre'] as String? ?? '',
        tone: j['tone'] as String? ?? '',
        defaultOracle: j['defaultOracle'] as String? ?? 'juice',
        headerCollapsed: (j['headerCollapsed'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'genre': genre,
        'tone': tone,
        'defaultOracle': defaultOracle,
        if (headerCollapsed) 'headerCollapsed': true,
      };
}

/// Lonelog Wargaming addon unit-status vocabulary (default; substitutable).
const kUnitStatuses = [
  'Fresh',
  'Steady',
  'Wavering',
  'Broken',
  'Routed',
  'Rallied',
  'Pinned',
  'Engaged',
  'Exhausted',
];

/// One wargame unit (Lonelog Wargaming addon `[Unit:Name|size|status]`) — a
/// group acting as one entity, NOT an individual.
class Unit {
  const Unit(
      {required this.id, required this.name, this.size = '', this.status = ''});
  final String id;
  final String name;
  final String size; // ×N count or full/half/depleted
  final String status; // from kUnitStatuses (or custom)

  Unit copyWith({String? name, String? size, String? status}) => Unit(
        id: id,
        name: name ?? this.name,
        size: size ?? this.size,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (size.isNotEmpty) 'size': size,
        if (status.isNotEmpty) 'status': status,
      };

  factory Unit.fromJson(Map<String, dynamic> j) => Unit(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        size: (j['size'] as String?) ?? '',
        status: (j['status'] as String?) ?? '',
      );
}

/// One tracked inventory item (Lonelog Resource Tracking addon `[Inv:…]`).
class InvItem {
  const InvItem(
      {required this.id, required this.name, this.qty = 1, this.props = ''});
  final String id;
  final String name;
  final int qty;
  final String props; // freeform: condition, charges x/y, magic, etc.

  InvItem copyWith({String? name, int? qty, String? props}) => InvItem(
        id: id,
        name: name ?? this.name,
        qty: qty ?? this.qty,
        props: props ?? this.props,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'qty': qty,
        if (props.isNotEmpty) 'props': props,
      };

  factory InvItem.fromJson(Map<String, dynamic> j) => InvItem(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        qty: (j['qty'] as int?) ?? 1,
        props: (j['props'] as String?) ?? '',
      );
}

class Rumor {
  const Rumor({
    required this.id,
    required this.text,
    this.resolved = false,
    this.note = '',
  });
  final String id;
  final String text;
  final bool resolved;
  final String note;

  Rumor copyWith({String? text, bool? resolved, String? note}) => Rumor(
        id: id,
        text: text ?? this.text,
        resolved: resolved ?? this.resolved,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        if (resolved) 'resolved': true,
        if (note.isNotEmpty) 'note': note,
      };

  factory Rumor.fromJson(Map<String, dynamic> j) => Rumor(
        id: j['id'] as String,
        text: j['text'] as String,
        resolved: (j['resolved'] as bool?) ?? false,
        note: (j['note'] as String?) ?? '',
      );
}

class Track {
  const Track({
    required this.id,
    required this.name,
    this.filled = 0,
    this.max = 10,
    this.note = '',
  });
  final String id;
  final String name;
  final int filled;
  final int max;
  final String note;

  Track copyWith({String? name, int? filled, int? max, String? note}) => Track(
        id: id,
        name: name ?? this.name,
        filled: filled ?? this.filled,
        max: max ?? this.max,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'filled': filled,
        'max': max,
        if (note.isNotEmpty) 'note': note,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        name: j['name'] as String,
        filled: (j['filled'] as int?) ?? 0,
        max: (j['max'] as int?) ?? 10,
        note: (j['note'] as String?) ?? '',
      );
}

// -- Ironsworn-family foe entries (from ruleset npc_collections) --------------

/// Rank label by 1-based index (Ironsworn 1=Troublesome … 5=Epic).
const kRankNames = [
  '',
  'Troublesome',
  'Dangerous',
  'Formidable',
  'Extreme',
  'Epic'
];

class FoeEntry {
  const FoeEntry({
    required this.id,
    required this.name,
    required this.rank,
    required this.nature,
    required this.features,
    required this.drives,
    required this.tactics,
  });
  final String id;
  final String name;
  final int rank;
  final String nature;
  final List<String> features;
  final List<String> drives;
  final List<String> tactics;

  static FoeEntry? fromJson(dynamic j) {
    if (j is! Map) return null;
    final id = j['id'] as String?;
    final name = j['name'] as String?;
    if (id == null || name == null) return null;
    return FoeEntry(
      id: id,
      name: name,
      rank: (j['rank'] as num?)?.toInt() ?? 1,
      nature: j['nature'] as String? ?? '',
      features: (j['features'] as List?)?.cast<String>() ?? const [],
      drives: (j['drives'] as List?)?.cast<String>() ?? const [],
      tactics: (j['tactics'] as List?)?.cast<String>() ?? const [],
    );
  }
}

class FoeCollection {
  const FoeCollection({
    required this.name,
    required this.ruleset,
    required this.entries,
  });
  final String name;
  final String ruleset;
  final List<FoeEntry> entries;

  static FoeCollection? fromJson(dynamic j) {
    if (j is! Map) return null;
    final name = j['name'] as String?;
    if (name == null) return null;
    return FoeCollection(
      name: name,
      ruleset: j['ruleset'] as String? ?? '',
      entries: (j['entries'] as List?)
              ?.map(FoeEntry.fromJson)
              .whereType<FoeEntry>()
              .toList() ??
          const [],
    );
  }
}
