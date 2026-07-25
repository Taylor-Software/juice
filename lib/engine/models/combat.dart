/// Stat blocks, creatures, combatants and encounter state.
///
/// Part of the `models` library — see models.dart. Split for
/// navigability only; parts share one scope, so the private helpers
/// (`_intOr`, `_strOr`, `_strSet`) and every cross-reference still work.
part of '../models.dart';

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
