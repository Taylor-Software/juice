/// Dungeons, hexes, settlements and the campaign map.
///
/// Part of the `models` library — see models.dart. Split for
/// navigability only; parts share one scope, so the private helpers
/// (`_intOr`, `_strOr`, `_strSet`) and every cross-reference still work.
part of '../models.dart';

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

/// One mapped dungeon room: its grid position, authored detail, and — for
/// classic (Roll 4 Ruin) rooms — its multi-cell footprint, doors, and any
/// level movement it leads to.
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
    this.levelDelta = 0,
    this.crossTo,
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
  final int levelDelta; // -1 down / +1 up transition room; 0 = none
  final String? crossTo; // branch crossover: 'dungeon' | 'cave'; null = none

  DungeonRoom copyWith({
    String? title,
    String? detail,
    String? status,
    List<(int, int)>? footprint,
    List<DoorEdge>? doors,
    String? roomType,
    int? levelDelta,
    String? crossTo,
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
        levelDelta: levelDelta ?? this.levelDelta,
        crossTo: crossTo ?? this.crossTo,
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
        if (levelDelta != 0) 'ld': levelDelta,
        if (crossTo != null) 'xt': crossTo,
      };

  /// Strict parse for known-good JSON (round-trips [toJson]).
  factory DungeonRoom.fromJson(Map<String, dynamic> j) => maybeFromJson(j)!;

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
      levelDelta: (j['ld'] as int?) ?? 0,
      crossTo: j['xt'] as String?,
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
    this.sketchEntryId,
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

  /// A sketch-map anchored to this hex: the id of a [JournalKind.sketch]
  /// entry (drawn town/building map, PDF page). Null = none.
  final String? sketchEntryId;

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
    String? sketchEntryId,
    bool clearSketchEntry = false,
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
        sketchEntryId:
            clearSketchEntry ? null : (sketchEntryId ?? this.sketchEntryId),
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
        if (sketchEntryId != null) 'sketch': sketchEntryId,
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
      sketchEntryId: j['sketch'] as String?,
    );
  }
}

/// A reference to a place on the session's single map: a dungeon room id,
/// or a hex by (col,row). Empty when none set.
class LocationRef {
  const LocationRef(
      {this.roomId, this.hexCol, this.hexRow, this.sketchEntryId});
  final String? roomId;
  final int? hexCol;
  final int? hexRow;

  /// A sketch-map place: the id of a [JournalKind.sketch] entry (free-drawn
  /// map, PDF page, or map snapshot) acting as the party's current map.
  final String? sketchEntryId;

  bool get isEmpty =>
      roomId == null &&
      hexCol == null &&
      hexRow == null &&
      sketchEntryId == null;

  Map<String, dynamic> toJson() => {
        if (roomId != null) 'roomId': roomId,
        if (hexCol != null) 'hexCol': hexCol,
        if (hexRow != null) 'hexRow': hexRow,
        if (sketchEntryId != null) 'sketch': sketchEntryId,
      };

  factory LocationRef.fromJson(Map<String, dynamic> j) => LocationRef(
        roomId: j['roomId'] as String?,
        hexCol: (j['hexCol'] as num?)?.toInt(),
        hexRow: (j['hexRow'] as num?)?.toInt(),
        sketchEntryId: j['sketch'] as String?,
      );

  /// True when [other] refers to the same place (sketch-entry or room id
  /// match, or matching hex col+row). Two empty refs do NOT match (nothing to
  /// link on); refs of different kinds never match.
  bool matches(LocationRef? other) {
    if (other == null || isEmpty || other.isEmpty) return false;
    if (sketchEntryId != null || other.sketchEntryId != null) {
      return sketchEntryId == other.sketchEntryId;
    }
    if (roomId != null || other.roomId != null) return roomId == other.roomId;
    return hexCol == other.hexCol && hexRow == other.hexRow;
  }
}

/// Journal entries whose [JournalEntry.location] matches [loc] (a room-id or
/// hex-col/row match via [LocationRef.matches]). Used by the map panes'
/// "what happened here" backlink. Order follows [entries] (newest-first, the
/// journal's storage order).
List<JournalEntry> entriesAtLocation(
        List<JournalEntry> entries, LocationRef loc) =>
    entries.where((e) => loc.matches(e.location)).toList(growable: false);

/// Tracked [Place]s pinned to [loc] (map-cell match via [LocationRef.matches]).
/// The map detail cards' "places here" list.
List<Place> placesAtLocation(List<Place> places, LocationRef loc) =>
    places.where((p) => loc.matches(p.location)).toList(growable: false);

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

/// One dungeon/cave level of the classic crawler. [branch] is 'dungeon' or
/// 'cave'; [typeName]/[note] carry the rolled A2/D2 type; [stone] the E5
/// cavestone (cave levels only, '' otherwise).
class DungeonLevel {
  const DungeonLevel({
    required this.depth,
    this.branch = 'dungeon',
    this.typeName = '',
    this.note = '',
    this.stone = '',
    this.rooms = const [],
    this.corridors = const [],
    this.currentRoomId,
  });
  final int depth;
  final String branch;
  final String typeName;
  final String note;
  final String stone;
  final List<DungeonRoom> rooms;
  final List<List<String>> corridors; // [idA, idB] pairs
  final String? currentRoomId;

  DungeonLevel copyWith({
    List<DungeonRoom>? rooms,
    List<List<String>>? corridors,
    String? currentRoomId,
    bool clearCurrentRoomId = false,
  }) =>
      DungeonLevel(
        depth: depth,
        branch: branch,
        typeName: typeName,
        note: note,
        stone: stone,
        rooms: rooms ?? this.rooms,
        corridors: corridors ?? this.corridors,
        currentRoomId:
            clearCurrentRoomId ? null : (currentRoomId ?? this.currentRoomId),
      );

  Map<String, dynamic> toJson() => {
        'depth': depth,
        if (branch != 'dungeon') 'branch': branch,
        if (typeName.isNotEmpty) 'type': typeName,
        if (note.isNotEmpty) 'note': note,
        if (stone.isNotEmpty) 'stone': stone,
        if (rooms.isNotEmpty) 'rooms': rooms.map((r) => r.toJson()).toList(),
        if (corridors.isNotEmpty) 'corridors': corridors,
        if (currentRoomId != null) 'currentRoomId': currentRoomId,
      };

  /// Parses one level entry; null for anything without a map shape.
  /// Tolerant: malformed room entries are skipped; corridor entries must
  /// be 2-string lists, else skipped.
  static DungeonLevel? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    return DungeonLevel(
      depth: (j['depth'] as int?) ?? 1,
      branch: (j['branch'] as String?) ?? 'dungeon',
      typeName: (j['type'] as String?) ?? '',
      note: (j['note'] as String?) ?? '',
      stone: (j['stone'] as String?) ?? '',
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
    );
  }
}

/// Persisted map state: dungeon levels + revealed hex field. The dungeon
/// graph lives on [levels]; [rooms]/[corridors]/[currentRoomId] are views
/// over the [activeLevel] so existing consumers keep working.
class DungeonSite {
  const DungeonSite({
    required this.id,
    this.name = 'Dungeon',
    this.levels = const [],
    this.activeLevel = 0,
    this.anchorHexCol,
    this.anchorHexRow,
  });

  final String id;
  final String name;
  final List<DungeonLevel> levels;
  final int activeLevel; // index into [levels]

  /// The world hex this dungeon sits at (map-layer hierarchy); null =
  /// unanchored — every layer can exist parentless.
  final int? anchorHexCol;
  final int? anchorHexRow;

  bool get hasAnchor => anchorHexCol != null && anchorHexRow != null;

  DungeonSite copyWith({
    String? name,
    List<DungeonLevel>? levels,
    int? activeLevel,
    int? anchorHexCol,
    int? anchorHexRow,
    bool clearAnchor = false,
  }) =>
      DungeonSite(
        id: id,
        name: name ?? this.name,
        levels: levels ?? this.levels,
        activeLevel: activeLevel ?? this.activeLevel,
        anchorHexCol: clearAnchor ? null : (anchorHexCol ?? this.anchorHexCol),
        anchorHexRow: clearAnchor ? null : (anchorHexRow ?? this.anchorHexRow),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (levels.isNotEmpty) 'levels': levels.map((l) => l.toJson()).toList(),
        if (activeLevel != 0) 'activeLevel': activeLevel,
        if (anchorHexCol != null) 'anchorHexCol': anchorHexCol,
        if (anchorHexRow != null) 'anchorHexRow': anchorHexRow,
      };

  static DungeonSite? maybeFromJson(dynamic j) {
    if (j is! Map || j['id'] is! String) return null;
    return DungeonSite(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? 'Dungeon',
      levels: ((j['levels'] as List?) ?? const [])
          .map(DungeonLevel.maybeFromJson)
          .whereType<DungeonLevel>()
          .toList(),
      activeLevel: (j['activeLevel'] as int?) ?? 0,
      anchorHexCol: j['anchorHexCol'] as int?,
      anchorHexRow: j['anchorHexRow'] as int?,
    );
  }
}

/// One building/location inside a [SettlementSite] (facts-only: a name +
/// freeform type + note). Deferred: a building can later link to a dungeon.
class Building {
  const Building(
      {required this.id, this.name = '', this.type = '', this.note = ''});
  final String id;
  final String name;
  final String type;
  final String note;

  Building copyWith({String? name, String? type, String? note}) => Building(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (name.isNotEmpty) 'name': name,
        if (type.isNotEmpty) 'type': type,
        if (note.isNotEmpty) 'note': note,
      };

  static Building? maybeFromJson(dynamic j) => j is Map
      ? Building(
          id: (j['id'] as String?) ?? '',
          name: (j['name'] as String?) ?? '',
          type: (j['type'] as String?) ?? '',
          note: (j['note'] as String?) ?? '')
      : null;
}

/// A settlement (city/town/village) on the session map — a flat list of
/// [buildings], optionally anchored to a world hex (parallel to [DungeonSite]).
class SettlementSite {
  const SettlementSite({
    required this.id,
    this.name = 'Settlement',
    this.kind = '',
    this.buildings = const [],
    this.note = '',
    this.anchorHexCol,
    this.anchorHexRow,
  });

  final String id;
  final String name;

  /// Freeform kind label (Village / Town / City …); empty until set.
  final String kind;
  final List<Building> buildings;
  final String note;
  final int? anchorHexCol;
  final int? anchorHexRow;

  bool get hasAnchor => anchorHexCol != null && anchorHexRow != null;

  SettlementSite copyWith({
    String? name,
    String? kind,
    List<Building>? buildings,
    String? note,
    int? anchorHexCol,
    int? anchorHexRow,
    bool clearAnchor = false,
  }) =>
      SettlementSite(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        buildings: buildings ?? this.buildings,
        note: note ?? this.note,
        anchorHexCol: clearAnchor ? null : (anchorHexCol ?? this.anchorHexCol),
        anchorHexRow: clearAnchor ? null : (anchorHexRow ?? this.anchorHexRow),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (kind.isNotEmpty) 'kind': kind,
        if (buildings.isNotEmpty)
          'buildings': buildings.map((b) => b.toJson()).toList(),
        if (note.isNotEmpty) 'note': note,
        if (anchorHexCol != null) 'anchorHexCol': anchorHexCol,
        if (anchorHexRow != null) 'anchorHexRow': anchorHexRow,
      };

  static SettlementSite? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    return SettlementSite(
      id: (j['id'] as String?) ?? '',
      name: (j['name'] as String?) ?? 'Settlement',
      kind: (j['kind'] as String?) ?? '',
      buildings: ((j['buildings'] as List?) ?? const [])
          .map(Building.maybeFromJson)
          .whereType<Building>()
          .toList(),
      note: (j['note'] as String?) ?? '',
      anchorHexCol: j['anchorHexCol'] as int?,
      anchorHexRow: j['anchorHexRow'] as int?,
    );
  }
}

/// Every map in one campaign: the dungeon sites (each with its own levels),
/// the settlements, and the shared hex world. `rooms`/`levels`/`corridors`
/// are VIEWS onto the active dungeon, so edits apply where the player is.
class MapState {
  const MapState({
    this.dungeons = const [],
    this.activeDungeonId,
    this.settlements = const [],
    this.activeSettlementId,
    this.hexes = const [],
    this.currentHexCol,
    this.currentHexRow,
  });

  /// Every dungeon on the session map, each with its own levels + optional
  /// world-hex anchor.
  final List<DungeonSite> dungeons;

  /// Which dungeon the Dungeon pane shows/edits; falls back to the first.
  final String? activeDungeonId;

  /// Every settlement on the session map, each with its buildings + optional
  /// world-hex anchor.
  final List<SettlementSite> settlements;

  /// Which settlement the Town pane shows/edits; falls back to the first.
  final String? activeSettlementId;

  final List<HexCell> hexes;
  final int? currentHexCol;
  final int? currentHexRow;

  DungeonSite? get activeDungeon => dungeons.isEmpty
      ? null
      : dungeons.firstWhere((d) => d.id == activeDungeonId,
          orElse: () => dungeons.first);

  SettlementSite? get activeSettlement => settlements.isEmpty
      ? null
      : settlements.firstWhere((s) => s.id == activeSettlementId,
          orElse: () => settlements.first);

  /// The dungeon anchored at hex ([col],[row]), or null.
  DungeonSite? dungeonAnchoredAt(int col, int row) {
    for (final d in dungeons) {
      if (d.anchorHexCol == col && d.anchorHexRow == row) return d;
    }
    return null;
  }

  /// The settlement anchored at hex ([col],[row]), or null.
  SettlementSite? settlementAnchoredAt(int col, int row) {
    for (final s in settlements) {
      if (s.anchorHexCol == col && s.anchorHexRow == row) return s;
    }
    return null;
  }

  /// Levels of the ACTIVE dungeon (compat view; empty when none).
  List<DungeonLevel> get levels => activeDungeon?.levels ?? const [];

  /// Active-level index of the ACTIVE dungeon (compat view).
  int get activeLevel => activeDungeon?.activeLevel ?? 0;

  /// The active dungeon's world-hex anchor (compat view for the pane chips).
  int? get anchorHexCol => activeDungeon?.anchorHexCol;
  int? get anchorHexRow => activeDungeon?.anchorHexRow;
  bool get hasAnchor => activeDungeon?.hasAnchor ?? false;

  DungeonLevel? get _active =>
      levels.isEmpty ? null : levels[activeLevel.clamp(0, levels.length - 1)];

  /// Rooms of the active level (compat view; empty when no levels).
  List<DungeonRoom> get rooms => _active?.rooms ?? const [];

  /// Corridors of the active level (compat view).
  List<List<String>> get corridors => _active?.corridors ?? const [];

  /// Current room of the active level (compat view).
  String? get currentRoomId => _active?.currentRoomId;

  /// The active dungeon's level at [depth], or null when none exists.
  DungeonLevel? levelAt(int depth) {
    for (final l in levels) {
      if (l.depth == depth) return l;
    }
    return null;
  }

  /// Dungeon-field edits ([levels]/[activeLevel]/[rooms]/[corridors]/
  /// [currentRoomId]/anchor) apply to the ACTIVE dungeon — seeding a default
  /// dungeon (and depth-1 level for room edits) when none exists yet, so the
  /// single-dungeon call sites keep working unchanged. When [dungeons]/
  /// [activeDungeonId] are also passed, they apply first, then the dungeon
  /// edits hit the new active dungeon.
  MapState copyWith({
    List<DungeonSite>? dungeons,
    String? activeDungeonId,
    List<SettlementSite>? settlements,
    String? activeSettlementId,
    List<DungeonLevel>? levels,
    int? activeLevel,
    List<DungeonRoom>? rooms,
    List<List<String>>? corridors,
    String? currentRoomId,
    bool clearCurrentRoomId = false,
    List<HexCell>? hexes,
    int? currentHexCol,
    int? currentHexRow,
    bool clearCurrentHex = false,
    int? anchorHexCol,
    int? anchorHexRow,
    bool clearAnchor = false,
  }) {
    var newDungeons = dungeons ?? this.dungeons;
    var newActiveId = activeDungeonId ?? this.activeDungeonId;
    final hasDungeonEdit = levels != null ||
        activeLevel != null ||
        rooms != null ||
        corridors != null ||
        currentRoomId != null ||
        clearCurrentRoomId ||
        anchorHexCol != null ||
        anchorHexRow != null ||
        clearAnchor;
    if (hasDungeonEdit) {
      if (newDungeons.isEmpty) {
        newDungeons = const [DungeonSite(id: 'd1')];
        newActiveId ??= 'd1';
      }
      var idx = newDungeons.indexWhere((d) => d.id == newActiveId);
      if (idx < 0) idx = 0;
      var newLevels = levels ?? newDungeons[idx].levels;
      final newActiveLevel = activeLevel ?? newDungeons[idx].activeLevel;
      final hasRoomEdit = rooms != null ||
          corridors != null ||
          currentRoomId != null ||
          clearCurrentRoomId;
      if (hasRoomEdit) {
        if (newLevels.isEmpty) {
          newLevels = const [DungeonLevel(depth: 1)];
        }
        final i = newActiveLevel.clamp(0, newLevels.length - 1);
        newLevels = [
          for (var k = 0; k < newLevels.length; k++)
            k == i
                ? newLevels[k].copyWith(
                    rooms: rooms,
                    corridors: corridors,
                    currentRoomId: currentRoomId,
                    clearCurrentRoomId: clearCurrentRoomId,
                  )
                : newLevels[k],
        ];
      }
      final edited = newDungeons[idx].copyWith(
        levels: newLevels,
        activeLevel: newActiveLevel,
        anchorHexCol: anchorHexCol,
        anchorHexRow: anchorHexRow,
        clearAnchor: clearAnchor,
      );
      newDungeons = [
        for (var k = 0; k < newDungeons.length; k++)
          k == idx ? edited : newDungeons[k],
      ];
    }
    return MapState(
      dungeons: newDungeons,
      activeDungeonId: newActiveId,
      settlements: settlements ?? this.settlements,
      activeSettlementId: activeSettlementId ?? this.activeSettlementId,
      hexes: hexes ?? this.hexes,
      currentHexCol:
          clearCurrentHex ? null : (currentHexCol ?? this.currentHexCol),
      currentHexRow:
          clearCurrentHex ? null : (currentHexRow ?? this.currentHexRow),
    );
  }

  Map<String, dynamic> toJson() => {
        if (dungeons.isNotEmpty)
          'dungeons': dungeons.map((d) => d.toJson()).toList(),
        if (activeDungeonId != null) 'activeDungeon': activeDungeonId,
        if (settlements.isNotEmpty)
          'settlements': settlements.map((s) => s.toJson()).toList(),
        if (activeSettlementId != null) 'activeSettlement': activeSettlementId,
        'hexes': hexes.map((h) => h.toJson()).toList(),
        'currentHexCol': currentHexCol,
        'currentHexRow': currentHexRow,
      };

  /// Tolerant: malformed dungeon/level/hex entries are skipped. Legacy
  /// single-dungeon JSON (top-level `levels` + optional `anchorHexCol/Row`,
  /// or the older bare `rooms`/`corridors`/`currentRoomId`) lifts into one
  /// DungeonSite.
  factory MapState.fromJson(Map<String, dynamic> j) {
    List<DungeonSite> dungeons;
    String? activeId;
    if (j['dungeons'] is List) {
      dungeons = (j['dungeons'] as List)
          .map(DungeonSite.maybeFromJson)
          .whereType<DungeonSite>()
          .toList();
      activeId = j['activeDungeon'] as String?;
    } else {
      List<DungeonLevel> levels;
      var activeLevel = 0;
      if (j['levels'] is List) {
        levels = (j['levels'] as List)
            .map(DungeonLevel.maybeFromJson)
            .whereType<DungeonLevel>()
            .toList();
        activeLevel = (j['activeLevel'] as int?) ?? 0;
      } else {
        final rooms = ((j['rooms'] as List?) ?? const [])
            .map(DungeonRoom.maybeFromJson)
            .whereType<DungeonRoom>()
            .toList();
        levels = rooms.isEmpty
            ? const []
            : [
                DungeonLevel(
                  depth: 1,
                  rooms: rooms,
                  corridors: [
                    for (final e in (j['corridors'] as List?) ?? const [])
                      if (e is List &&
                          e.length == 2 &&
                          e.every((id) => id is String))
                        List<String>.from(e),
                  ],
                  currentRoomId: j['currentRoomId'] as String?,
                ),
              ];
      }
      final hasAnchor = j['anchorHexCol'] is int && j['anchorHexRow'] is int;
      dungeons = levels.isEmpty && !hasAnchor
          ? const []
          : [
              DungeonSite(
                id: 'd1',
                levels: levels,
                activeLevel: activeLevel,
                anchorHexCol: j['anchorHexCol'] as int?,
                anchorHexRow: j['anchorHexRow'] as int?,
              ),
            ];
      activeId = dungeons.isEmpty ? null : 'd1';
    }
    final settlements = ((j['settlements'] as List?) ?? const [])
        .map(SettlementSite.maybeFromJson)
        .whereType<SettlementSite>()
        .toList();
    return MapState(
      dungeons: dungeons,
      activeDungeonId: activeId,
      settlements: settlements,
      activeSettlementId: (j['activeSettlement'] as String?) ??
          (settlements.isEmpty ? null : settlements.first.id),
      hexes: ((j['hexes'] as List?) ?? const [])
          .map(HexCell.maybeFromJson)
          .whereType<HexCell>()
          .toList(),
      currentHexCol: j['currentHexCol'] as int?,
      currentHexRow: j['currentHexRow'] as int?,
    );
  }
}
