import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/emulator_data.dart';

void main() {
  // Tests run with CWD = project root, so read the asset file directly
  // (avoids rootBundle, which needs a widget-test asset bundle). The raw
  // map stays available so expectations can be derived from the asset.
  final raw = jsonDecode(File('assets/emulator_data.json').readAsStringSync())
      as Map<String, dynamic>;
  final data = EmulatorData(raw);

  final d66Keys = [
    for (var t = 1; t <= 6; t++)
      for (var u = 1; u <= 6; u++) t * 10 + u,
  ];

  test('spark and specific table names come in zine order', () {
    expect(data.sparkNames, [
      'action',
      'focus',
      'method',
      'disposition',
      'motivation',
      'dynamics',
    ]);
    expect(data.specificNames, [
      'combat',
      'social',
      'exploration',
      'delving',
      'interpretation',
      'downtime',
      'planning',
    ]);
  });

  test('every d66 table carries exactly keys 11..66 with non-empty text', () {
    for (final name in data.sparkNames) {
      final table = data.sparkTable(name);
      expect(table.keys.toList()..sort(), d66Keys, reason: name);
      expect(table.values.every((v) => v.trim().isNotEmpty), isTrue,
          reason: name);
    }
    for (final name in data.specificNames) {
      final table = data.specificTable(name);
      expect(table.keys.toList()..sort(), d66Keys, reason: name);
      expect(table.values.every((v) => v.trim().isNotEmpty), isTrue,
          reason: name);
    }
  });

  test('pinned cells match the zine (transcription anchors)', () {
    expect(data.d66Entry('combat', 11), 'Aim carefully, wait for an opening');
    expect(data.d66Entry('social', 25), 'Confide a secret');
    expect(data.d66Entry('action', 11), 'Abort');
    expect(data.d66Entry('dynamics', 66), 'Uneasy');
    expect(data.d66Entry('method', 34), 'Magic');
    expect(data.d66Entry('planning', 55), 'Split the party');
  });

  test('throws on unknown table or bad key', () {
    expect(() => data.sparkTable('nope'), throwsArgumentError);
    expect(() => data.specificTable('action'), throwsArgumentError);
    expect(() => data.d66Entry('nope', 11), throwsArgumentError);
    expect(() => data.d66Entry('combat', 10), throwsArgumentError);
  });

  test('agendaEntry returns the keyed agenda row (anchors pinned)', () {
    final a = data.agendaEntry(2);
    expect(a.key, 2);
    expect(a.group, 'Drama');
    expect(a.name, 'DRAMA');
    expect(a.ask, 'what would be the worst thing to reveal right now?');
    expect(a.flavor, contains('dark secrets'));
    expect(data.agendaEntry(12).name, 'AGREEABLE');
  });

  test('focusEntry returns the keyed focus row (anchors pinned)', () {
    final f = data.focusEntry(2);
    expect(f.key, 2);
    expect(f.name, 'PLAYFUL');
    expect(f.blurb, startsWith('a focus on relaxing'));
    expect(data.focusEntry(12).name, 'APATHETIC');
  });

  test('agendaEntry and focusEntry throw outside 2..12', () {
    expect(() => data.agendaEntry(1), throwsArgumentError);
    expect(() => data.agendaEntry(13), throwsArgumentError);
    expect(() => data.focusEntry(1), throwsArgumentError);
    expect(() => data.focusEntry(13), throwsArgumentError);
  });

  test('PET lists: 36 personality tags, 6 consequences, 6 real-life', () {
    expect(data.personalityTags, hasLength(36));
    expect(data.personalityTags.first, 'chatty');
    expect(data.consequences, hasLength(6));
    expect(data.consequences[0], 'expose a weakness');
    expect(data.realLife, hasLength(6));
    expect(data.realLife[5], 'victorious');
  });

  test('attribution carries both license lines', () {
    expect(data.attribution, [
      'PET & Sidekick © Tam H (hedonic.ink), CC-BY 4.0',
      'Triple-O © Cezar Capacle / Critical Kit, CC-BY-SA 4.0',
    ]);
  });

  // -- Sidekick (phase 4) -----------------------------------------------------

  Map<String, dynamic> section(String key) =>
      (raw['sidekick'] as Map<String, dynamic>)[key] as Map<String, dynamic>;

  test('moods come in printed order', () {
    expect(data.moods,
        ['default', 'taciturn', 'savvy', 'high_strung', 'sassy', 'selfish']);
    expect(data.moods, kSidekickMoods);
  });

  test('dialogueLine returns the keyed line; high_strung remap intact', () {
    expect(data.dialogueLine('default', 2), 'Look out!');
    // High-Strung is printed 1-11 in the zine (a slip) and remapped to 2-12
    // by the pipeline; pin a cell against the asset, not a hand-typed copy.
    final highStrung = section('dialogue')['high_strung'] as Map;
    expect(data.dialogueLine('high_strung', 2), highStrung['2']);
  });

  test('dialogueLine throws on unknown mood or key outside 2..12', () {
    expect(() => data.dialogueLine('grumpy', 7), throwsArgumentError);
    expect(() => data.dialogueLine('default', 1), throwsArgumentError);
    expect(() => data.dialogueLine('default', 13), throwsArgumentError);
  });

  test('tone/topic/said-how chip lists carry six entries (anchors pinned)', () {
    expect(data.tones, hasLength(6));
    expect(data.tones[0], 'aggressive');
    expect(data.topics, hasLength(6));
    expect(data.topics[5], 'anecdote');
    expect(data.saidHowA, hasLength(6));
    expect(data.saidHowA[5], 'neutrally');
    expect(data.saidHowB, hasLength(6));
    expect(data.saidHowB[0], 'ruefully');
  });

  test('hex returns index/q/r/topic/context (anchors pinned)', () {
    final center = data.hex(0);
    expect(center.index, 0);
    expect((center.q, center.r), (0, 0));
    expect(center.topic, 'fact');
    expect(center.context, 'red');
    final need = data.hex(6);
    expect(need.topic, 'need');
    expect(need.context, 'gray');
    expect(() => data.hex(-1), throwsArgumentError);
    expect(() => data.hex(19), throwsArgumentError);
  });

  test('hexNeighbors: center touches ring 1; adjacency symmetric all over', () {
    expect(data.hexNeighbors(0), [1, 2, 3, 4, 5, 6]);
    for (var i = 0; i < 19; i++) {
      for (final n in data.hexNeighbors(i)) {
        expect(data.hexNeighbors(n), contains(i), reason: '$i <-> $n');
      }
    }
    expect(() => data.hexNeighbors(19), throwsArgumentError);
  });

  test('hexDirection maps every 2d6 sum per the asset overlay', () {
    final directions = section('hexflower')['directions'] as Map;
    for (var key = 2; key <= 12; key++) {
      expect(data.hexDirection(key), directions['$key'], reason: 'key $key');
    }
    expect(() => data.hexDirection(1), throwsArgumentError);
    expect(() => data.hexDirection(13), throwsArgumentError);
  });

  test('hexStep follows direction_deltas over q/r; off-edge is null', () {
    final hexflower = section('hexflower');
    final deltas = hexflower['direction_deltas'] as Map;
    final hexes = (hexflower['hexes'] as List).cast<Map<String, dynamic>>();
    int? indexAt(int q, int r) {
      for (final h in hexes) {
        if (h['q'] == q && h['r'] == r) return h['index'] as int;
      }
      return null;
    }

    // From the center, key 12 ('N') lands on the northern ring-1 hex —
    // expectation derived from the asset's own deltas, not hand-encoded.
    final north = deltas[data.hexDirection(12)] as List;
    final expected = indexAt(north[0] as int, north[1] as int);
    expect(expected, isNotNull);
    expect(data.hexStep(0, 12), expected);

    // Full sweep: every (hex, key) agrees with the deltas-derived neighbor;
    // landings are always adjacent; off-flower steps are null.
    for (final h in hexes) {
      for (var key = 2; key <= 12; key++) {
        final d = deltas[data.hexDirection(key)] as List;
        final target = indexAt(
            (h['q'] as int) + (d[0] as int), (h['r'] as int) + (d[1] as int));
        final from = h['index'] as int;
        expect(data.hexStep(from, key), target, reason: 'hex $from key $key');
        if (target != null) {
          expect(data.hexNeighbors(from), contains(target));
        }
      }
    }

    // An edge hex stepping outward: hex 7 (top of the flower) due N.
    expect(data.hexStep(7, 12), isNull);
  });
}
