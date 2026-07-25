/// The OSR/indie sheets: Nimble, Draw Steel, Argosa, Cairn, Knave,
/// Embark, OSE, DCC, Kal-Arath, Shadowdark.
///
/// Part of the `models` library — see models.dart. Split for
/// navigability only; parts share one scope, so the private helpers
/// (`_intOr`, `_strOr`, `_strSet`) and every cross-reference still work.
part of '../models.dart';

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
class NimbleSheet implements HasHpPool {
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

  @override
  (int, int) get hpPool => (currentHp, maxHp);

  @override
  NimbleSheet withHp(int delta) =>
      copyWith(currentHp: (currentHp + delta).clamp(0, maxHp));
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

/// Draw Steel hero sheet. Facts-only: class/characteristic NAMES are authored
/// constants, every value is player-editable. Power rolls resolve via
/// `drawSteelPowerRoll` in sheet_rolls.dart.
class DrawSteelSheet implements HasHpPool {
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

  @override
  (int, int) get hpPool => (currentStamina, maxStamina);

  @override
  DrawSteelSheet withHp(int delta) =>
      copyWith(currentStamina: (currentStamina + delta).clamp(0, maxStamina));
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

/// Tales of Argosa sheet. Roll-under resolution (`argosaRollUnder`), a Luck
/// pool that resets to `10 + ceil(level/2)`, and a computed Stagger state.
class ArgosaSheet implements HasHpPool {
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

  @override
  (int, int) get hpPool => (currentHp, maxHp);

  @override
  ArgosaSheet withHp(int delta) =>
      copyWith(currentHp: (currentHp + delta).clamp(0, maxHp));
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

/// Cairn sheet. Three stats, and HP that is Hit PROTECTION (avoidance, not
/// meat) — at 0 the excess reduces STR, which the player applies by hand.
class CairnSheet implements HasHpPool {
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

  @override
  (int, int) get hpPool => (currentHp, maxHp);

  @override
  CairnSheet withHp(int delta) =>
      copyWith(currentHp: (currentHp + delta).clamp(0, maxHp));
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

/// Knave 2e sheet. The six scores ARE modifiers (0-10), inventory slots are
/// the computed `10 + CON`, and career is flavour with no mechanical effect.
class KnaveSheet implements HasHpPool {
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

  @override
  (int, int) get hpPool => (currentHp, maxHp);

  @override
  KnaveSheet withHp(int delta) =>
      copyWith(currentHp: (currentHp + delta).clamp(0, maxHp));
}

// ── Embark 2E ────────────────────────────────────────────────────────────────

const kEmbarkStats = <String>['str', 'dex', 'wil', 'int'];

const kEmbarkStatLabels = <String, String>{
  'str': 'STR',
  'dex': 'DEX',
  'wil': 'WIL',
  'int': 'INT',
};

const kEmbarkClasses = <String>[
  'Warrior',
  'Scout',
  'Mage',
  'Invoker',
  'Bard',
  'Barbarian',
];

/// The class's resource-pool name for the single sheet RESOURCE box (the
/// official sheet unifies Grit / Spell Dice / Flair into one). Facts-only,
/// non-copyrightable. Scout (Talents) and Barbarian (Feats) have no numeric
/// pool, so a generic label. Pure.
String embarkResourceLabel(String className) {
  switch (className) {
    case 'Warrior':
      return 'Grit';
    case 'Mage':
    case 'Invoker':
      return 'Spell Dice';
    case 'Bard':
      return 'Flair';
    default:
      return 'Resource';
  }
}

/// Facts-only Embark 2E sheet. Attributes are the raw number added to a d12
/// (range -1..4), NOT a score->modifier curve. Injuries are the 3-step death
/// track (third = death; each is a -1 to Checks). Everything else is left
/// freeform (Embark has no fixed skill/language lists).
class EmbarkSheet implements HasHpPool {
  const EmbarkSheet({
    this.className = 'Warrior',
    this.stats = const {
      'str': 0,
      'dex': 0,
      'wil': 0,
      'int': 0,
    },
    this.level = 1,
    this.maxHp = 6,
    this.currentHp = 6,
    this.injuries = 0,
    this.av = 0,
    this.resource = 0,
    this.resourceMax = 0,
    this.sp = '',
    this.skills = '',
    this.languages = '',
    this.notes = '',
  });

  final String className;
  final Map<String, int> stats;
  final int level;
  final int maxHp;
  final int currentHp;
  final int injuries;
  final int av;
  final int resource;
  final int resourceMax;
  final String sp;
  final String skills;
  final String languages;
  final String notes;

  EmbarkSheet copyWith({
    String? className,
    Map<String, int>? stats,
    int? level,
    int? maxHp,
    int? currentHp,
    int? injuries,
    int? av,
    int? resource,
    int? resourceMax,
    String? sp,
    String? skills,
    String? languages,
    String? notes,
  }) {
    final mh = (maxHp ?? this.maxHp).clamp(0, kFieldClampMax);
    final st = stats ?? this.stats;
    final rm = (resourceMax ?? this.resourceMax).clamp(0, 99);
    return EmbarkSheet(
      className: className ?? this.className,
      stats: {
        for (final k in kEmbarkStats)
          k: ((st[k] ?? 0) as num).round().clamp(-1, 4)
      },
      level: (level ?? this.level).clamp(1, 6),
      maxHp: mh,
      currentHp: (currentHp ?? this.currentHp).clamp(0, mh),
      injuries: (injuries ?? this.injuries).clamp(0, 3),
      av: (av ?? this.av).clamp(0, 4),
      resource: (resource ?? this.resource).clamp(0, rm),
      resourceMax: rm,
      sp: sp ?? this.sp,
      skills: skills ?? this.skills,
      languages: languages ?? this.languages,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'className': className,
        'stats': stats,
        'level': level,
        'maxHp': maxHp,
        'currentHp': currentHp,
        'injuries': injuries,
        'av': av,
        'resource': resource,
        'resourceMax': resourceMax,
        'sp': sp,
        'skills': skills,
        'languages': languages,
        'notes': notes,
      };

  static EmbarkSheet? maybeFromJson(dynamic j) {
    if (j is! Map<String, dynamic>) return null;
    final st = (j['stats'] as Map?) ?? {};
    final rm = ((j['resourceMax'] as num?)?.round() ?? 0).clamp(0, 99);
    return EmbarkSheet(
      className: j['className'] as String? ?? 'Warrior',
      stats: {
        for (final k in kEmbarkStats)
          k: ((st[k] ?? 0) as num).round().clamp(-1, 4),
      },
      level: ((j['level'] as num?)?.round() ?? 1).clamp(1, 6),
      maxHp: (j['maxHp'] as num?)?.round() ?? 6,
      currentHp: (j['currentHp'] as num?)?.round() ?? 6,
      injuries: ((j['injuries'] as num?)?.round() ?? 0).clamp(0, 3),
      av: ((j['av'] as num?)?.round() ?? 0).clamp(0, 4),
      resource: ((j['resource'] as num?)?.round() ?? 0).clamp(0, rm),
      resourceMax: rm,
      sp: j['sp'] as String? ?? '',
      skills: j['skills'] as String? ?? '',
      languages: j['languages'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
    );
  }

  @override
  (int, int) get hpPool => (currentHp, maxHp);

  @override
  EmbarkSheet withHp(int delta) =>
      copyWith(currentHp: (currentHp + delta).clamp(0, maxHp));
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
class DccSheet implements HasHpPool {
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

  @override
  (int, int) get hpPool => (currentHp, maxHp);

  @override
  DccSheet withHp(int delta) =>
      copyWith(currentHp: (currentHp + delta).clamp(0, maxHp));
}

/// OSE / B/X sheet. Descending AC, THAC0, and five player-managed save
/// targets — the targets live on the sheet rather than being derived, so a
/// house-ruled table still works.
class OseSheet implements HasHpPool {
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

  @override
  (int, int) get hpPool => (currentHp, maxHp);

  @override
  OseSheet withHp(int delta) =>
      copyWith(currentHp: (currentHp + delta).clamp(0, maxHp));
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
class KalArathSheet implements HasHpPool {
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

  @override
  (int, int) get hpPool => (currentHp, maxHp);

  @override
  KalArathSheet withHp(int delta) =>
      copyWith(currentHp: (currentHp + delta).clamp(0, maxHp));
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
class ShadowdarkSheet implements HasHpPool {
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

  @override
  (int, int) get hpPool => (currentHp, maxHp);

  @override
  ShadowdarkSheet withHp(int delta) =>
      copyWith(currentHp: (currentHp + delta).clamp(0, maxHp));
}
