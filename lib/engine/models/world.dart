/// World trackers: units, inventory, rumors, places, NPCs, foes.
///
/// Part of the `models` library — see models.dart. Split for
/// navigability only; parts share one scope, so the private helpers
/// (`_intOr`, `_strOr`, `_strSet`) and every cross-reference still work.
part of '../models.dart';

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

/// Kind of a tracked [Place] (a named world location, distinct from the map's
/// coordinate cells — a Place may pin to one via [Place.location] but need not).
enum PlaceKind { settlement, dungeon, wilderness, landmark, other }

PlaceKind _placeKindFromName(String? n) => switch (n) {
      'settlement' => PlaceKind.settlement,
      'dungeon' => PlaceKind.dungeon,
      'wilderness' => PlaceKind.wilderness,
      'landmark' => PlaceKind.landmark,
      _ => PlaceKind.other,
    };

/// A named place in the world the party knows about — the Places tracker's
/// entity (session-scoped, like [Thread]). Optionally pinned to a map
/// cell via [location] so journal entries logged there back-link to it.
class Place {
  const Place({
    required this.id,
    required this.name,
    this.kind = PlaceKind.other,
    this.note = '',
    this.location,
  });
  final String id;
  final String name;
  final PlaceKind kind;
  final String note;
  final LocationRef? location;

  Place copyWith({
    String? name,
    PlaceKind? kind,
    String? note,
    LocationRef? location,
    bool clearLocation = false,
  }) =>
      Place(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        note: note ?? this.note,
        location: clearLocation ? null : (location ?? this.location),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (kind != PlaceKind.other) 'kind': kind.name,
        if (note.isNotEmpty) 'note': note,
        if (location != null) 'loc': location!.toJson(),
      };

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        kind: _placeKindFromName(j['kind'] as String?),
        note: (j['note'] as String?) ?? '',
        location: j['loc'] is Map
            ? LocationRef.fromJson((j['loc'] as Map).cast<String, dynamic>())
            : null,
      );
}

/// How a tracked [Npc] regards the party (drives the card's status dot).
enum NpcDisposition { friendly, neutral, hostile, unknown }

NpcDisposition _dispositionFromName(String? n) => switch (n) {
      'friendly' => NpcDisposition.friendly,
      'hostile' => NpcDisposition.hostile,
      'unknown' => NpcDisposition.unknown,
      _ => NpcDisposition.neutral,
    };

/// A world NPC the party has met — the People tracker's entity. Lightweight and
/// distinct from a roster [Character] (PCs + hirelings/companions, which carry
/// sheets/HP); an Npc can be promoted into a companion Character when it joins
/// the party. Optionally tied to a [Place] via [placeId] (where it was met).
/// A directed tie from one [Npc] to another: "[label] → [npcId]" (e.g.
/// "brother", "rival", "employer").
class NpcRelation {
  const NpcRelation(this.npcId, this.label);
  final String npcId;
  final String label;

  Map<String, dynamic> toJson() =>
      {'npc': npcId, if (label.isNotEmpty) 'label': label};

  static NpcRelation? maybeFromJson(Object? raw) {
    if (raw is! Map || raw['npc'] is! String) return null;
    return NpcRelation(raw['npc'] as String, (raw['label'] as String?) ?? '');
  }
}

/// A tracked person in the world. Lighter than a roster [Character] (no
/// sheet); can be pinned to a [Place] and promoted to a companion if they
/// join the party.
class Npc {
  const Npc({
    required this.id,
    required this.name,
    this.race = '',
    this.role = '',
    this.disposition = NpcDisposition.neutral,
    this.note = '',
    this.placeId,
    this.relations = const [],
  });
  final String id;
  final String name;

  /// Freeform ancestry/species, e.g. "Human", "Half-Orc". Omitted when empty.
  final String race;

  /// Freeform world role/vocation, e.g. "Innkeeper", "Caravan master".
  final String role;
  final NpcDisposition disposition;
  final String note;

  /// Id of the [Place] this NPC is associated with; null when unplaced.
  final String? placeId;

  /// Directed ties to other NPCs (this NPC's "brother", "rival", …).
  final List<NpcRelation> relations;

  Npc copyWith({
    String? name,
    String? race,
    String? role,
    NpcDisposition? disposition,
    String? note,
    String? placeId,
    bool clearPlace = false,
    List<NpcRelation>? relations,
  }) =>
      Npc(
        id: id,
        name: name ?? this.name,
        race: race ?? this.race,
        role: role ?? this.role,
        disposition: disposition ?? this.disposition,
        note: note ?? this.note,
        placeId: clearPlace ? null : (placeId ?? this.placeId),
        relations: relations ?? this.relations,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (race.isNotEmpty) 'race': race,
        if (role.isNotEmpty) 'role': role,
        if (disposition != NpcDisposition.neutral) 'disp': disposition.name,
        if (note.isNotEmpty) 'note': note,
        if (placeId != null) 'placeId': placeId,
        if (relations.isNotEmpty)
          'rel': relations.map((r) => r.toJson()).toList(),
      };

  factory Npc.fromJson(Map<String, dynamic> j) => Npc(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        race: (j['race'] as String?) ?? '',
        role: (j['role'] as String?) ?? '',
        disposition: _dispositionFromName(j['disp'] as String?),
        note: (j['note'] as String?) ?? '',
        placeId: j['placeId'] as String?,
        relations: ((j['rel'] as List?) ?? const [])
            .map(NpcRelation.maybeFromJson)
            .whereType<NpcRelation>()
            .toList(),
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

/// One bestiary entry from a bundled ruleset foe collection.
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

/// A named group of [FoeEntry]s belonging to one ruleset, as loaded from a
/// generated `foes_*.json` asset.
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
