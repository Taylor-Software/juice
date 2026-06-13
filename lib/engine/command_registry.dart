/// Declarative quick-command registry (spec: cycle4 living-journal §1).
///
/// Pure engine layer — consumed by the journal's re-roll action now and the
/// slash palette in phase 2. Deep work stays in the tools; commands cover
/// the high-frequency "ask and keep playing" loop.
library;

import 'dice_notation.dart';
import 'models.dart';
import 'oracle.dart';

/// Argument shape a command expects (drives palette affordances, phase 2).
enum CommandArg { none, odds, notation }

/// What a command produces: a ready-to-journal title/body plus the
/// structured entry payload (always `rerollable: true` — commands are pure).
class CommandResult {
  const CommandResult(
      {required this.title, required this.body, required this.payload});
  final String title;
  final String body;
  final Map<String, dynamic> payload;
}

class CommandDef {
  const CommandDef({
    required this.id,
    required this.label,
    required this.keywords,
    required this.system,
    required this.arg,
    required this.run,
    this.toolId,
  });

  final String id;
  final String label;
  final List<String> keywords;

  /// 'juice' | 'mythic' | 'roll-high' | 'core' (profile scoping, phase 4).
  final String system;
  final CommandArg arg;

  /// Runs the command. May throw [FormatException] for bad args (dice
  /// notation); never throws otherwise.
  final CommandResult Function(Oracle oracle, Map<String, String> args) run;

  /// Tool-registry id for "open in tool" / deep work.
  final String? toolId;
}

/// Mythic fate-chart odds ladder, index-aligned with the verified asset
/// (pinned by test against OracleData.mythicOdds).
const kMythicOdds = [
  'Certain',
  'Nearly Certain',
  'Very Likely',
  'Likely',
  '50/50',
  'Unlikely',
  'Very Unlikely',
  'Nearly Impossible',
  'Impossible',
];

/// Roll High odds ladder, index-aligned with the verified asset
/// (pinned by test against OracleData.rollHighOdds).
const kRollHighOdds = [
  'Almost Certain',
  'Very Likely',
  'Likely',
  'Unknown',
  'Unlikely',
  'Very Unlikely',
  'Almost Impossible',
];

CommandDef? commandById(List<CommandDef> commands, String id) {
  for (final c in commands) {
    if (c.id == id) return c;
  }
  return null;
}

Map<String, dynamic> _payload(
        String command, Map<String, String> args, GenResult g) =>
    {
      ...g.toPayload(),
      'command': command,
      'args': args,
      'rerollable': true,
    };

CommandResult _fromGen(String command, Map<String, String> args, GenResult g) =>
    CommandResult(
        title: g.title, body: g.asText, payload: _payload(command, args, g));

List<CommandDef> buildCommandRegistry() => [
      CommandDef(
        id: 'fate-juice',
        label: 'Fate Check (Juice)',
        keywords: ['fate', 'check', 'yes', 'no', 'juice', 'oracle'],
        system: 'juice',
        arg: CommandArg.odds,
        toolId: 'fate-check',
        run: (o, args) {
          final lk =
              Likelihood.values.asNameMap()[args['odds']] ?? Likelihood.normal;
          final r = o.fateCheck(lk);
          final g = GenResult(
            title: 'Fate Check (${lk.label})',
            summary: r.result,
            rolls: [
              Roll(label: 'Answer', value: r.result, detail: r.shorthand),
              Roll(
                  label: 'Intensity',
                  value: r.intensity,
                  detail: 'd6 ${r.intensityRoll}'),
            ],
          );
          return _fromGen('fate-juice', {'odds': lk.key}, g);
        },
      ),
      CommandDef(
        id: 'fate-mythic',
        label: 'Fate Check (Mythic)',
        keywords: ['fate', 'mythic', 'chart', 'yes', 'no', 'chaos'],
        system: 'mythic',
        arg: CommandArg.odds,
        toolId: 'mythic',
        run: (o, args) {
          var idx = kMythicOdds.indexOf(args['odds'] ?? '50/50');
          if (idx < 0) idx = 4; // 50/50
          final chaos = (int.tryParse(args['chaos'] ?? '') ?? 5).clamp(1, 9);
          final src = o.mythicFate(idx, chaos);
          // Re-label the 'Odds' roll to 'Chaos' so body contains 'Chaos:',
          // which is more scannable and satisfies the render contract.
          final rolls = src.rolls
              .map((r) => r.label == 'Odds'
                  ? Roll(label: 'Chaos', value: r.value, detail: r.detail)
                  : r)
              .toList();
          final g =
              GenResult(title: src.title, summary: src.summary, rolls: rolls);
          return _fromGen(
              'fate-mythic', {'odds': kMythicOdds[idx], 'chaos': '$chaos'}, g);
        },
      ),
      CommandDef(
        id: 'fate-roll-high',
        label: 'Fate Check (Roll High)',
        keywords: ['fate', 'roll', 'high', 'yes', 'no'],
        system: 'roll-high',
        arg: CommandArg.odds,
        toolId: 'roll-high',
        run: (o, args) {
          var idx = kRollHighOdds.indexOf(args['odds'] ?? 'Unknown');
          if (idx < 0) idx = 3; // Unknown
          const die = 'd20';
          final g = o.rollHigh(die, idx);
          return _fromGen(
              'fate-roll-high', {'odds': kRollHighOdds[idx], 'die': die}, g);
        },
      ),
      CommandDef(
        id: 'dice',
        label: 'Roll Dice',
        keywords: ['dice', 'roll', 'd6', 'd20', 'notation'],
        system: 'core',
        arg: CommandArg.notation,
        toolId: 'dice',
        run: (o, args) {
          final notation = (args['notation'] ?? '').trim();
          if (notation.isEmpty) {
            throw const FormatException('Add dice notation, e.g. /dice 3d6+2');
          }
          final r = parseDice(notation).roll(o.dice);
          final g = GenResult(
            title: 'Dice Roll',
            summary: '${r.expression} = ${r.total}',
            rolls: [
              for (final grp in r.groups)
                if (grp.dice.isNotEmpty)
                  Roll(
                      label: grp.label,
                      value: grp.dice
                          .map((d) => d.kept ? d.display : '[${d.display}]')
                          .join(', '),
                      detail: '${grp.subtotal}'),
            ],
          );
          return _fromGen('dice', {'notation': notation}, g);
        },
      ),
      CommandDef(
        id: 'meaning',
        label: 'Discover Meaning',
        keywords: ['meaning', 'discover', 'inspiration', 'prompt'],
        system: 'juice',
        arg: CommandArg.none,
        toolId: 'gen-story',
        run: (o, args) {
          // discoverMeaning() has empty rolls; build rolls explicitly so the
          // render contract (body == summary+rolls) and non-empty roll
          // assertions both hold.
          final verb = o.data.discoverVerb[o.dice.dN(20) - 1];
          final subject = o.data.discoverSubject[o.dice.dN(20) - 1];
          final g = GenResult(
            title: 'Discover Meaning',
            summary: '$verb $subject',
            rolls: [
              Roll(label: 'Verb', value: verb),
              Roll(label: 'Subject', value: subject),
            ],
          );
          return _fromGen('meaning', const {}, g);
        },
      ),
      CommandDef(
        id: 'name',
        label: 'Generate Name',
        keywords: ['name', 'npc', 'generate'],
        system: 'juice',
        arg: CommandArg.none,
        toolId: 'gen-details',
        run: (o, args) => _fromGen('name', const {}, o.generateName()),
      ),
      CommandDef(
        id: 'detail',
        label: 'Random Detail',
        keywords: ['detail', 'random', 'flavor'],
        system: 'juice',
        arg: CommandArg.none,
        toolId: 'gen-details',
        run: (o, args) => _fromGen('detail', const {}, o.detail()),
      ),
    ];
