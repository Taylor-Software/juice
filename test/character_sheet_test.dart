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

  group('IronswornSheet', () {
    test('premade defaults match the standard starting sheet', () {
      final s = IronswornSheet.premade();
      expect([s.edge, s.heart, s.iron, s.shadow, s.wits], [3, 2, 2, 1, 1]);
      expect([s.health, s.spirit, s.supply], [5, 5, 5]);
      expect(s.momentum, 2);
      expect(s.momentumMax, 10);
      expect(s.momentumReset, 2);
    });

    test('debilities lower max + reset and re-clamp momentum via copyWith', () {
      final s = const IronswornSheet(momentum: 10)
          .copyWith(debilities: {'wounded', 'shaken'});
      expect(s.momentumMax, 8);
      expect(s.momentumReset, 0);
      expect(s.momentum, 8); // re-clamped down to the new max
    });

    test('values are clamped to legal ranges', () {
      final s = const IronswornSheet().copyWith(
        edge: 9,
        health: 99,
        supply: -2,
        momentum: 99,
        bonds: 50,
        xpSpent: -3,
      );
      expect(s.edge, 3);
      expect(s.health, 5);
      expect(s.supply, 0);
      expect(s.momentum, 10);
      expect(s.bonds, 10);
      expect(s.xpSpent, 0);
    });

    test('round-trips with vows, assets, debilities', () {
      const s = IronswornSheet(
        edge: 3,
        heart: 2,
        iron: 2,
        shadow: 1,
        wits: 1,
        health: 4,
        spirit: 3,
        supply: 5,
        momentum: -2,
        xpEarned: 6,
        xpSpent: 4,
        bonds: 3,
        debilities: {'shaken'},
        vows: [
          ProgressTrack(name: 'Avenge', rank: ProgressRank.dangerous, ticks: 8)
        ],
        assets: [AssetState(assetId: 'a/assets/b/c', name: 'Wolf')],
      );
      final back = IronswornSheet.maybeFromJson(s.toJson())!;
      expect(back.health, 4);
      expect(back.momentum, -2);
      expect(back.debilities, {'shaken'});
      expect(back.vows.single.ticks, 8);
      expect(back.assets.single.name, 'Wolf');
      expect(back.momentumMax, 9);
    });

    test('tolerates junk and unknown debility ids', () {
      expect(IronswornSheet.maybeFromJson('x'), isNull);
      final s = IronswornSheet.maybeFromJson({
        'edge': 'three',
        'momentum': 'fast',
        'debilities': ['wounded', 'bogus', 7],
        'vows': ['junk'],
        'assets': 'nope',
      })!;
      expect(s.edge, 1); // default
      expect(s.momentum, 2); // default
      expect(s.debilities, {'wounded'}); // unknown id dropped
      expect(s.vows, isEmpty);
      expect(s.assets, isEmpty);
    });
  });

  group('Character.ironsworn', () {
    test('round-trips and is omitted when null', () {
      const plain = Character(id: 'p', name: 'Plain');
      expect(plain.toJson().containsKey('ironsworn'), isFalse);
      expect(Character.fromJson(plain.toJson()).ironsworn, isNull);

      final c =
          Character(id: 'i', name: 'Ulla', ironsworn: IronswornSheet.premade());
      final back = Character.fromJson(c.toJson());
      expect(back.ironsworn!.edge, 3);
      expect(back.ironsworn!.momentum, 2);
    });

    test('copyWith sets and clears ironsworn', () {
      const c = Character(id: 'i2', name: 'L');
      final set = c.copyWith(ironsworn: IronswornSheet.premade());
      expect(set.ironsworn, isNotNull);
      expect(set.copyWith().ironsworn, isNotNull);
      expect(set.copyWith(clearIronsworn: true).ironsworn, isNull);
    });

    test('junk ironsworn block is tolerated as null', () {
      final c =
          Character.fromJson({'id': 'i3', 'name': 'J', 'ironsworn': 'junk'});
      expect(c.ironsworn, isNull);
    });
  });

  group('IronswornAssetDef.listFromRuleset', () {
    test('flattens asset_collections and seeds default ability flags', () {
      final ruleset = {
        'asset_collections': [
          {
            'name': 'Combat Talent',
            'assets': [
              {
                'id': 'classic/assets/combat_talent/swordmaster',
                'name': 'Swordmaster',
                'category': 'Combat Talent',
                'abilities': [
                  {'text': 'A', 'enabled': true},
                  {'text': 'B', 'enabled': false},
                ],
              },
            ],
          },
          {'name': 'Junk', 'assets': 'not a list'},
        ],
      };
      final defs = IronswornAssetDef.listFromRuleset(ruleset);
      expect(defs, hasLength(1));
      expect(defs.single.name, 'Swordmaster');
      expect(defs.single.abilities, ['A', 'B']);
      expect(defs.single.abilityEnabled, [true, false]);
      final st = defs.single.toState();
      expect(st.assetId, 'classic/assets/combat_talent/swordmaster');
      expect(st.enabledAbilities, [true, false]);
    });

    test('returns empty for a map with no asset_collections', () {
      expect(IronswornAssetDef.listFromRuleset({'meta': {}}), isEmpty);
    });
  });
}
