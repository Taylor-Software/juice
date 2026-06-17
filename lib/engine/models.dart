/// Plain immutable models for engine output and persisted state.
/// No freezed/codegen — the data is small and stable.
library;

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

/// Kind of journal entry: player prose, a tool result, or a scene divider.
enum JournalKind { text, result, scene }

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

  JournalEntry copyWith({
    String? title,
    String? body,
    String? threadId,
    bool clearThreadId = false,
    List<String>? tags,
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
        payload: payload,
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
      );
}

/// Persisted thread (Mythic-style "thread"/vow the player tracks).
class Thread {
  const Thread({
    required this.id,
    required this.title,
    this.note = '',
    this.open = true,
    this.pinned = false,
  });
  final String id;
  final String title;
  final String note;
  final bool open;
  final bool pinned;

  Thread copyWith({String? title, String? note, bool? open, bool? pinned}) =>
      Thread(
        id: id,
        title: title ?? this.title,
        note: note ?? this.note,
        open: open ?? this.open,
        pinned: pinned ?? this.pinned,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'open': open,
        if (pinned) 'pinned': true,
      };

  factory Thread.fromJson(Map<String, dynamic> j) => Thread(
        id: j['id'] as String,
        title: j['title'] as String,
        note: (j['note'] as String?) ?? '',
        open: (j['open'] as bool?) ?? true,
        pinned: (j['pinned'] as bool?) ?? false,
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

/// A persisted asset on an Ironsworn sheet. [enabledAbilities] parallels the
/// asset definition's abilities[]; only the toggled-on flags are play state.
class AssetState {
  const AssetState({
    required this.assetId,
    required this.name,
    this.category = '',
    this.enabledAbilities = const [],
  });
  final String assetId; // datasworn _id
  final String name;
  final String category;
  final List<bool> enabledAbilities;

  AssetState copyWith({List<bool>? enabledAbilities}) => AssetState(
        assetId: assetId,
        name: name,
        category: category,
        enabledAbilities: enabledAbilities ?? this.enabledAbilities,
      );

  Map<String, dynamic> toJson() => {
        'assetId': assetId,
        'name': name,
        if (category.isNotEmpty) 'category': category,
        'enabledAbilities': enabledAbilities,
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
    int intOr(dynamic v, int d) => v is int ? v : d;
    final dbs = j['debilities'] is List
        ? (j['debilities'] as List)
            .whereType<String>()
            .where(kIronswornDebilities.containsKey)
            .toSet()
        : <String>{};
    final maxM = 10 - dbs.length;
    return IronswornSheet(
      edge: intOr(j['edge'], 1).clamp(1, 3),
      heart: intOr(j['heart'], 1).clamp(1, 3),
      iron: intOr(j['iron'], 1).clamp(1, 3),
      shadow: intOr(j['shadow'], 1).clamp(1, 3),
      wits: intOr(j['wits'], 1).clamp(1, 3),
      health: intOr(j['health'], 5).clamp(0, 5),
      spirit: intOr(j['spirit'], 5).clamp(0, 5),
      supply: intOr(j['supply'], 5).clamp(0, 5),
      momentum: intOr(j['momentum'], 2).clamp(-6, maxM),
      xpEarned: intOr(j['xpEarned'], 0).clamp(0, 1 << 31),
      xpSpent: intOr(j['xpSpent'], 0).clamp(0, 1 << 31),
      bonds: intOr(j['bonds'], 0).clamp(0, 10),
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
  });
  final String id;
  final String name;
  final String? characterId;
  final int initiative;
  final CharTrack? track; // null for linked combatants
  final List<String> tags;
  final bool defeated;

  Combatant copyWith({
    int? initiative,
    CharTrack? track,
    List<String>? tags,
    bool? defeated,
  }) =>
      Combatant(
        id: id,
        name: name,
        characterId: characterId,
        initiative: initiative ?? this.initiative,
        track: track ?? this.track,
        tags: tags ?? this.tags,
        defeated: defeated ?? this.defeated,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'characterId': characterId,
        'initiative': initiative,
        'track': track?.toJson(),
        'tags': tags,
        'defeated': defeated,
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
      );
}

/// Turn-ordered encounter. [combatants] order IS the turn order.
class EncounterState {
  const EncounterState({
    this.combatants = const [],
    this.turnIndex = 0,
    this.round = 1,
  });
  final List<Combatant> combatants;
  final int turnIndex;
  final int round;

  EncounterState copyWith(
          {List<Combatant>? combatants, int? turnIndex, int? round}) =>
      EncounterState(
        combatants: combatants ?? this.combatants,
        turnIndex: turnIndex ?? this.turnIndex,
        round: round ?? this.round,
      );

  Map<String, dynamic> toJson() => {
        'combatants': combatants.map((c) => c.toJson()).toList(),
        'turnIndex': turnIndex,
        'round': round,
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
  });
  final String id;
  final int x;
  final int y;
  final String title; // e.g. the room's oracle headline
  final String detail; // full GenResult.asText (+ appended linger lines)
  final String status; // Lonelog room status (cleared/looted/…); '' = unset

  DungeonRoom copyWith({String? title, String? detail, String? status}) =>
      DungeonRoom(
        id: id,
        x: x,
        y: y,
        title: title ?? this.title,
        detail: detail ?? this.detail,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'title': title,
        'detail': detail,
        if (status.isNotEmpty) 'status': status,
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
    int? intOr(dynamic v) => v is int ? v : null;
    List<String> strings(dynamic v) =>
        v is List ? v.whereType<String>().toList() : const [];
    return CharacterEmulation(
      agendaKey: intOr(j['agendaKey']),
      focusKey: intOr(j['focusKey']),
      mood: j['mood'] is String ? j['mood'] as String : null,
      tokens: intOr(j['tokens']) ?? 0,
      prominentTags: strings(j['prominentTags']),
      usedTags: strings(j['usedTags']),
      hexIndex: intOr(j['hexIndex']),
    );
  }
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
    this.starred = false,
  });
  final String id;
  final String name;
  final String note;
  final List<CharStat> stats;
  final List<CharTrack> tracks;
  final List<String> tags;

  /// Party-emulator state; null until the Party tool writes it.
  final CharacterEmulation? emulation;

  /// Whether this character is starred in the campaign header.
  final bool starred;

  /// Lists are replaced wholesale when provided; null keeps the current list.
  Character copyWith({
    String? name,
    String? note,
    List<CharStat>? stats,
    List<CharTrack>? tracks,
    List<String>? tags,
    CharacterEmulation? emulation,
    bool clearEmulation = false,
    bool? starred,
  }) =>
      Character(
        id: id,
        name: name ?? this.name,
        note: note ?? this.note,
        stats: stats ?? this.stats,
        tracks: tracks ?? this.tracks,
        tags: tags ?? this.tags,
        emulation: clearEmulation ? null : (emulation ?? this.emulation),
        starred: starred ?? this.starred,
      );

  /// 'emulation' and 'starred' are written only when non-null/true so existing
  /// characters and campaign files stay byte-stable until the features are used.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'note': note,
        'stats': stats.map((s) => s.toJson()).toList(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'tags': tags,
        if (emulation != null) 'emulation': emulation!.toJson(),
        if (starred) 'starred': true,
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
        starred: (j['starred'] as bool?) ?? false,
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

/// A campaign/session: an isolated journal, threads, characters, crawl.
class SessionMeta {
  const SessionMeta({required this.id, required this.name, this.systems});
  final String id;
  final String name;

  /// Enabled optional systems; null means all (legacy campaigns).
  final List<String>? systems;

  /// Resolved set: the declared systems, or every system when unset.
  Set<String> get enabledSystems => systems?.toSet() ?? kAllSystems;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (systems != null) 'systems': systems,
      };

  factory SessionMeta.fromJson(Map<String, dynamic> j) => SessionMeta(
        id: j['id'] as String,
        name: j['name'] as String,
        systems: (j['systems'] as List?)?.whereType<String>().toList(),
      );
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
