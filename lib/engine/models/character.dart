/// The roster entity: roles, funnels, and Character itself.
///
/// Part of the `models` library — see models.dart. Split for
/// navigability only; parts share one scope, so the private helpers
/// (`_intOr`, `_strOr`, `_strSet`) and every cross-reference still work.
part of '../models.dart';

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

/// Where a roster entry sits in the party: a player character, a companion
/// travelling with them, or a tracked NPC.
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
(int, int)? characterHpPool(Character c) =>
    c.hpSheet?.hpPool ??
    (c.tracks.isNotEmpty ? (c.tracks.first.current, c.tracks.first.max) : null);

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
    this.embark,
    this.ose,
    this.kalArath,
    this.custom,
    this.dcc,
    this.funnel,
    this.starred = false,
    this.role = CharacterRole.pc,
    this.conditions = const [],
    this.coins = 0,
  });
  final String id;
  final String name;
  final String note;
  final List<CharStat> stats;
  final List<CharTrack> tracks;
  final List<String> tags;

  /// Currency count for the basic sheet. Omitted from JSON when 0.
  final int coins;

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

  /// Bespoke Embark 2E sheet; null unless this is an Embark PC.
  final EmbarkSheet? embark;

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
      'embark' => Character(
          id: id, name: 'New Embark character', embark: const EmbarkSheet()),
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
    EmbarkSheet? embark,
    bool clearEmbark = false,
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
    int? coins,
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
        embark: clearEmbark ? null : (embark ?? this.embark),
        ose: clearOse ? null : (ose ?? this.ose),
        kalArath: clearKalArath ? null : (kalArath ?? this.kalArath),
        custom: clearCustom ? null : (custom ?? this.custom),
        dcc: clearDcc ? null : (dcc ?? this.dcc),
        funnel: clearFunnel ? null : (funnel ?? this.funnel),
        starred: starred ?? this.starred,
        role: role ?? this.role,
        conditions: conditions ?? this.conditions,
        coins: coins ?? this.coins,
      );

  /// Applies an HP [delta] (negative = damage) to whichever HP pool this
  /// character uses: the D&D / Shadowdark sheet's currentHp (clamped to its
  /// maxHp), else the first track (via [CharTrack.adjusted]). Characters with
  /// no HP pool (e.g. Ironsworn / Starforged, which use condition meters) are
  /// returned unchanged. Used by the party-wide effect broadcast.
  /// This character's HP-bearing sheet, if it has one.
  ///
  /// The ONE place that enumerates which sheets carry a pool, in resolution
  /// order. [characterHpPool] and [withHpDelta] both read it, so a new sheet
  /// system is wired into HP by adding it here once — previously the same
  /// eleven-branch ladder was spelled out twice, with the clamp arithmetic
  /// re-derived in each branch.
  HasHpPool? get hpSheet {
    for (final s in <HasHpPool?>[
      dnd,
      shadowdark,
      nimble,
      drawSteel,
      argosa,
      cairn,
      knave,
      embark,
      ose,
      kalArath,
      dcc,
    ]) {
      if (s != null) return s;
    }
    return null;
  }

  Character withHpDelta(int delta) {
    if (delta == 0) return this;
    // Each sheet clamps against its own max in its own withHp; this only has
    // to put the result back in the right typed slot.
    if (dnd != null) return copyWith(dnd: dnd!.withHp(delta));
    if (shadowdark != null) {
      return copyWith(shadowdark: shadowdark!.withHp(delta));
    }
    if (nimble != null) return copyWith(nimble: nimble!.withHp(delta));
    if (drawSteel != null) return copyWith(drawSteel: drawSteel!.withHp(delta));
    if (argosa != null) return copyWith(argosa: argosa!.withHp(delta));
    if (cairn != null) return copyWith(cairn: cairn!.withHp(delta));
    if (knave != null) return copyWith(knave: knave!.withHp(delta));
    if (embark != null) return copyWith(embark: embark!.withHp(delta));
    if (ose != null) return copyWith(ose: ose!.withHp(delta));
    if (kalArath != null) return copyWith(kalArath: kalArath!.withHp(delta));
    if (dcc != null) return copyWith(dcc: dcc!.withHp(delta));
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
        if (embark != null) 'embark': embark!.toJson(),
        if (ose != null) 'ose': ose!.toJson(),
        if (kalArath != null) 'kalArath': kalArath!.toJson(),
        if (custom != null) 'custom': custom!.toJson(),
        if (dcc != null) 'dcc': dcc!.toJson(),
        if (funnel != null) 'funnel': funnel!.toJson(),
        if (starred) 'starred': true,
        if (role != CharacterRole.pc) 'role': role.name,
        if (conditions.isNotEmpty) 'conditions': conditions,
        if (coins != 0) 'coins': coins,
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
        embark: EmbarkSheet.maybeFromJson(j['embark']),
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
        coins: (j['coins'] as int?) ?? 0,
      );
}
