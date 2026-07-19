import 'system_primer.dart' show resolveSystem;

/// One titled block of facts-only reference lines.
class QuickRefSection {
  const QuickRefSection(this.title, this.lines);
  final String title;
  final List<String> lines;

  Map<String, dynamic> toJson() => {'title': title, 'lines': lines};

  static QuickRefSection? maybeFromJson(Object? raw) {
    if (raw is! Map) return null;
    final t = raw['title'], l = raw['lines'];
    if (t is! String || l is! List) return null;
    return QuickRefSection(t, l.whereType<String>().toList());
  }
}

/// A per-system mechanics quick reference (facts-only: procedures + condition/
/// save names + one-line generic effects; no rulebook prose, no attribution).
class QuickRefCard {
  const QuickRefCard({
    required this.system,
    required this.title,
    required this.sections,
  });
  final String system;
  final String title;
  final List<QuickRefSection> sections;
}

const _dnd =
    QuickRefCard(system: 'dnd', title: 'D&D 5e — Quick Reference', sections: [
  QuickRefSection('Resolution', [
    'd20 + modifier vs a Difficulty Class (DC).',
    'Advantage / disadvantage: roll 2d20, take the higher / lower.',
    'On attacks, a natural 20 always hits (and crits); a natural 1 always misses.',
  ]),
  QuickRefSection('Combat round', [
    'Roll initiative (d20 + DEX); act highest to lowest.',
    'Your turn: move up to your speed + one action + one bonus action (if you have one).',
    'One reaction per round (e.g. opportunity attack when a foe leaves your reach).',
  ]),
  QuickRefSection('Common actions', [
    'Attack, Cast a Spell, Dash, Disengage, Dodge, Help, Hide, Ready, Search, Use an Object.',
  ]),
  QuickRefSection('Attacks & damage', [
    'Attack roll: d20 + ability mod + proficiency vs target AC.',
    'On a hit, roll the weapon/spell damage + ability mod.',
  ]),
  QuickRefSection('Damage & death', [
    '0 HP = unconscious; make a death save each turn: d20, 10+ succeeds, under fails.',
    '3 successes = stable; 3 failures = dead. Taking damage at 0 HP = 1 failure (a crit = 2).',
  ]),
  QuickRefSection('Conditions', [
    'Blinded, Charmed, Deafened, Frightened, Grappled, Incapacitated, Invisible,',
    'Paralyzed, Petrified, Poisoned, Prone, Restrained, Stunned, Unconscious, Exhaustion.',
  ]),
  QuickRefSection('Rest', [
    'Short rest (~1 hr): spend Hit Dice to regain HP.',
    'Long rest (~8 hr): regain all HP and half your Hit Dice.',
  ]),
]);

const _ironsworn = QuickRefCard(
    system: 'ironsworn',
    title: 'Ironsworn — Quick Reference',
    sections: [
      QuickRefSection('Resolution', [
        'Roll your action die (d6) + stat + adds vs two challenge dice (d10 each).',
        'Beat both = strong hit; beat one = weak hit; beat neither = miss.',
      ]),
      QuickRefSection('Momentum', [
        'Track momentum (-6..+10). Burn it to replace BOTH challenge dice with its value.',
        'Negative momentum cancels a matching action-die result.',
      ]),
      QuickRefSection('Combat (moves)', [
        'There is no initiative count — you "have the initiative" or you don\'t.',
        'Enter the Fray, then Strike (you have it) / Clash (you don\'t) / Secure an Advantage.',
        'Strong hits keep or seize the initiative; misses hand it to the enemy.',
      ]),
      QuickRefSection('Harm & death', [
        'Suffer harm → lose health. At 0 health, harm hits momentum or forces Face Death.',
      ]),
      QuickRefSection('Conditions (debilities)', [
        'Banes: wounded, shaken, unprepared, encumbered, maimed, corrupted.',
        'Burdens: cursed, tormented. Each marked debility lowers your max momentum.',
      ]),
    ]);

const _cairn =
    QuickRefCard(system: 'cairn', title: 'Cairn — Quick Reference', sections: [
  QuickRefSection('Resolution', [
    'Roll d20 UNDER the relevant ability (STR / DEX / WIL) to save.',
    '1 always succeeds, 20 always fails. Only roll when there is real risk and uncertainty.',
  ]),
  QuickRefSection('Combat round', [
    'Attacker rolls the weapon die − target Armor; deal the remainder to HP.',
    'Several attackers on one foe: roll all damage dice, keep the single highest.',
  ]),
  QuickRefSection('Impaired & enhanced', [
    'Impaired (cover, bound) = roll d4 for damage.',
    'Enhanced (helpless foe, daring move) = roll d12. Blast attacks hit everything in area.',
  ]),
  QuickRefSection('Damage & death', [
    'HP is luck/avoidance. At 0 HP, excess damage reduces STR.',
    'Then make a STR save or take Critical Damage: out of the fight, dying without aid.',
  ]),
  QuickRefSection('Deprivation & rest', [
    'A short rest with water restores HP. Deprived (no food/light/rest) = cannot recover.',
    'A day spent deprived adds Fatigue, which fills an inventory slot until you recover safely.',
  ]),
]);

const _knave = QuickRefCard(
    system: 'knave',
    title: 'Knave 2e — Quick Reference',
    sections: [
      QuickRefSection('Resolution', [
        'Roll d20 + ability bonus (0–10), meet or beat the target.',
        'Saves: d20 + relevant bonus vs DC 11 (or 11 + an opposing factor).',
      ]),
      QuickRefSection('Combat round', [
        'Roll initiative. Attack: d20 + bonus vs the target\'s Armor Class.',
        'On a hit, roll the weapon\'s damage die.',
      ]),
      QuickRefSection('Damage & death', [
        'Lose HP when hit. At 0 HP you start taking Wounds.',
        'Accumulating too many Wounds means death (track on the sheet).',
      ]),
      QuickRefSection('Inventory', [
        'Carry slots = 10 + CON. Exceeding them leaves you encumbered (slowed).',
      ]),
      QuickRefSection('Rest', [
        'Rest to recover HP; longer downtime and care to mend Wounds.',
      ]),
    ]);

const _embark = QuickRefCard(
    system: 'embark',
    title: 'Embark 2E — Quick Reference',
    sections: [
      QuickRefSection('Resolution', [
        'Roll d12 + the relevant attribute (STR / DEX / WIL / INT); total 8+ succeeds.',
        'Advantage / disadvantage: roll an extra die, take the highest / lowest.',
        'Each Injury you carry is a -1 penalty to all Checks.',
      ]),
      QuickRefSection('Combat round', [
        'Roll initiative (d12): 7+ the players act first, else the enemies do.',
        'Each turn: a Move action + one other action (Strike, Cast, Stunt, Use, …).',
        'Attacks always hit: roll the weapon damage die minus the target\'s Armor Value (min 1).',
      ]),
      QuickRefSection('Damage & injuries', [
        'Damage reduces HP (min 0). Armor Value (0-4) subtracts from each hit.',
        'At 0 HP, or taking damage while at 0, you gain an Injury.',
        'Third Injury = death. NPCs take no Injuries and die at 0 HP.',
      ]),
      QuickRefSection('Resting', [
        'Breather: 1 Turn + 1 ration → restore d6 HP.',
        'Full Rest: a full day in a safe haven → restore all HP and remove all Injuries.',
      ]),
      QuickRefSection('Light & time', [
        'Torches burn 6 Turns (~1 hr); lanterns 18 Turns. You cannot see in the dark.',
        'Turn = 10 min (dungeon); Watch = 6 hrs (overland travel, 1 hex per Watch).',
      ]),
    ]);

const _ose = QuickRefCard(
    system: 'ose',
    title: 'OSE / B-X — Quick Reference',
    sections: [
      QuickRefSection('Resolution', [
        'Mostly attack rolls and saving throws on a d20 vs a fixed target.',
        'Ability checks are rare and by ruling.',
      ]),
      QuickRefSection('Combat round', [
        'Declare → initiative (d6 per side) → movement → missiles → spells → melee.',
        'Attack: d20 + modifiers vs the target\'s AC, using THAC0 or the to-hit table.',
      ]),
      QuickRefSection('Saving throws', [
        'Five saves: Death/Poison, Wands, Paralysis/Petrify, Breath, Spells/Rods/Staves.',
        'Roll d20; meet or beat the listed target number.',
      ]),
      QuickRefSection('AC & death', [
        'Descending AC — lower is better. On a hit, roll weapon damage.',
        '0 HP = dead (or unconscious by table ruling).',
      ]),
      QuickRefSection('Rest', [
        'Recover slowly with rest (e.g. ~1 HP per day); full recovery needs extended downtime.',
      ]),
    ]);

const _argosa = QuickRefCard(
    system: 'argosa',
    title: 'Tales of Argosa — Quick Reference',
    sections: [
      QuickRefSection('Resolution', [
        'Roll d20 UNDER your stat to succeed (roll-under).',
        'Roll ≤ half the stat = Great Success. 1 is best, 20 is worst.',
      ]),
      QuickRefSection('Combat round', [
        'Determine order, act, then resolve. Attack vs defense; on a hit, roll weapon damage − armor.',
      ]),
      QuickRefSection('Luck', [
        'Spend Luck to reroll or improve a result.',
        'Reset Luck to 10 + ⌈level / 2⌉ on a rest.',
      ]),
      QuickRefSection('Damage & staggered', [
        'Lose HP when hit. Staggered when current HP ≤ half max (and above 0): under pressure.',
        '0 HP = down / dying.',
      ]),
      QuickRefSection('Rest', [
        'Rest restores HP and Luck; serious wounds need longer recovery.',
      ]),
    ]);

const _kalArath = QuickRefCard(
    system: 'kal-arath',
    title: 'Kal-Arath — Quick Reference',
    sections: [
      QuickRefSection('Resolution', [
        'Roll 2d6 + stat, total ≥ 8 to succeed.',
        'Double 6s = Critical Success; double 1s = Critical Failure.',
      ]),
      QuickRefSection('Combat round', [
        'Act in the fiction; resolve a strike with 2d6 + stat ≥ 8 (or vs the foe).',
        'On success, deal damage minus the target\'s damage reduction.',
      ]),
      QuickRefSection('Fate & pacts', [
        'Spend a Fate Point (about one per session) to reroll or turn a failure.',
        'Demonic pacts grant power at the cost of mounting Doom.',
      ]),
      QuickRefSection('Damage & death', [
        'Lose HP when struck (after damage reduction). 0 HP = dying / out of the fight.',
        'Recover slowly or with aid.',
      ]),
    ]);

const _shadowdark = QuickRefCard(
    system: 'shadowdark',
    title: 'Shadowdark — Quick Reference',
    sections: [
      QuickRefSection('Resolution', [
        'd20 + ability modifier vs a Difficulty Class (easy 9, normal 12, hard 15, extreme 18).',
        'Advantage / disadvantage: roll 2d20, take the higher / lower.',
        'A natural 20 is a critical success; a natural 1 is a critical failure.',
      ]),
      QuickRefSection('Combat round', [
        'Roll initiative (d20 + DEX); act highest to lowest.',
        'Your turn: move a near distance + one action.',
        'Attack: d20 + attack bonus vs the target\'s AC; on a hit, roll weapon damage.',
      ]),
      QuickRefSection('Light', [
        'Light sources burn in REAL time — a torch lasts about one hour at the table.',
        'In full darkness you cannot see to act; manage your light or be caught in the dark.',
      ]),
      QuickRefSection('Spellcasting', [
        'Cast: d20 + spellcasting modifier vs DC 10 + the spell\'s tier.',
        'Fail and you lose that spell until your next rest; a natural 1 can carry a worse mishap.',
      ]),
      QuickRefSection('Damage & death', [
        '0 HP = unconscious and dying; allies have a short window to stabilize you or you die.',
        'Monsters reduced to 0 HP are slain.',
      ]),
      QuickRefSection('Rest', [
        'A rest restores HP; a safe night\'s rest recovers more and resets daily abilities.',
      ]),
    ]);

const _nimble = QuickRefCard(
    system: 'nimble',
    title: 'Nimble — Quick Reference',
    sections: [
      QuickRefSection('Resolution', [
        'Roll d20 + the relevant stat modifier (STR / DEX / INT / WIS) vs a target.',
        'Advantage / disadvantage shifts the roll up or down.',
      ]),
      QuickRefSection('Combat round', [
        'Take your turn: move and act. Attacks roll damage dice directly.',
        'Rolling the maximum on a damage die can explode (roll it again and add).',
        'Armor reduces the damage you take.',
      ]),
      QuickRefSection('Saves', [
        'Roll a save with advantage or disadvantage as the situation dictates.',
      ]),
      QuickRefSection('Wounds & death', [
        'At 0 HP you begin taking Wounds (the dying track).',
        'Accumulate too many Wounds and your hero dies.',
      ]),
      QuickRefSection('Rest', [
        'Rest to recover HP; Wounds mend more slowly.',
      ]),
    ]);

const _drawSteel = QuickRefCard(
    system: 'draw-steel',
    title: 'Draw Steel — Quick Reference',
    sections: [
      QuickRefSection('Power roll', [
        'Roll 2d10 + a characteristic and read the tier: tier 1 (≤11), tier 2 (12–16), tier 3 (17+).',
        'Higher tiers give better outcomes. Edges and banes nudge the result up or down a tier.',
      ]),
      QuickRefSection('Characteristics', [
        'Might, Agility, Reason, Intuition, Presence — used as the bonus on power rolls.',
        'There is no AC; defenses come from the characteristics and abilities.',
      ]),
      QuickRefSection('Heroic resource', [
        'Each class builds a heroic resource during a fight (e.g. Focus, Discipline, Ferocity).',
        'Spend it to fuel signature and heroic abilities.',
      ]),
      QuickRefSection('Combat round', [
        'Sides alternate taking hero / enemy turns. On your turn: a move + a main action.',
        'Forced movement, conditions, and positioning matter heavily.',
      ]),
      QuickRefSection('Damage & death', [
        'Lose Stamina when hit; Winded at half Stamina. At 0 Stamina you are dying.',
      ]),
    ]);

const _dcc =
    QuickRefCard(system: 'dcc', title: 'DCC — Quick Reference', sections: [
  QuickRefSection('Resolution', [
    'd20 + modifier vs a DC. The dice chain (d3-d5-d7-d14-d16-d24-d30) scales bonuses/penalties.',
  ]),
  QuickRefSection('Combat round', [
    'Roll initiative (d20 + AGI); act highest to lowest.',
    'Attack: d20 + mods vs AC; on a hit, roll weapon damage.',
    'Warriors & Dwarves add a Deed Die to attack and damage — 3+ lands a Mighty Deed.',
  ]),
  QuickRefSection('Saving throws', [
    'Three saves: Fortitude, Reflex, Will. Roll d20 + the save bonus vs the DC.',
  ]),
  QuickRefSection('Spellcasting', [
    'Spell check: d20 + caster level + ability mod vs the spell\'s DC; the total sets the effect.',
    'Wizards/Elves may spellburn (burn STR/AGI/STA for a bonus); Clerics risk disapproval.',
    'A natural 1 can misfire or corrupt the caster.',
  ]),
  QuickRefSection('Luck', [
    'Spend Luck to add to a roll (burned permanently). Thieves & Halflings recover Luck.',
  ]),
  QuickRefSection('Damage & death', [
    '0 HP = dying; you may recover the body (a Luck roll) rather than die outright.',
  ]),
]);

/// Authored facts-only cards, keyed by canonical system id (see resolveSystem).
/// Ironsworn shares one card across classic/starforged/sundered_isles.
const Map<String, QuickRefCard> kSystemQuickRefs = {
  'dnd': _dnd,
  'shadowdark': _shadowdark,
  'nimble': _nimble,
  'draw-steel': _drawSteel,
  'cairn': _cairn,
  'knave': _knave,
  'embark': _embark,
  'ose': _ose,
  'argosa': _argosa,
  'kal-arath': _kalArath,
  'dcc': _dcc,
  'ironsworn': _ironsworn,
  'starforged': _ironsworn,
  'sundered_isles': _ironsworn,
};

/// The active system's card, or null when the resolved system has none.
QuickRefCard? resolveSystemQuickRef(
        Set<String> systems, Set<String> rulesets) =>
    kSystemQuickRefs[resolveSystem(systems, rulesets)];

/// A user-authored ref card. Renders as a [QuickRefCard].
class UserRefCard {
  const UserRefCard(
      {required this.id, required this.title, required this.sections});
  final String id;
  final String title;
  final List<QuickRefSection> sections;

  QuickRefCard toQuickRefCard() =>
      QuickRefCard(system: 'custom', title: title, sections: sections);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sections': [for (final s in sections) s.toJson()],
      };

  static UserRefCard? maybeFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], title = raw['title'], secs = raw['sections'];
    if (id is! String || title is! String || secs is! List) return null;
    return UserRefCard(
      id: id,
      title: title,
      sections: secs
          .map(QuickRefSection.maybeFromJson)
          .whereType<QuickRefSection>()
          .toList(),
    );
  }
}

/// Parses an editor body into sections (pure). A line starting with '#' begins a
/// new section with that heading; other non-empty lines are bullets of the
/// current section; non-empty lines before the first heading go under a leading
/// 'Notes' section; blank lines are ignored; headings with no bullets are dropped.
List<QuickRefSection> parseRefSections(String text) {
  final out = <QuickRefSection>[];
  var title = 'Notes';
  var lines = <String>[];
  void flush() {
    if (lines.isNotEmpty) out.add(QuickRefSection(title, List.of(lines)));
    lines = [];
  }

  for (final raw in text.split('\n')) {
    final t = raw.trim();
    if (t.isEmpty) continue;
    if (t.startsWith('#')) {
      flush();
      final h = t.replaceFirst(RegExp(r'^#+\s*'), '').trim();
      title = h.isEmpty ? 'Notes' : h;
    } else {
      lines.add(t);
    }
  }
  flush();
  return out;
}
