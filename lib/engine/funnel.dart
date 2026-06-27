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
};
