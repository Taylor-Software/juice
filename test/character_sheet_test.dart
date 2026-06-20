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

  group('Character.starforged', () {
    test('round-trips and is omitted when null', () {
      const plain = Character(id: 'p', name: 'Plain');
      expect(plain.toJson().containsKey('starforged'), isFalse);
      final c = Character(
          id: 's', name: 'Nova', starforged: StarforgedSheet.premade());
      final back = Character.fromJson(c.toJson());
      expect(back.starforged!.edge, 3);
      expect(back.starforged!.momentum, 2);
    });

    test('copyWith sets and clears starforged', () {
      const c = Character(id: 's2', name: 'L');
      final set = c.copyWith(starforged: StarforgedSheet.premade());
      expect(set.starforged, isNotNull);
      expect(set.copyWith().starforged, isNotNull);
      expect(set.copyWith(clearStarforged: true).starforged, isNull);
    });

    test('junk starforged block is tolerated as null', () {
      final c =
          Character.fromJson({'id': 's3', 'name': 'J', 'starforged': 'junk'});
      expect(c.starforged, isNull);
    });
  });

  group('Character.dnd', () {
    test('round-trips and is omitted when null', () {
      const plain = Character(id: 'p', name: 'Plain');
      expect(plain.toJson().containsKey('dnd'), isFalse);
      final c = Character(id: 'd', name: 'Tarin', dnd: DndSheet.premade());
      final back = Character.fromJson(c.toJson());
      expect(back.dnd!.className, 'Fighter');
      expect(back.dnd!.score('str'), 15);
    });

    test('copyWith sets and clears dnd', () {
      const c = Character(id: 'd2', name: 'L');
      final set = c.copyWith(dnd: DndSheet.premade());
      expect(set.dnd, isNotNull);
      expect(set.copyWith().dnd, isNotNull);
      expect(set.copyWith(clearDnd: true).dnd, isNull);
    });

    test('junk dnd block tolerated as null', () {
      expect(Character.fromJson({'id': 'd3', 'name': 'J', 'dnd': 'junk'}).dnd,
          isNull);
    });
  });

  group('Character.shadowdark', () {
    test('round-trips and is omitted when null', () {
      const plain = Character(id: 'p', name: 'Plain');
      expect(plain.toJson().containsKey('shadowdark'), isFalse);
      final c = Character(
          id: 'sd', name: 'Mort', shadowdark: ShadowdarkSheet.premade());
      final back = Character.fromJson(c.toJson());
      expect(back.shadowdark!.className, 'Fighter');
      expect(back.shadowdark!.ancestry, 'Human');
    });

    test('copyWith sets and clears shadowdark', () {
      const c = Character(id: 'sd2', name: 'L');
      final set = c.copyWith(shadowdark: ShadowdarkSheet.premade());
      expect(set.shadowdark, isNotNull);
      expect(set.copyWith().shadowdark, isNotNull);
      expect(set.copyWith(clearShadowdark: true).shadowdark, isNull);
    });

    test('junk shadowdark block tolerated as null', () {
      expect(
          Character.fromJson({'id': 'x', 'name': 'J', 'shadowdark': 'junk'})
              .shadowdark,
          isNull);
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

    test('parses condition_meter controls into asset meters (seeded default)',
        () {
      final ruleset = {
        'asset_collections': [
          {
            'name': 'Companion Assets',
            'assets': [
              {
                'id': 'sf/assets/companion/banshee',
                'name': 'Banshee',
                'abilities': [
                  {'text': 'A', 'enabled': true}
                ],
                'controls': {
                  'health': {
                    'label': 'health',
                    'field_type': 'condition_meter',
                    'min': 0,
                    'max': 4,
                    'value': 4,
                    'controls': {'out_of_action': {'field_type': 'checkbox'}},
                  },
                  'doc': {'field_type': 'text'}, // ignored (not a meter)
                },
              },
            ],
          },
        ],
      };
      final def = IronswornAssetDef.listFromRuleset(ruleset).single;
      expect(def.meters, hasLength(1));
      final m = def.meters.single;
      expect(m.key, 'health');
      expect(m.max, 4);
      expect(m.value, 4); // seeded from default
      // toState carries the meters onto the persisted asset.
      expect(def.toState().meters.single.value, 4);
    });
  });

  group('AssetMeter / AssetState meters', () {
    test('round-trips meters through JSON', () {
      const a = AssetState(
        assetId: 'x',
        name: 'Banshee',
        meters: [AssetMeter(key: 'health', label: 'health', min: 0, max: 4, value: 2)],
      );
      final back = AssetState.maybeFromJson(a.toJson())!;
      expect(back.meters.single.key, 'health');
      expect(back.meters.single.value, 2);
      expect(back.meters.single.max, 4);
    });

    test('copyWith clamps the value to [min, max]', () {
      const m = AssetMeter(key: 'h', label: 'h', min: 0, max: 4, value: 2);
      expect(m.copyWith(value: 9).value, 4);
      expect(m.copyWith(value: -3).value, 0);
      expect(m.copyWith(value: 3).value, 3);
    });
  });

  group('DndSheet', () {
    test('ability modifier floors correctly (incl. odd low scores)', () {
      DndSheet s(int v) => DndSheet(abilities: {'str': v});
      expect(s(1).abilityMod('str'), -5);
      expect(s(7).abilityMod('str'), -2); // ~/ would wrongly give -1
      expect(s(8).abilityMod('str'), -1);
      expect(s(10).abilityMod('str'), 0);
      expect(s(15).abilityMod('str'), 2);
      expect(s(20).abilityMod('str'), 5);
    });

    test('derived stats: prof bonus, saves, skills, passive perception', () {
      const s = DndSheet(
        abilities: {
          'str': 16,
          'dex': 14,
          'con': 12,
          'int': 8,
          'wis': 13,
          'cha': 10
        },
        level: 5, // prof +3
        saveProficiencies: {'str', 'con'},
        skillProficiencies: {'athletics', 'perception'},
        skillExpertise: {'athletics'},
      );
      expect(s.proficiencyBonus, 3);
      expect(s.saveBonus('str'), 6); // +3 mod + 3 prof
      expect(s.saveBonus('dex'), 2); // +2 mod, not proficient
      expect(s.skillBonus('athletics'), 9); // str +3, expertise => +3*2
      expect(s.skillBonus('perception'), 4); // wis +1 + prof 3
      expect(s.skillBonus('stealth'), 2); // dex +2, not proficient
      expect(s.passivePerception, 14); // 10 + 4
      expect(s.hitDie, 10); // Fighter
      expect(s.initiative, 2); // dex mod
    });

    test('premade is a level-1 Fighter with the standard array', () {
      final s = DndSheet.premade();
      expect(s.className, 'Fighter');
      expect(s.score('str'), 15);
      expect(s.maxHp, 12);
      expect(s.saveProficiencies, {'str', 'con'});
      expect(s.proficiencyBonus, 2);
    });

    test('round-trips and clamps; tolerant of junk', () {
      const s = DndSheet(
        abilities: {
          'str': 16,
          'dex': 14,
          'con': 12,
          'int': 8,
          'wis': 13,
          'cha': 10
        },
        className: 'Wizard',
        level: 7,
        race: 'Elf',
        ac: 15,
        currentHp: 30,
        maxHp: 38,
        hitDiceRemaining: 4,
        saveProficiencies: {'int', 'wis'},
        skillProficiencies: {'arcana'},
        conditions: {'poisoned'},
        exhaustionLevel: 2,
        deathSaveSuccesses: 1,
        featuresText: 'Spellcasting',
      );
      final back = DndSheet.maybeFromJson(s.toJson())!;
      expect(back.className, 'Wizard');
      expect(back.level, 7);
      expect(back.score('str'), 16);
      expect(back.conditions, {'poisoned'});
      expect(back.exhaustionLevel, 2);
      expect(back.featuresText, 'Spellcasting');

      expect(DndSheet.maybeFromJson('x'), isNull);
      final j = DndSheet.maybeFromJson({
        'abilities': {'str': 99, 'dex': 'big'},
        'className': 'Bogus',
        'level': 50,
        'saveProficiencies': ['str', 'nope'],
        'skillProficiencies': ['arcana', 'junk'],
        'conditions': ['poisoned', 'invented'],
        'exhaustionLevel': 9,
      })!;
      expect(j.score('str'), 30); // clamped 1..30
      expect(j.score('dex'), 10); // junk -> default
      expect(j.className, 'Fighter'); // unknown -> default
      expect(j.level, 20); // clamped
      expect(j.saveProficiencies, {'str'}); // unknown ability dropped
      expect(j.skillProficiencies, {'arcana'}); // unknown skill dropped
      expect(j.conditions, {'poisoned'}); // unknown condition dropped
      expect(j.exhaustionLevel, 6); // clamped 0..6
    });
  });

  group('DndSheet spell slots', () {
    test('slot tables match the SRD full/half/pact tables', () {
      DndSheet caster(String c, int lvl) => DndSheet(className: c, level: lvl);
      // Full caster (Wizard)
      expect(caster('Wizard', 1).slotMax(1), 2);
      expect(caster('Wizard', 1).slotMax(2), 0);
      expect([for (var l = 1; l <= 9; l++) caster('Wizard', 5).slotMax(l)],
          [4, 3, 2, 0, 0, 0, 0, 0, 0]);
      expect([for (var l = 1; l <= 9; l++) caster('Wizard', 20).slotMax(l)],
          [4, 3, 3, 3, 3, 2, 2, 1, 1]);
      // Half caster (Paladin): none at L1, 5th-level slots at L19+
      expect(caster('Paladin', 1).slotMax(1), 0);
      expect(caster('Paladin', 2).slotMax(1), 2);
      expect(caster('Paladin', 20).slotMax(5), 2);
      expect(caster('Paladin', 20).slotMax(6), 0); // half casters cap at 5th
      // Warlock pact magic
      expect(caster('Warlock', 1).pactSlotCount, 1);
      expect(caster('Warlock', 1).pactSlotLevel, 1);
      expect(caster('Warlock', 11).pactSlotCount, 3);
      expect(caster('Warlock', 20).pactSlotCount, 4);
      expect(caster('Warlock', 20).pactSlotLevel, 5);
      expect(
          caster('Warlock', 5).slotMax(1), 0); // warlock uses pact, not slotMax
    });

    test('isCaster + derived DC/attack/ability', () {
      const w = DndSheet(
        className: 'Wizard',
        level: 5,
        abilities: {
          'str': 8,
          'dex': 14,
          'con': 12,
          'int': 16,
          'wis': 10,
          'cha': 10
        },
      );
      expect(w.isCaster, isTrue);
      expect(w.spellcastingAbility, 'int');
      expect(w.spellcastingMod, 3); // int 16 -> +3
      expect(w.proficiencyBonus, 3); // level 5
      expect(w.spellSaveDC, 14); // 8 + 3 + 3
      expect(w.spellAttackBonus, 6); // 3 + 3
      const f = DndSheet(className: 'Fighter', level: 5);
      expect(f.isCaster, isFalse);
      expect(f.spellcastingAbility, isNull);
      expect(f.spellSaveDC, isNull);
    });

    test('round-trips; normalizes spellSlotsUsed to length 9; omits defaults',
        () {
      const s = DndSheet(
        className: 'Wizard',
        level: 3,
        spellSlotsUsed: [1, 0, 0, 0, 0, 0, 0, 0, 0],
        pactSlotsUsed: 0,
        preparedSpells: 'Mage Hand, Shield',
      );
      final back = DndSheet.maybeFromJson(s.toJson())!;
      expect(back.spellSlotsUsed.length, 9);
      expect(back.spellSlotsUsed[0], 1);
      expect(back.preparedSpells, 'Mage Hand, Shield');
      // defaults omitted
      expect(
          DndSheet.premade().toJson().containsKey('spellSlotsUsed'), isFalse);
      expect(
          DndSheet.premade().toJson().containsKey('preparedSpells'), isFalse);
      // tolerant: short/junk list normalized to length 9, negatives floored to 0
      final j = DndSheet.maybeFromJson({
        'className': 'Wizard',
        'spellSlotsUsed': [-3, 'x', 2],
        'pactSlotsUsed': -1,
      })!;
      expect(j.spellSlotsUsed.length, 9);
      expect(j.spellSlotsUsed[0], 0); // -3 floored
      expect(j.spellSlotsUsed[2], 2);
      expect(j.pactSlotsUsed, 0);
    });
  });

  group('ShadowdarkSheet', () {
    test('abilityMod floors; gearSlotCapacity = max(STR,10)', () {
      ShadowdarkSheet s(Map<String, int> a) => ShadowdarkSheet(abilities: a);
      expect(s({'str': 3}).abilityMod('str'), -4);
      expect(s({'str': 7}).abilityMod('str'), -2);
      expect(s({'str': 10}).abilityMod('str'), 0);
      expect(s({'str': 18}).abilityMod('str'), 4);
      expect(s({'str': 8}).gearSlotCapacity, 10);
      expect(s({'str': 15}).gearSlotCapacity, 15);
    });

    test('hit die + caster derivations', () {
      const w = ShadowdarkSheet(className: 'Wizard', abilities: {
        'str': 8,
        'dex': 12,
        'con': 10,
        'int': 16,
        'wis': 10,
        'cha': 10
      });
      expect(w.hitDie, 4);
      expect(w.isCaster, isTrue);
      expect(w.castingAbility, 'int');
      expect(w.castingMod, 3);
      const f = ShadowdarkSheet(className: 'Fighter');
      expect(f.hitDie, 8);
      expect(f.isCaster, isFalse);
      expect(f.castingAbility, isNull);
      expect(f.castingMod, isNull);
    });

    test('premade is a level-1 Human Fighter', () {
      final s = ShadowdarkSheet.premade();
      expect(s.className, 'Fighter');
      expect(s.ancestry, 'Human');
      expect(s.alignment, 'Neutral');
      expect(s.level, 1);
      expect(s.maxHp, 8);
    });

    test('round-trips; tolerant; coerces unknown enums + clamps', () {
      const s = ShadowdarkSheet(
        className: 'Priest',
        ancestry: 'Elf',
        alignment: 'Lawful',
        level: 3,
        xp: 12,
        ac: 15,
        currentHp: 14,
        maxHp: 18,
        gearSlotsUsed: 5,
        luckToken: true,
        title: 'Crusader',
        deity: 'Saint Terragnis',
        talentsText: '+1 atk',
        spellsText: 'Cure Wounds',
        abilities: {'wis': 14},
      );
      final back = ShadowdarkSheet.maybeFromJson(s.toJson())!;
      expect(back.className, 'Priest');
      expect(back.ancestry, 'Elf');
      expect(back.alignment, 'Lawful');
      expect(back.luckToken, isTrue);
      expect(back.title, 'Crusader');
      expect(back.deity, 'Saint Terragnis');
      expect(back.score('wis'), 14);

      expect(ShadowdarkSheet.maybeFromJson('x'), isNull);
      final j = ShadowdarkSheet.maybeFromJson({
        'className': 'Bard',
        'ancestry': 'Orc',
        'alignment': 'Good',
        'level': 99,
        'abilities': {'str': 99},
        'gearSlotsUsed': -2,
      })!;
      expect(j.className, 'Fighter'); // unknown -> default
      expect(j.ancestry, 'Human');
      expect(j.alignment, 'Neutral');
      expect(j.level, 10); // clamped 1..10
      expect(j.score('str'), 20); // clamped 1..20
      expect(j.gearSlotsUsed, 0);
    });
  });

  group('StarforgedSheet.assetRuleset', () {
    test('defaults to starforged; premade can set sundered_isles', () {
      expect(const StarforgedSheet().assetRuleset, 'starforged');
      expect(StarforgedSheet.premade().assetRuleset, 'starforged');
      expect(StarforgedSheet.premade().isSundered, isFalse);
      final si = StarforgedSheet.premade(assetRuleset: 'sundered_isles');
      expect(si.assetRuleset, 'sundered_isles');
      expect(si.isSundered, isTrue);
    });

    test('round-trips; omitted from toJson when default', () {
      expect(StarforgedSheet.premade().toJson().containsKey('assetRuleset'),
          isFalse);
      final si = StarforgedSheet.premade(assetRuleset: 'sundered_isles');
      expect(si.toJson()['assetRuleset'], 'sundered_isles');
      expect(StarforgedSheet.maybeFromJson(si.toJson())!.assetRuleset,
          'sundered_isles');
    });

    test('legacy JSON and junk values resolve to starforged', () {
      // No key (existing Starforged characters).
      final legacy = StarforgedSheet.maybeFromJson({'edge': 2})!;
      expect(legacy.assetRuleset, 'starforged');
      // Junk / unknown.
      expect(
          StarforgedSheet.maybeFromJson({'assetRuleset': 'bogus'})!
              .assetRuleset,
          'starforged');
      expect(StarforgedSheet.maybeFromJson({'assetRuleset': 42})!.assetRuleset,
          'starforged');
    });

    test('copyWith passes through and sanitizes', () {
      final si =
          const StarforgedSheet().copyWith(assetRuleset: 'sundered_isles');
      expect(si.assetRuleset, 'sundered_isles');
      expect(si.copyWith().assetRuleset, 'sundered_isles');
      expect(si.copyWith(assetRuleset: 'nope').assetRuleset, 'starforged');
    });
  });

  group('StarforgedSheet', () {
    test('premade defaults match the standard starting sheet', () {
      final s = StarforgedSheet.premade();
      expect([s.edge, s.heart, s.iron, s.shadow, s.wits], [3, 2, 2, 1, 1]);
      expect([s.health, s.spirit, s.supply], [5, 5, 5]);
      expect(s.momentum, 2);
      expect(s.momentumMax, 10);
      expect(s.momentumReset, 2);
      expect([s.questsLegacy, s.bondsLegacy, s.discoveriesLegacy], [0, 0, 0]);
    });

    test('impacts lower max + reset and re-clamp momentum via copyWith', () {
      final s = const StarforgedSheet(momentum: 10)
          .copyWith(impacts: {'wounded', 'doomed'});
      expect(s.momentumMax, 8);
      expect(s.momentumReset, 0);
      expect(s.momentum, 8);
    });

    test('values are clamped to legal ranges', () {
      final s = const StarforgedSheet().copyWith(
        edge: 9,
        health: 99,
        supply: -2,
        momentum: 99,
        questsLegacy: 50,
        discoveriesLegacy: -3,
        xpSpent: -1,
      );
      expect(s.edge, 3);
      expect(s.health, 5);
      expect(s.supply, 0);
      expect(s.momentum, 10);
      expect(s.questsLegacy, 10);
      expect(s.discoveriesLegacy, 0);
      expect(s.xpSpent, 0);
    });

    test('round-trips with legacy, impacts, vows, connections, assets', () {
      const s = StarforgedSheet(
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
        questsLegacy: 3,
        bondsLegacy: 1,
        discoveriesLegacy: 2,
        impacts: {'shaken'},
        vows: [
          ProgressTrack(
              name: 'Reach the Forge', rank: ProgressRank.formidable, ticks: 4)
        ],
        connections: [
          ProgressTrack(name: 'Lara', rank: ProgressRank.dangerous, ticks: 8)
        ],
        assets: [
          AssetState(assetId: 'starforged/assets/path/ace', name: 'Ace')
        ],
      );
      final back = StarforgedSheet.maybeFromJson(s.toJson())!;
      expect(back.health, 4);
      expect(back.momentum, -2);
      expect(back.questsLegacy, 3);
      expect(back.impacts, {'shaken'});
      expect(back.vows.single.ticks, 4);
      expect(back.connections.single.name, 'Lara');
      expect(back.assets.single.name, 'Ace');
      expect(back.momentumMax, 9);
    });

    test('tolerates junk and unknown impact ids', () {
      expect(StarforgedSheet.maybeFromJson('x'), isNull);
      final s = StarforgedSheet.maybeFromJson({
        'edge': 'three',
        'momentum': 'fast',
        'impacts': ['wounded', 'bogus', 7],
        'connections': ['junk'],
        'assets': 'nope',
      })!;
      expect(s.edge, 1);
      expect(s.momentum, 2);
      expect(s.impacts, {'wounded'});
      expect(s.connections, isEmpty);
      expect(s.assets, isEmpty);
    });
  });
}
