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

  /// One stateful wilderness travel step (replaces the stateless
  /// Wilderness Step). Environment drifts by 2dF from the previous hex
  /// (header "2dF Env"); Lost/Found cycle per instructions p73:
  /// encounter 10 while exploring -> Lost (d6 encounters);
  /// encounter 6 (River/Road) while Lost -> reoriented.
  ({GenResult result, CrawlState state}) wildernessTravel(CrawlState s) {
    final env = s.envRow == null
        ? dice.d10Index()
        : (s.envRow! + dice.fate() + dice.fate()).clamp(1, 10).toInt();
    final encIdx = s.lost ? dice.dN(6) : dice.d10Index();
    final encounter = data.table('wilderness_encounter')[encIdx - 1];
    var lost = s.lost;
    String? note;
    if (!lost && encIdx == 10) {
      lost = true;
      note = 'You are now Lost — encounters drop to a d6';
    } else if (lost && encIdx == 6) {
      lost = false;
      note = 'Reoriented — no longer Lost';
    }
    final rolls = <Roll>[
      Roll(
          label: 'Environment',
          value: data.table('wilderness_environment')[env - 1],
          detail: s.envRow == null ? 'd10 ${d10Label(env)}' : '2dF drift'),
      Roll(
          label: 'Encounter',
          value: encounter,
          detail: s.lost ? 'd6 $encIdx (lost)' : 'd10 ${d10Label(encIdx)}'),
      Roll(label: 'Weather', value: _pick('wilderness_weather')),
    ];
    return (
      result: GenResult(title: 'Wilderness Travel', summary: note, rolls: rolls),
      state: s.copyWith(envRow: env, lost: lost),
    );
  }

  GenResult naturalHazard() => GenResult(title: 'Natural Hazard', rolls: [
        Roll(label: 'Hazard', value: _pick('natural_hazard')),
      ]);

  GenResult dungeonName() => GenResult(
        title: 'Dungeon Name',
        summary:
            '${_pick('dungeon_description')} ${_pick('dungeon_name')} of ${_pick('dungeon_subject')}',
        rolls: const [],
      );

  /// Dungeon encounter roll + sub-roll expansion. First entry uses a d10;
  /// lingering >10 minutes in an unsafe area drops to a d6 (instructions
  /// p116), which also caps the Natural Hazard sub-roll at d6.
  List<Roll> _dungeonEncounterRolls({required bool linger}) {
    final encIdx = linger ? dice.dN(6) : dice.d10Index();
    final enc = data.table('dungeon_encounter')[encIdx - 1];
    final rolls = <Roll>[
      Roll(
          label: 'Encounter',
          value: enc,
          detail: linger ? 'd6 $encIdx' : 'd10 ${d10Label(encIdx)}'),
    ];
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
        final hazardIdx = linger ? dice.dN(6) : dice.d10Index();
        rolls.add(Roll(
            label: 'Hazard',
            value: data.table('natural_hazard')[hazardIdx - 1]));
        break;
      case 'Treasure':
        rolls.add(Roll(label: 'Treasure', value: treasure().summary ?? ''));
        break;
    }
    return rolls;
  }

  GenResult dungeonRoom() => GenResult(title: 'Dungeon Room', rolls: [
        Roll(label: 'Next Area', value: _pick('dungeon_next_area')),
        Roll(label: 'Passage', value: _pick('dungeon_passage')),
        Roll(label: 'Condition', value: _pick('dungeon_condition')),
        ..._dungeonEncounterRolls(linger: false),
      ]);

  /// Lingering in the current area: encounter-only roll at d6.
  GenResult dungeonLinger() =>
      GenResult(title: 'Dungeon Linger', rolls: _dungeonEncounterRolls(linger: true));

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

  // -- Monster encounter -------------------------------------------------

  /// Pick the monster-grid row key for [envRow] per the pocketfold formula.
  String _monsterRowKey(int envRow) {
    final formula = data.monsterEnvFormula['$envRow']!; // [modifier, skew]
    final mod = formula[0], skew = formula[1];
    final a = dice.dN(6), b = dice.dN(6);
    final pick = skew > 0
        ? (a > b ? a : b)
        : skew < 0
            ? (a < b ? a : b)
            : a;
    if (skew != 0 && a == b) return '**'; // doubles: bandits, any biome
    final row = (pick + mod).clamp(1, 10);
    if (envRow == 6 && row == 6) return '*'; // Forest special: blights
    return row == 10 ? '0' : '$row';
  }

  /// Wilderness Monster Encounter (pocketfold left extension). Rolls the
  /// current environment too; pass [envRow] (1..10) to pin it instead.
  GenResult monsterEncounter({int? envRow}) {
    final env = envRow ?? dice.d10Index();
    final envName = data.table('wilderness_environment')[env - 1];
    final gridRow = data.monsterGrid[_monsterRowKey(env)]!;
    final d1 = dice.dN(10), d2 = dice.dN(10);
    final band = d1 <= 4 ? 2 : (d1 <= 8 ? 3 : 4);
    final difficulty = const {2: 'Easy', 3: 'Medium', 4: 'Hard'}[band]!;
    final rolls = <Roll>[
      Roll(label: 'Environment', value: envName, detail: 'd10 ${d10Label(env)}'),
      Roll(label: 'Difficulty', value: difficulty, detail: 'd10 ${d10Label(d1)}'),
    ];
    for (final cell in gridRow.take(band)) {
      final hasPrefix = cell.startsWith('+ ') || cell.startsWith('- ');
      final prefix = hasPrefix ? cell[0] : '';
      final name = hasPrefix ? cell.substring(2) : cell;
      final q1 = dice.dN(6), q2 = dice.dN(6);
      final qty = (prefix == '+'
              ? (q1 > q2 ? q1 : q2)
              : prefix == '-'
                  ? (q1 < q2 ? q1 : q2)
                  : q1) -
          1;
      if (qty > 0) {
        rolls.add(Roll(label: 'Monster', value: '$qty× $name'));
      }
    }
    if (d1 == d2) {
      rolls.add(Roll(label: 'Boss', value: gridRow[4]));
    }
    if (!rolls.any((r) => r.label == 'Monster' || r.label == 'Boss')) {
      rolls.add(const Roll(label: 'Monster', value: 'None — signs only'));
    }
    return GenResult(title: 'Monster Encounter', rolls: rolls);
  }

  /// Creature tracks only: environment-tuned monster type, no difficulty.
  GenResult creatureTracks({int? envRow}) {
    final env = envRow ?? dice.d10Index();
    final envName = data.table('wilderness_environment')[env - 1];
    final cell = data.monsterGrid[_monsterRowKey(env)]![0];
    final name = cell.startsWith('+ ') || cell.startsWith('- ')
        ? cell.substring(2)
        : cell;
    return GenResult(title: 'Creature Tracks', rolls: [
      Roll(label: 'Environment', value: envName, detail: 'd10 ${d10Label(env)}'),
      Roll(label: 'Tracks', value: name),
    ]);
  }

  // -- NPC dialog walk ---------------------------------------------------

  /// NPC dialog marker (row, col) on the 5x5 grid; starts and resets at
  /// center "Fact". Persisted via [dialogPos] getter and [restoreDialogPos].
  int _dialogRow = 2, _dialogCol = 2;

  /// Current dialog marker, for persistence.
  ({int row, int col}) get dialogPos => (row: _dialogRow, col: _dialogCol);

  /// Restore a persisted dialog marker (values clamped to the 5x5 grid).
  void restoreDialogPos(int row, int col) {
    _dialogRow = row.clamp(0, 4);
    _dialogCol = col.clamp(0, 4);
  }

  // -- Mythic GME 2e (Word Mill Games, CC-BY-NC) --------------------------

  /// Fate Chart roll: [oddsIndex] 0..8 (Certain..Impossible), [chaos] 1..9.
  GenResult mythicFate(int oddsIndex, int chaos) {
    final band = data.mythicBands[9 - chaos + oddsIndex];
    final excYes = band[0], target = band[1], excNo = band[2];
    final roll = dice.d100();
    final String answer;
    if (roll <= excYes) {
      answer = 'Exceptional Yes';
    } else if (roll <= target) {
      answer = 'Yes';
    } else if (roll < excNo) {
      answer = 'No';
    } else {
      answer = 'Exceptional No';
    }
    final rolls = <Roll>[
      Roll(label: 'Answer', value: answer, detail: 'd100 $roll vs $target'),
      Roll(
          label: 'Odds',
          value: data.mythicOdds[oddsIndex],
          detail: 'chaos $chaos'),
    ];
    if (roll < 100 && roll % 11 == 0 && roll ~/ 11 <= chaos) {
      rolls.add(const Roll(
          label: 'Random Event', value: 'Doubles! Roll Event Focus'));
    }
    return GenResult(title: 'Mythic Fate Chart', rolls: rolls);
  }

  /// Scene Test at the start of an expected scene.
  GenResult mythicSceneTest(int chaos) {
    final roll = dice.dN(10);
    final String outcome;
    if (roll > chaos) {
      outcome = 'Expected Scene';
    } else if (roll.isOdd) {
      outcome = 'Altered Scene';
    } else {
      outcome = 'Interrupted Scene';
    }
    return GenResult(title: 'Mythic Scene Test', rolls: [
      Roll(label: 'Scene', value: outcome, detail: 'd10 $roll vs chaos $chaos'),
    ]);
  }

  /// Event Focus; thread/NPC-flavored results pick from the player's lists.
  GenResult mythicEventFocus({
    List<String> threads = const [],
    List<String> characters = const [],
  }) {
    final roll = dice.d100();
    final entry = data.mythicEventFocus
        .firstWhere((e) => roll <= (e[0] as int));
    final label = entry[1] as String;
    final kind = entry[2] as String?;
    final rolls = <Roll>[
      Roll(label: 'Focus', value: label, detail: 'd100 $roll'),
    ];
    final pool = kind == 'thread'
        ? threads
        : kind == 'character'
            ? characters
            : const <String>[];
    if (kind != null) {
      rolls.add(Roll(
        label: 'Target',
        value: pool.isEmpty
            ? '(no ${kind}s tracked — invent one)'
            : pool[dice.dN(pool.length) - 1],
      ));
    }
    return GenResult(title: 'Mythic Event Focus', rolls: rolls);
  }

  /// One beat of NPC dialog: move the marker, read the fragment.
  /// Doubles end the conversation and reset the marker (instructions p96).
  GenResult npcDialog() {
    final d1 = dice.dN(10), d2 = dice.dN(10);
    if (d1 == d2) {
      _dialogRow = 2;
      _dialogCol = 2;
      return GenResult(
        title: 'NPC Dialog',
        summary: 'Conversation ends',
        rolls: [
          Roll(label: 'Dice', value: '$d1, $d2', detail: 'doubles'),
        ],
      );
    }
    final dir = data.dialogDirection
        .firstWhere((band) => d1 <= (band[0] as int));
    final tone = dir[1] as String;
    _dialogRow = (_dialogRow + (dir[2] as int)) % 5;
    _dialogCol = (_dialogCol + (dir[3] as int)) % 5;
    final subject = data.dialogSubject
        .firstWhere((band) => d2 <= (band[0] as int))[1] as String;
    final fragment = data.dialogGrid[_dialogRow][_dialogCol];
    final tense = _dialogRow <= 1 ? 'past' : 'present';
    return GenResult(title: 'NPC Dialog', rolls: [
      Roll(label: 'Fragment', value: fragment, detail: tense),
      Roll(label: 'Tone', value: tone, detail: 'd10 ${d10Label(d1)}'),
      Roll(label: 'Subject', value: subject, detail: 'd10 ${d10Label(d2)}'),
    ]);
  }
}
