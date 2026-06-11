import 'dice.dart';
import 'models.dart';
import 'oracle_data.dart';

/// Verified Fate Check result map (matches FATE_MAP in build_oracle.py, which is
/// tested against the PDF's documented table and probabilities).
/// Key: "primary,secondary" or "0,0,left" / "0,0,right" for the double-blank.
/// Value: {normal, likely, unlikely}.
const Map<String, Map<String, String>> _fateMap = {
  '1,1': {'normal': 'Yes And', 'likely': 'Yes And', 'unlikely': 'Yes And'},
  '1,0': {'normal': 'Yes', 'likely': 'Yes', 'unlikely': 'Yes'},
  '1,-1': {'normal': 'Yes But', 'likely': 'Yes But', 'unlikely': 'No But'},
  '0,1': {'normal': 'Favorable', 'likely': 'Yes', 'unlikely': 'Yes'},
  '0,0,left': {
    'normal': 'Yes But + Random Event',
    'likely': 'Yes + Random Event',
    'unlikely': 'No + Random Event',
  },
  '0,0,right': {
    'normal': 'Invalid Assumption',
    'likely': 'Yes',
    'unlikely': 'No',
  },
  '0,-1': {'normal': 'Unfavorable', 'likely': 'No', 'unlikely': 'No'},
  '-1,1': {'normal': 'No But', 'likely': 'Yes But', 'unlikely': 'No But'},
  '-1,0': {'normal': 'No', 'likely': 'No', 'unlikely': 'No'},
  '-1,-1': {'normal': 'No And', 'likely': 'No And', 'unlikely': 'No And'},
};

/// The oracle engine. Wraps [OracleData] + [Dice] and exposes every roll the
/// app offers. Composite generators combine multiple table rolls.
class Oracle {
  Oracle(this.data, [Dice? dice]) : dice = dice ?? Dice();

  final OracleData data;
  final Dice dice;

  // -- Fate Check --------------------------------------------------------
  FateResult fateCheck(Likelihood likelihood) {
    final p = dice.fate();
    final s = dice.fate();
    final intensityRoll = dice.dN(6);
    String? side;
    String key;
    if (p == 0 && s == 0) {
      side = dice.coin() ? 'left' : 'right';
      key = '0,0,$side';
    } else {
      key = '$p,$s';
    }
    return FateResult(
      primary: p,
      secondary: s,
      side: side,
      intensityRoll: intensityRoll,
      intensity: data.intensity[intensityRoll - 1],
      likelihood: likelihood,
      result: _fateMap[key]![likelihood.key]!,
    );
  }

  // -- Generic d10 table roll -------------------------------------------
  Roll rollTable(String key, String label, {int skew = 0}) {
    final idx = dice.d10Index(skew: skew);
    return Roll(
      label: label,
      value: data.table(key)[idx - 1],
      detail: 'd10 ${d10Label(idx)}',
    );
  }

  String _pick(String key, {int skew = 0}) =>
      data.table(key)[dice.d10Index(skew: skew) - 1];

  // -- Composite generators ---------------------------------------------

  GenResult newQuest() {
    final obj = _pick('quest_objective');
    final desc = _pick('quest_description');
    final focus = _pick('quest_focus');
    final prep = _pick('quest_preposition');
    final loc = _pick('quest_location');
    return GenResult(
      title: 'New Quest',
      summary: '$obj the $desc $focus, $prep the $loc.',
      rolls: [
        Roll(label: 'Objective', value: obj),
        Roll(label: 'Description', value: desc),
        Roll(label: 'Focus', value: focus),
        Roll(label: 'Preposition', value: prep),
        Roll(label: 'Location', value: loc),
      ],
    );
  }

  GenResult newScene() {
    final reIdx = dice.d10Index();
    final dcIdx = dice.d10Index();
    return GenResult(
      title: 'New Scene',
      rolls: [
        Roll(label: 'Random Event', value: data.table('random_event')[reIdx - 1]),
        Roll(label: 'Physical Challenge', value: _pick('challenge_physical')),
        Roll(label: 'Mental Challenge', value: _pick('challenge_mental')),
        Roll(label: 'DC', value: data.table('dc')[dcIdx - 1]),
      ],
    );
  }

  GenResult randomEvent() {
    return GenResult(title: 'Random Event', rolls: [
      Roll(label: 'Event', value: _pick('random_event')),
      Roll(label: 'Focus', value: _pick('quest_focus')),
    ]);
  }

  GenResult challenge() {
    final dcIdx = dice.d10Index();
    return GenResult(title: 'Challenge', rolls: [
      Roll(label: 'Physical', value: _pick('challenge_physical')),
      Roll(label: 'Mental', value: _pick('challenge_mental')),
      Roll(label: 'DC', value: data.table('dc')[dcIdx - 1]),
    ]);
  }

  GenResult payThePrice({bool critical = false}) {
    final key = critical ? 'major_plot_twist' : 'pay_the_price';
    return GenResult(
      title: critical ? 'Major Plot Twist' : 'Pay the Price',
      rolls: [Roll(label: 'Result', value: _pick(key))],
    );
  }

  GenResult npc() => GenResult(title: 'NPC', rolls: [
        Roll(label: 'Personality', value: _pick('npc_personality')),
        Roll(label: 'Need', value: _pick('npc_need')),
        Roll(label: 'Motive', value: _pick('npc_motive')),
      ]);

  GenResult npcBehavior({int skew = 0}) => GenResult(
        title: 'NPC Behavior${skew > 0 ? ' (Active)' : skew < 0 ? ' (Passive)' : ''}',
        rolls: [Roll(label: 'Behavior', value: _pick('npc_behavior', skew: skew))],
      );

  GenResult npcCombat() => GenResult(title: 'NPC Combat Action', rolls: [
        Roll(label: 'Action', value: _pick('npc_combat')),
      ]);

  GenResult settlement() => GenResult(title: 'Settlement', rolls: [
        Roll(label: 'Name', value: _pick('settlement_name')),
        Roll(label: 'Establishment', value: _pick('settlement_establishment')),
        Roll(label: 'Artisan', value: _pick('settlement_artisan')),
        Roll(label: 'News', value: _pick('settlement_news')),
      ]);

  GenResult wildernessStep() => GenResult(title: 'Wilderness Step', rolls: [
        Roll(label: 'Environment', value: _pick('wilderness_environment')),
        Roll(label: 'Encounter', value: _pick('wilderness_encounter')),
        Roll(label: 'Weather', value: _pick('wilderness_weather')),
      ]);

  GenResult naturalHazard() => GenResult(title: 'Natural Hazard', rolls: [
        Roll(label: 'Hazard', value: _pick('natural_hazard')),
      ]);

  GenResult dungeonName() => GenResult(
        title: 'Dungeon Name',
        summary:
            '${_pick('dungeon_description')} ${_pick('dungeon_name')} of ${_pick('dungeon_subject')}',
        rolls: const [],
      );

  GenResult dungeonRoom() {
    final enc = _pick('dungeon_encounter');
    final rolls = <Roll>[
      Roll(label: 'Next Area', value: _pick('dungeon_next_area')),
      Roll(label: 'Passage', value: _pick('dungeon_passage')),
      Roll(label: 'Condition', value: _pick('dungeon_condition')),
      Roll(label: 'Encounter', value: enc),
    ];
    // Expand the encounter with its sub-roll where applicable.
    switch (enc) {
      case 'Monster':
        rolls.add(Roll(
            label: 'Monster',
            value:
                '${_pick('monster_description')} / ${_pick('monster_ability')}'));
        break;
      case 'Trap':
        rolls.add(Roll(
            label: 'Trap',
            value: '${_pick('trap_action')} / ${_pick('trap_subject')}'));
        break;
      case 'Feature':
        rolls.add(Roll(label: 'Feature', value: _pick('dungeon_feature')));
        break;
      case 'Natural Hazard':
        rolls.add(Roll(label: 'Hazard', value: _pick('natural_hazard')));
        break;
      case 'Treasure':
        rolls.add(Roll(label: 'Treasure', value: treasure().summary ?? ''));
        break;
    }
    return GenResult(title: 'Dungeon Room', rolls: rolls);
  }

  GenResult treasure() {
    final cat = data.treasureCategories[dice.dN(6) - 1];
    final sub = data.treasureSub(cat);
    final parts = <String>[];
    final rolls = <Roll>[Roll(label: 'Type', value: cat)];
    sub.forEach((colName, values) {
      final v = (values as List).cast<String>()[dice.dN(6) - 1];
      parts.add(v);
      rolls.add(Roll(label: colName, value: v));
    });
    return GenResult(
      title: 'Treasure',
      summary: '${parts.join(' ')} ($cat)',
      rolls: rolls,
    );
  }

  GenResult generateName() {
    final start = data.nameStart[dice.dN(20) - 1];
    final mid = data.nameMid[dice.dN(20) - 1];
    final end = data.nameEnd[dice.dN(20) - 1];
    final name = (start + mid + end);
    final cased = name.isEmpty
        ? name
        : name[0].toUpperCase() + name.substring(1);
    return GenResult(
      title: 'Name',
      summary: cased,
      rolls: [
        Roll(label: 'Syllables', value: '$start · $mid · $end'),
      ],
    );
  }

  GenResult discoverMeaning() => GenResult(
        title: 'Discover Meaning',
        summary:
            '${data.discoverVerb[dice.dN(20) - 1]} ${data.discoverSubject[dice.dN(20) - 1]}',
        rolls: const [],
      );

  GenResult immersion() {
    // Sense by d10 band: 1-3 See, 4-6 Hear, 7-8 Smell, 9-0 Feel.
    final band = dice.d10Index();
    final (sense, key) = switch (band) {
      <= 3 => ('See', 'immersion_see'),
      <= 6 => ('Hear', 'immersion_hear'),
      <= 8 => ('Smell', 'immersion_smell'),
      _ => ('Feel', 'immersion_feel'),
    };
    return GenResult(title: 'Immersion', rolls: [
      Roll(label: sense, value: _pick(key)),
      Roll(label: 'Where', value: _pick('immersion_where')),
      Roll(label: 'Emotion', value: _pick('emotion_negative')),
      Roll(label: 'Positive', value: _pick('emotion_positive')),
      Roll(label: 'Because', value: _pick('because')),
    ]);
  }

  GenResult plotPoint() {
    // Category by d10 band: 1-2 Action, 3-4 Tension, 5-6 Mystery, 7-8 Social, 9-0 Personal.
    final band = dice.d10Index();
    final (cat, key) = switch (band) {
      <= 2 => ('Action', 'interrupt_action'),
      <= 4 => ('Tension', 'interrupt_tension'),
      <= 6 => ('Mystery', 'interrupt_mystery'),
      <= 8 => ('Social', 'interrupt_social'),
      _ => ('Personal', 'interrupt_personal'),
    };
    return GenResult(title: 'Plot Point / Interrupt', rolls: [
      Roll(label: cat, value: _pick(key)),
    ]);
  }

  GenResult randomIdea() => GenResult(title: 'Random Idea', rolls: [
        Roll(label: 'Modifier', value: _pick('idea_modifier')),
        Roll(label: 'Idea', value: _pick('idea_idea')),
      ]);

  GenResult detail({int skew = 0}) => GenResult(title: 'Detail', rolls: [
        Roll(label: 'Detail', value: _pick('detail', skew: skew)),
      ]);

  GenResult property() {
    final p = _pick('property');
    final intensity = data.intensity[dice.dN(6) - 1];
    return GenResult(title: 'Property', rolls: [
      Roll(label: 'Property', value: '$intensity $p'),
    ]);
  }

  // -- Extended NPC d100 tables -----------------------------------------
  String _d100(String extKey) {
    final r = dice.d100();
    for (final row in data.ext(extKey)) {
      if (r <= (row[0] as num)) return row[1] as String;
    }
    return data.ext(extKey).last[1] as String;
  }

  GenResult extendedInfo() => GenResult(title: 'NPC Plot Knowledge', rolls: [
        Roll(label: 'Type', value: _d100('info_type')),
        Roll(label: 'Topic', value: _d100('info_topic')),
      ]);

  GenResult companionResponse() => GenResult(
        title: 'Companion Response',
        rolls: [Roll(label: 'Response', value: _d100('companion'))],
      );

  GenResult dialogTopic() => GenResult(
        title: 'NPC Dialog Topic',
        rolls: [Roll(label: 'Topic', value: _d100('dialog_topic'))],
      );
}
