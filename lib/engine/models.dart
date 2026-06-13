/// Plain immutable models for engine output and persisted state.
/// No freezed/codegen — the data is small and stable.

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
class DungeonRoom {
  const DungeonRoom({
    required this.id,
    required this.x,
    required this.y,
    required this.title,
    this.detail = '',
  });
  final String id;
  final int x;
  final int y;
  final String title; // e.g. the room's oracle headline
  final String detail; // full GenResult.asText (+ appended linger lines)

  DungeonRoom copyWith({String? title, String? detail}) => DungeonRoom(
        id: id,
        x: x,
        y: y,
        title: title ?? this.title,
        detail: detail ?? this.detail,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'x': x, 'y': y, 'title': title, 'detail': detail};

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
    );
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
  });
  final int col;
  final int row;
  final int envRow; // 1..10 -> wilderness_environment table
  final bool lost;

  HexCell copyWith({int? envRow, bool? lost}) => HexCell(
        col: col,
        row: row,
        envRow: envRow ?? this.envRow,
        lost: lost ?? this.lost,
      );

  Map<String, dynamic> toJson() =>
      {'col': col, 'row': row, 'envRow': envRow, 'lost': lost};

  /// Parses one hex entry; null for anything without a map shape and int
  /// coordinates. envRow clamps into the table range 1..10.
  static HexCell? maybeFromJson(dynamic j) {
    if (j is! Map || j['col'] is! int || j['row'] is! int) return null;
    return HexCell(
      col: j['col'] as int,
      row: j['row'] as int,
      envRow: ((j['envRow'] as int?) ?? 1).clamp(1, 10),
      lost: (j['lost'] as bool?) ?? false,
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
const kAllSystems = {'juice', 'mythic', 'ironsworn', 'party'};

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
