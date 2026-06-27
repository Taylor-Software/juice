import 'models.dart';

/// Max 0-level peasants a funnel tracks at once.
const int kFunnelMaxPeasants = 6;

/// A graduation dropdown a target system needs (class/ancestry/alignment/…).
class FunnelChoice {
  const FunnelChoice(this.key, this.label, this.options);
  final String key, label;
  final List<String> options;
}

/// Per-system funnel contract: what its peasants look like + how to build one of
/// its heroes from a survivor. Pure; registered in [kFunnelProfiles].
class FunnelProfile {
  const FunnelProfile({
    required this.system,
    required this.statKeys,
    required this.statMin,
    required this.statMax,
    required this.statDefault,
    required this.flavorFields,
    required this.hpMin,
    required this.hpMax,
    required this.graduateChoices,
    required this.graduate,
  });

  final String system;
  final List<({String key, String label})> statKeys;
  final int statMin, statMax, statDefault;
  final List<({String key, String label})> flavorFields;
  final int hpMin, hpMax;
  final List<FunnelChoice> graduateChoices;

  /// Builds a hero Character of [system] from [p], applying graduation [picks]
  /// (keyed by [graduateChoices] key). Maps stats by key into the target sheet
  /// (the sheet's own copyWith clamps/defaults); HP into the sheet's pool.
  final Character Function(String id, FunnelPeasant p, Map<String, String> picks)
      graduate;

  /// A fresh empty peasant seeded from this profile (mid-range stats, hpMin).
  FunnelPeasant seedPeasant() => FunnelPeasant(
        hp: hpMin,
        stats: {for (final s in statKeys) s.key: statDefault},
        flavor: {for (final f in flavorFields) f.key: ''},
      );

  /// The default pick for each choice (its first option), for the graduate dialog.
  Map<String, String> defaultPicks() =>
      {for (final c in graduateChoices) c.key: c.options.first};
}

FunnelProfile? funnelProfileFor(String system) => kFunnelProfiles[system];

/// Helper: hero name from the peasant, falling back to the forSheet default.
String _heroName(FunnelPeasant p, Character base) =>
    p.name.trim().isEmpty ? base.name : p.name.trim();

final Map<String, FunnelProfile> kFunnelProfiles = {
  'dcc': FunnelProfile(
    system: 'dcc',
    statKeys: const [
      (key: 'str', label: 'STR'),
      (key: 'agi', label: 'AGI'),
      (key: 'sta', label: 'STA'),
      (key: 'per', label: 'PER'),
      (key: 'int', label: 'INT'),
      (key: 'lck', label: 'LCK'),
    ],
    statMin: 3,
    statMax: 18,
    statDefault: 10,
    flavorFields: const [
      (key: 'occupation', label: 'Occupation'),
      (key: 'weapon', label: 'Weapon'),
      (key: 'tradeGoods', label: 'Trade goods'),
    ],
    hpMin: 1,
    hpMax: 8,
    graduateChoices: [
      const FunnelChoice('className', 'Class', kDccClasses),
      const FunnelChoice('alignment', 'Alignment', kDccAlignments),
    ],
    graduate: (id, p, picks) {
      final base = Character.forSheet('dcc', id);
      return base.copyWith(
        name: _heroName(p, base),
        dcc: base.dcc!.copyWith(
          mode: 'leveled',
          stats: p.stats,
          lckMax: p.stats['lck'] ?? 10,
          currentHp: p.hp,
          maxHp: p.hp,
          occupation: p.flavor['occupation'] ?? '',
          className: picks['className'] ?? 'Warrior',
          alignment: picks['alignment'] ?? 'Neutral',
        ),
      );
    },
  ),
  'dnd': FunnelProfile(
    system: 'dnd',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'dex', label: 'DEX'),
      (key: 'con', label: 'CON'), (key: 'int', label: 'INT'),
      (key: 'wis', label: 'WIS'), (key: 'cha', label: 'CHA'),
    ],
    statMin: 3, statMax: 18, statDefault: 10,
    flavorFields: const [(key: 'background', label: 'Background')],
    hpMin: 1, hpMax: 10,
    graduateChoices: [const FunnelChoice('className', 'Class', kDndClasses)],
    graduate: (id, p, picks) {
      final base = Character.forSheet('dnd', id);
      return base.copyWith(
        name: _heroName(p, base),
        dnd: base.dnd!.copyWith(
          abilities: p.stats,
          currentHp: p.hp, maxHp: p.hp,
          className: picks['className'] ?? 'Fighter',
        ),
      );
    },
  ),
  'shadowdark': FunnelProfile(
    system: 'shadowdark',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'dex', label: 'DEX'),
      (key: 'con', label: 'CON'), (key: 'int', label: 'INT'),
      (key: 'wis', label: 'WIS'), (key: 'cha', label: 'CHA'),
    ],
    statMin: 3, statMax: 18, statDefault: 10,
    flavorFields: const [(key: 'background', label: 'Background')],
    hpMin: 1, hpMax: 8,
    graduateChoices: [
      const FunnelChoice('className', 'Class', kShadowdarkClasses),
      const FunnelChoice('ancestry', 'Ancestry', kShadowdarkAncestries),
      const FunnelChoice('alignment', 'Alignment', kShadowdarkAlignments),
    ],
    graduate: (id, p, picks) {
      final base = Character.forSheet('shadowdark', id);
      return base.copyWith(
        name: _heroName(p, base),
        shadowdark: base.shadowdark!.copyWith(
          abilities: p.stats,
          currentHp: p.hp, maxHp: p.hp,
          className: picks['className'] ?? 'Fighter',
          ancestry: picks['ancestry'] ?? 'Human',
          alignment: picks['alignment'] ?? 'Neutral',
        ),
      );
    },
  ),
  'argosa': FunnelProfile(
    system: 'argosa',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'dex', label: 'DEX'),
      (key: 'con', label: 'CON'), (key: 'int', label: 'INT'),
      (key: 'per', label: 'PER'), (key: 'wil', label: 'WIL'),
      (key: 'cha', label: 'CHA'),
    ],
    statMin: 3, statMax: 18, statDefault: 10,
    flavorFields: const [(key: 'occupation', label: 'Occupation')],
    hpMin: 1, hpMax: 10,
    graduateChoices: [const FunnelChoice('className', 'Class', kArgosaClasses)],
    graduate: (id, p, picks) {
      final base = Character.forSheet('argosa', id);
      return base.copyWith(
        name: _heroName(p, base),
        argosa: base.argosa!.copyWith(
          stats: p.stats,
          currentHp: p.hp, maxHp: p.hp,
          className: picks['className'] ?? kArgosaClasses.first,
        ),
      );
    },
  ),
  'ose': FunnelProfile(
    system: 'ose',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'int', label: 'INT'),
      (key: 'wis', label: 'WIS'), (key: 'dex', label: 'DEX'),
      (key: 'con', label: 'CON'), (key: 'cha', label: 'CHA'),
    ],
    statMin: 3, statMax: 18, statDefault: 10,
    flavorFields: const [(key: 'occupation', label: 'Occupation')],
    hpMin: 1, hpMax: 8,
    graduateChoices: [
      const FunnelChoice('className', 'Class', kOseClasses),
      const FunnelChoice('alignment', 'Alignment', kOseAlignments),
    ],
    graduate: (id, p, picks) {
      final base = Character.forSheet('ose', id);
      return base.copyWith(
        name: _heroName(p, base),
        ose: base.ose!.copyWith(
          stats: p.stats,
          currentHp: p.hp, maxHp: p.hp,
          className: picks['className'] ?? 'Fighter',
          alignment: picks['alignment'] ?? 'Neutral',
        ),
      );
    },
  ),
  'nimble': FunnelProfile(
    system: 'nimble',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'dex', label: 'DEX'),
      (key: 'int', label: 'INT'), (key: 'wis', label: 'WIS'),
    ],
    statMin: -9, statMax: 9, statDefault: 0,
    flavorFields: const [(key: 'ancestry', label: 'Ancestry')],
    hpMin: 1, hpMax: 20,
    graduateChoices: const [FunnelChoice('className', 'Class', kNimbleClasses)],
    graduate: (id, p, picks) {
      final base = Character.forSheet('nimble', id);
      return base.copyWith(
        name: _heroName(p, base),
        nimble: base.nimble!.copyWith(
          stats: p.stats,
          currentHp: p.hp, maxHp: p.hp,
          className: picks['className'] ?? kNimbleClasses.first,
        ),
      );
    },
  ),
  'draw-steel': FunnelProfile(
    system: 'draw-steel',
    statKeys: const [
      (key: 'might', label: 'Might'), (key: 'agility', label: 'Agility'),
      (key: 'reason', label: 'Reason'), (key: 'intuition', label: 'Intuition'),
      (key: 'presence', label: 'Presence'),
    ],
    statMin: -5, statMax: 5, statDefault: 0,
    flavorFields: const [(key: 'ancestry', label: 'Ancestry')],
    hpMin: 1, hpMax: 24,
    graduateChoices: const [FunnelChoice('className', 'Class', kDrawSteelClasses)],
    graduate: (id, p, picks) {
      final base = Character.forSheet('draw-steel', id);
      return base.copyWith(
        name: _heroName(p, base),
        drawSteel: base.drawSteel!.copyWith(
          characteristics: p.stats,
          currentStamina: p.hp, maxStamina: p.hp,
          className: picks['className'] ?? kDrawSteelClasses.first,
        ),
      );
    },
  ),
  'knave': FunnelProfile(
    system: 'knave',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'dex', label: 'DEX'),
      (key: 'con', label: 'CON'), (key: 'int', label: 'INT'),
      (key: 'wis', label: 'WIS'), (key: 'cha', label: 'CHA'),
    ],
    statMin: 0, statMax: 10, statDefault: 0,
    flavorFields: const [(key: 'career', label: 'Career')],
    hpMin: 1, hpMax: 8,
    graduateChoices: const [],
    graduate: (id, p, picks) {
      final base = Character.forSheet('knave', id);
      return base.copyWith(
        name: _heroName(p, base),
        knave: base.knave!.copyWith(
          stats: p.stats,
          currentHp: p.hp, maxHp: p.hp,
        ),
      );
    },
  ),
  'kal-arath': FunnelProfile(
    system: 'kal-arath',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'tou', label: 'TOU'),
      (key: 'agi', label: 'AGI'), (key: 'int', label: 'INT'),
      (key: 'pre', label: 'PRE'),
    ],
    statMin: -1, statMax: 5, statDefault: 0,
    flavorFields: const [(key: 'doom', label: 'Doom')],
    hpMin: 1, hpMax: 10,
    graduateChoices: const [
      FunnelChoice('archetype', 'Archetype', kKalArathArchetypes),
      FunnelChoice('pact', 'Demonic Pact', kKalArathPacts),
    ],
    graduate: (id, p, picks) {
      final base = Character.forSheet('kal-arath', id);
      return base.copyWith(
        name: _heroName(p, base),
        kalArath: base.kalArath!.copyWith(
          stats: p.stats,
          currentHp: p.hp, maxHp: p.hp,
          archetype: picks['archetype'] ?? kKalArathArchetypes.first,
          pact: picks['pact'] ?? kKalArathPacts.first,
        ),
      );
    },
  ),
  'cairn': FunnelProfile(
    system: 'cairn',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'dex', label: 'DEX'),
      (key: 'wil', label: 'WIL'),
    ],
    statMin: 3, statMax: 18, statDefault: 10,
    flavorFields: const [],
    hpMin: 1, hpMax: 8,
    graduateChoices: const [FunnelChoice('background', 'Background', kCairnBackgrounds)],
    graduate: (id, p, picks) {
      final base = Character.forSheet('cairn', id);
      return base.copyWith(
        name: _heroName(p, base),
        cairn: base.cairn!.copyWith(
          str: p.stats['str'], dex: p.stats['dex'], wil: p.stats['wil'],
          currentHp: p.hp, maxHp: p.hp,
          background: picks['background'] ?? kCairnBackgrounds.first,
        ),
      );
    },
  ),
  'ironsworn': FunnelProfile(
    system: 'ironsworn',
    statKeys: const [
      (key: 'edge', label: 'Edge'), (key: 'heart', label: 'Heart'),
      (key: 'iron', label: 'Iron'), (key: 'shadow', label: 'Shadow'),
      (key: 'wits', label: 'Wits'),
    ],
    statMin: 1, statMax: 3, statDefault: 1,
    flavorFields: const [],
    hpMin: 0, hpMax: 5,
    graduateChoices: const [],
    graduate: (id, p, picks) {
      final base = Character.forSheet('ironsworn', id);
      return base.copyWith(
        name: _heroName(p, base),
        ironsworn: base.ironsworn!.copyWith(
          edge: p.stats['edge'], heart: p.stats['heart'],
          iron: p.stats['iron'], shadow: p.stats['shadow'],
          wits: p.stats['wits'],
        ),
      );
    },
  ),
  'starforged': FunnelProfile(
    system: 'starforged',
    statKeys: const [
      (key: 'edge', label: 'Edge'), (key: 'heart', label: 'Heart'),
      (key: 'iron', label: 'Iron'), (key: 'shadow', label: 'Shadow'),
      (key: 'wits', label: 'Wits'),
    ],
    statMin: 1, statMax: 3, statDefault: 1,
    flavorFields: const [],
    hpMin: 0, hpMax: 5,
    graduateChoices: const [],
    graduate: (id, p, picks) {
      final base = Character.forSheet('starforged', id);
      return base.copyWith(
        name: _heroName(p, base),
        starforged: base.starforged!.copyWith(
          edge: p.stats['edge'], heart: p.stats['heart'],
          iron: p.stats['iron'], shadow: p.stats['shadow'],
          wits: p.stats['wits'],
        ),
      );
    },
  ),
};
