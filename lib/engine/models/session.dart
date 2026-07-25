/// Campaigns, systems, decks and per-campaign settings.
///
/// Part of the `models` library — see models.dart. Split for
/// navigability only; parts share one scope, so the private helpers
/// (`_intOr`, `_strOr`, `_strSet`) and every cross-reference still work.
part of '../models.dart';

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
  'classic-dungeon',
  'dnd',
  'shadowdark',
  'nimble',
  'draw-steel',
  'argosa',
  'cairn',
  'knave',
  'embark',
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
  'embark': SystemCategory.ruleset,
  'ose': SystemCategory.ruleset,
  'kal-arath': SystemCategory.ruleset,
  'custom': SystemCategory.ruleset,
  'dcc': SystemCategory.ruleset,
  'juice': SystemCategory.oracle,
  'mythic': SystemCategory.oracle,
  'cards': SystemCategory.oracle,
  'verdant': SystemCategory.exploration,
  'hexcrawl': SystemCategory.exploration,
  'classic-dungeon': SystemCategory.exploration,
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
  'classic-dungeon': 'Classic Dungeon',
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

/// A campaign/session: an isolated journal, threads, characters, crawl.
/// (The old CampaignMode gm/party split was retired with the solo-only
/// refocus — legacy JSON `mode` keys are ignored on parse.)
class SessionMeta {
  const SessionMeta(
      {required this.id,
      required this.name,
      this.systems,
      this.identityColor,
      this.identityIcon,
      this.genre,
      this.dndEdition});
  final String id;
  final String name;

  /// Enabled optional systems; null means all (legacy campaigns).
  final List<String>? systems;

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
        if (identityColor != null) 'identityColor': identityColor,
        if (identityIcon != null) 'identityIcon': identityIcon,
        if (genre != null) 'genre': genre,
        if (dndEdition != null) 'dndEdition': dndEdition,
      };

  // id is immutable — not overridable via copyWith.
  SessionMeta copyWith({
    String? name,
    List<String>? systems,
    int? identityColor,
    String? identityIcon,
    String? genre,
    String? dndEdition,
  }) =>
      SessionMeta(
        id: id,
        name: name ?? this.name,
        systems: systems ?? this.systems,
        identityColor: identityColor ?? this.identityColor,
        identityIcon: identityIcon ?? this.identityIcon,
        genre: genre ?? this.genre,
        dndEdition: dndEdition ?? this.dndEdition,
      );

  factory SessionMeta.fromJson(Map<String, dynamic> j) => SessionMeta(
        id: j['id'] as String,
        name: j['name'] as String,
        systems: (j['systems'] as List?)?.whereType<String>().toList(),
        identityColor: (j['identityColor'] as num?)?.toInt(),
        identityIcon: j['identityIcon'] as String?,
        genre: j['genre'] as String?,
        dndEdition: j['dndEdition'] as String?,
      );
}

/// The identity-hue palette (ARGB ints) for per-campaign accents — the launcher
/// spine + icon tile. Assigned at create time, varied across campaigns. See
/// UX-refresh #11 and DESIGN.md -> Colors -> The Identity Spine.
///
/// Rewarmed 2026-07-24: the handoff's Indigo (0xFF4A5A8A) and Plum
/// (0xFF8A4A6A) were the only cool values anywhere in the app's chrome, which
/// the Warm-Only Rule bans. Mulberry and Umber replace them — five identities
/// separated by hue AND value, all inside the warm family. Umber is the
/// closest pair with Terracotta; it reads apart by being markedly darker and
/// desaturated. Stored campaigns keep whatever hue they were assigned.
const kIdentityHues = <int>[
  0xFF9A4A22, // Terracotta
  0xFF5B7A52, // Sage
  0xFF7E3B4E, // Mulberry (was Indigo)
  0xFF59422F, // Umber (was Plum)
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
  'embark': 'flight_takeoff',
  'ose': 'auto_stories',
  'kal-arath': 'whatshot',
};

/// Derives a default identity-icon key from a campaign's [systems]: the
/// ruleset's icon if one is enabled, else the oracle fallback. Pure.
String identityIconKeyFor(Set<String> systems) {
  for (final s in systems) {
    final k = _kRulesetIconKey[s];
    if (k != null) return k;
  }
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
/// Per-campaign play settings: the fiction's genre and tone (both ride every
/// AI prompt), the default yes/no oracle, and UI preferences.
class CampaignSettings {
  const CampaignSettings({
    this.genre = '',
    this.tone = '',
    this.defaultOracle = 'juice',
    this.headerCollapsed = false,
    this.emulatorSystem = 'both',
  });
  final String genre;
  final String tone;
  final String defaultOracle;
  final bool headerCollapsed;

  /// Which party-emulator system the player uses: 'both' (default),
  /// 'triple-o', or 'pet'. Filters the Party Emulator screen.
  final String emulatorSystem;

  CampaignSettings copyWith({
    String? genre,
    String? tone,
    String? defaultOracle,
    bool? headerCollapsed,
    String? emulatorSystem,
  }) =>
      CampaignSettings(
        genre: genre ?? this.genre,
        tone: tone ?? this.tone,
        defaultOracle: defaultOracle ?? this.defaultOracle,
        headerCollapsed: headerCollapsed ?? this.headerCollapsed,
        emulatorSystem: emulatorSystem ?? this.emulatorSystem,
      );

  factory CampaignSettings.fromJson(Map<String, dynamic> j) => CampaignSettings(
        genre: j['genre'] as String? ?? '',
        tone: j['tone'] as String? ?? '',
        defaultOracle: j['defaultOracle'] as String? ?? 'juice',
        headerCollapsed: (j['headerCollapsed'] as bool?) ?? false,
        emulatorSystem: j['emulatorSystem'] as String? ?? 'both',
      );

  Map<String, dynamic> toJson() => {
        'genre': genre,
        'tone': tone,
        'defaultOracle': defaultOracle,
        if (headerCollapsed) 'headerCollapsed': true,
        if (emulatorSystem != 'both') 'emulatorSystem': emulatorSystem,
      };
}
