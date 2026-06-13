import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/command_registry.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';

OracleData _loadData() {
  final raw = File('assets/oracle_data.json').readAsStringSync();
  return OracleData(jsonDecode(raw) as Map<String, dynamic>);
}

void main() {
  final data = _loadData();
  Oracle oracleWith(int seed) => Oracle(data, Dice(Random(seed)));
  final commands = buildCommandRegistry();

  test('ids unique, systems valid, toolIds known shape', () {
    final ids = commands.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
    const systems = {'juice', 'mythic', 'roll-high', 'core'};
    for (final c in commands) {
      expect(systems.contains(c.system), isTrue, reason: c.id);
      expect(c.keywords, isNotEmpty, reason: c.id);
    }
    expect(
        ids,
        containsAll([
          'fate-juice',
          'fate-mythic',
          'fate-roll-high',
          'dice',
          'meaning',
          'name',
          'detail'
        ]));
  });

  test('odds label constants match the verified asset', () {
    expect(kMythicOdds, data.mythicOdds);
    expect(kRollHighOdds, data.rollHighOdds);
  });

  test('fate-juice honors odds and emits rerollable payload', () {
    final cmd = commandById(commands, 'fate-juice')!;
    final r = cmd.run(oracleWith(7), {'odds': 'likely'});
    expect(r.title, 'Fate Check (Likely)');
    expect(r.payload['command'], 'fate-juice');
    expect(r.payload['args'], {'odds': 'likely'});
    expect(r.payload['rerollable'], true);
    expect(r.payload['rolls'], isNotEmpty);
    expect(r.body, isNotEmpty);
  });

  test('fate-juice defaults to normal on unknown odds', () {
    final cmd = commandById(commands, 'fate-juice')!;
    final r = cmd.run(oracleWith(8), {'odds': 'nonsense'});
    expect(r.title, 'Fate Check (Normal)');
  });

  test('fate-mythic uses chaos arg and stores it back', () {
    final cmd = commandById(commands, 'fate-mythic')!;
    final r = cmd.run(oracleWith(9), {'odds': '50/50', 'chaos': '7'});
    expect(r.payload['args'], {'odds': '50/50', 'chaos': '7'});
    // The Chaos roll row carries the chaos detail (engine emits it).
    expect(r.body, contains('Chaos'));
  });

  test('fate-roll-high defaults die d20 / odds Unknown', () {
    final cmd = commandById(commands, 'fate-roll-high')!;
    final r = cmd.run(oracleWith(10), {});
    expect(r.payload['args'], {'odds': 'Unknown', 'die': 'd20'});
    expect(r.body, contains('d20'));
  });

  test('dice rolls notation and rejects garbage', () {
    final cmd = commandById(commands, 'dice')!;
    final r = cmd.run(oracleWith(11), {'notation': '3d6+2'});
    expect(r.title, 'Dice Roll');
    expect(r.payload['args'], {'notation': '3d6+2'});
    expect(r.payload['summary'], matches(RegExp(r'^3d6\+2 = \d+$')));
    expect(() => cmd.run(oracleWith(11), {'notation': 'zzz'}),
        throwsFormatException);
    expect(() => cmd.run(oracleWith(11), {}), throwsFormatException);
  });

  test('meaning, name, detail run without args', () {
    for (final id in ['meaning', 'name', 'detail']) {
      final r = commandById(commands, id)!.run(oracleWith(12), {});
      expect(r.payload['rolls'], isNotEmpty, reason: id);
      expect(r.payload['rerollable'], true, reason: id);
    }
  });

  test('commandById returns null for unknown', () {
    expect(commandById(commands, 'nope'), isNull);
  });

  group('slash parsing + matching', () {
    final reg = buildCommandRegistry();

    test('parseSlash returns null when not a slash command', () {
      expect(parseSlash('hello'), isNull);
      expect(parseSlash('  /fate'), isNull); // must be leading char
      expect(parseSlash(''), isNull);
    });

    test('parseSlash splits token and rest', () {
      expect(parseSlash('/'), (token: '', rest: ''));
      expect(parseSlash('/fa'), (token: 'fa', rest: ''));
      expect(parseSlash('/dice 3d6+2'), (token: 'dice', rest: '3d6+2'));
      expect(parseSlash('/fate likely'), (token: 'fate', rest: 'likely'));
      expect(parseSlash('/name  '), (token: 'name', rest: ''));
    });

    test('matchCommands by empty token returns all', () {
      expect(matchCommands(reg, '').length, reg.length);
    });

    test('matchCommands filters by id/keyword/label prefix-ish', () {
      final dice = matchCommands(reg, 'dice');
      expect(dice.map((c) => c.id), contains('dice'));
      final fate = matchCommands(reg, 'fate');
      // all three fate commands match the keyword 'fate'
      expect(fate.map((c) => c.id),
          containsAll(['fate-juice', 'fate-mythic', 'fate-roll-high']));
      expect(matchCommands(reg, 'zzz'), isEmpty);
    });

    test('matchCommands is case-insensitive', () {
      expect(matchCommands(reg, 'DICE').map((c) => c.id), contains('dice'));
    });
  });

  test('command bodies equal the payload-derived text (render contract)', () {
    // Render shows summary+rolls; body must start from the same text so the
    // journal can detect appended notes (see journal payload rendering).
    for (final id in [
      'fate-juice',
      'fate-mythic',
      'fate-roll-high',
      'meaning',
      'name',
      'detail'
    ]) {
      final r = commandById(commands, id)!.run(oracleWith(13), {});
      final rolls = (r.payload['rolls'] as List)
          .map((m) => '${m['label']}: ${m['display']}')
          .join('\n');
      final expected = r.payload.containsKey('summary')
          ? '${r.payload['summary']}\n$rolls'
          : rolls;
      expect(r.body, expected, reason: id);
    }
  });
}
