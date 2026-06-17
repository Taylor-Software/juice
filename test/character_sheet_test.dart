import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('legacy character JSON parses with empty blocks', () {
    final c = Character.fromJson({'id': '1', 'name': 'Ash', 'note': 'ranger'});
    expect(c.stats, isEmpty);
    expect(c.tracks, isEmpty);
    expect(c.tags, isEmpty);
    expect(c.note, 'ranger');
  });

  test('full sheet round-trips', () {
    const c = Character(
      id: '2',
      name: 'Brynn',
      note: 'smith',
      stats: [CharStat(label: 'Iron', value: '+2')],
      tracks: [CharTrack(label: 'HP', current: 7, max: 10)],
      tags: ['wounded', 'bond'],
    );
    final back = Character.fromJson(c.toJson());
    expect(back.stats.single.label, 'Iron');
    expect(back.stats.single.value, '+2');
    expect(back.tracks.single.current, 7);
    expect(back.tracks.single.max, 10);
    expect(back.tags, ['wounded', 'bond']);
  });

  test('copyWith replaces blocks and adjusted clamps', () {
    const c = Character(id: '3', name: 'X');
    final edited = c.copyWith(
      tracks: const [CharTrack(label: 'HP', current: 5, max: 10)],
    );
    expect(edited.tracks.single.label, 'HP');
    expect(edited.name, 'X');
    const t = CharTrack(label: 'HP', current: 5, max: 10);
    expect(t.adjusted(7).current, 10);
    expect(t.adjusted(-9).current, 0);
  });

  test('malformed block entries are skipped, not fatal', () {
    final c = Character.fromJson({
      'id': '4',
      'name': 'Y',
      'stats': [
        {'label': 'Edge', 'value': '1'},
        'junk',
      ],
      'tracks': [
        {'label': 'HP'},
      ],
      'tags': ['ok', 42],
    });
    expect(c.stats.single.label, 'Edge');
    expect(c.tracks.single.max, 0);
    expect(c.tags, ['ok']);
  });

  test('negative track values are sanitized on parse', () {
    final c = Character.fromJson({
      'id': '5',
      'name': 'Z',
      'tracks': [
        {'label': 'HP', 'current': 12, 'max': -3},
      ],
    });
    expect(c.tracks.single.current, 0);
    expect(c.tracks.single.max, 0);
  });

  group('CharacterEmulation', () {
    test('full emulation round-trips through Character JSON', () {
      const c = Character(
        id: 'e1',
        name: 'Em',
        emulation: CharacterEmulation(
          agendaKey: 7,
          focusKey: 12,
          mood: 'sassy',
          tokens: 3,
          prominentTags: ['brave'],
          usedTags: ['curious'],
          hexIndex: 9,
        ),
      );
      final e = Character.fromJson(c.toJson()).emulation!;
      expect(e.agendaKey, 7);
      expect(e.focusKey, 12);
      expect(e.mood, 'sassy');
      expect(e.tokens, 3);
      expect(e.prominentTags, ['brave']);
      expect(e.usedTags, ['curious']);
      expect(e.hexIndex, 9);
    });

    test('null emulation is omitted from character JSON', () {
      const c = Character(id: 'e2', name: 'Plain');
      expect(c.toJson().containsKey('emulation'), isFalse);
      expect(Character.fromJson(c.toJson()).emulation, isNull);
    });

    test('null emulation fields are omitted from its JSON', () {
      final json = const CharacterEmulation(tokens: 2).toJson();
      expect(
          json.keys, unorderedEquals(['tokens', 'prominentTags', 'usedTags']));
    });

    test('legacy character JSON parses with null emulation', () {
      final c = Character.fromJson({'id': 'e3', 'name': 'Old'});
      expect(c.emulation, isNull);
    });

    test('junk emulation block and junk fields are tolerated', () {
      expect(
          Character.fromJson({'id': 'e4', 'name': 'J', 'emulation': 'junk'})
              .emulation,
          isNull);
      final e = Character.fromJson({
        'id': 'e5',
        'name': 'K',
        'emulation': {
          'agendaKey': 'seven',
          'mood': 42,
          'tokens': 'many',
          'prominentTags': ['ok', 7],
          'usedTags': 'nope',
          'hexIndex': 3.5,
        },
      }).emulation!;
      expect(e.agendaKey, isNull);
      expect(e.focusKey, isNull);
      expect(e.mood, isNull);
      expect(e.tokens, 0);
      expect(e.prominentTags, ['ok']);
      expect(e.usedTags, isEmpty);
      expect(e.hexIndex, isNull);
    });

    test('copyWith clear flags null the nullable fields', () {
      const e = CharacterEmulation(
          agendaKey: 5, focusKey: 6, mood: 'savvy', tokens: 1, hexIndex: 2);
      final cleared = e.copyWith(
          clearAgenda: true, clearFocus: true, clearMood: true, clearHex: true);
      expect(cleared.agendaKey, isNull);
      expect(cleared.focusKey, isNull);
      expect(cleared.mood, isNull);
      expect(cleared.hexIndex, isNull);
      expect(cleared.tokens, 1);
      final kept = e.copyWith(tokens: 4, prominentTags: ['brave']);
      expect(kept.agendaKey, 5);
      expect(kept.focusKey, 6);
      expect(kept.mood, 'savvy');
      expect(kept.hexIndex, 2);
      expect(kept.tokens, 4);
      expect(kept.prominentTags, ['brave']);
      expect(kept.usedTags, isEmpty);
    });

    test('Character.copyWith sets and clears emulation', () {
      const c = Character(id: 'e6', name: 'L');
      final set = c.copyWith(emulation: const CharacterEmulation(tokens: 1));
      expect(set.emulation!.tokens, 1);
      expect(set.copyWith().emulation, isNotNull);
      expect(set.copyWith(clearEmulation: true).emulation, isNull);
    });
  });

  group('ProgressTrack', () {
    test('marks advance ticks by rank size and clamp at 40', () {
      const t = ProgressTrack(name: 'Vow', rank: ProgressRank.formidable);
      expect(t.markTicks, 4); // convenience getter on the track
      final once = t.marked(1);
      expect(once.ticks, 4);
      expect(once.boxes, 1);
      expect(t.marked(20).ticks, 40); // clamped
      expect(t.marked(-1).ticks, 0); // clamped
    });

    test('round-trips and tolerates junk', () {
      const t =
          ProgressTrack(name: 'Avenge', rank: ProgressRank.epic, ticks: 7);
      final back = ProgressTrack.maybeFromJson(t.toJson())!;
      expect(back.name, 'Avenge');
      expect(back.rank, ProgressRank.epic);
      expect(back.ticks, 7);
      expect(ProgressTrack.maybeFromJson('nope'), isNull);
      final j = ProgressTrack.maybeFromJson(
          {'name': 42, 'rank': 'bogus', 'ticks': 99})!;
      expect(j.name, '');
      expect(j.rank, ProgressRank.dangerous); // default
      expect(j.ticks, 40); // clamped
    });
  });

  group('AssetState', () {
    test('round-trips with ability flags', () {
      const a = AssetState(
        assetId: 'classic/assets/combat_talent/swordmaster',
        name: 'Swordmaster',
        category: 'Combat Talent',
        enabledAbilities: [true, false, false],
      );
      final back = AssetState.maybeFromJson(a.toJson())!;
      expect(back.assetId, a.assetId);
      expect(back.name, 'Swordmaster');
      expect(back.category, 'Combat Talent');
      expect(back.enabledAbilities, [true, false, false]);
    });

    test('rejects entries with no id; coerces junk flags', () {
      expect(AssetState.maybeFromJson({'name': 'x'}), isNull);
      final a = AssetState.maybeFromJson({
        'assetId': 'id/assets/x/y',
        'enabledAbilities': [1, true, 'no'],
      })!;
      expect(a.name, '');
      expect(a.enabledAbilities, [false, true, false]);
    });
  });
}
