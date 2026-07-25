/// D&D 5e sheet plus its authored class/spell tables.
///
/// Part of the `models` library — see models.dart. Split for
/// navigability only; parts share one scope, so the private helpers
/// (`_intOr`, `_strOr`, `_strSet`) and every cross-reference still work.
part of '../models.dart';

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
class DndSheet implements HasHpPool {
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

  @override
  (int, int) get hpPool => (currentHp, maxHp);

  @override
  DndSheet withHp(int delta) =>
      copyWith(currentHp: (currentHp + delta).clamp(0, maxHp));
}

// --- Nimble (facts-only: authored class/stat names only) --------------------
