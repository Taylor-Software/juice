import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/campaign_presets.dart';
import 'package:juice_oracle/engine/funnel.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/shared/home_shell.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('FunnelPeasant', () {
    test('defaults: alive, not graduated, empty maps', () {
      const p = FunnelPeasant();
      expect(p.alive, true);
      expect(p.graduated, false);
      expect(p.hp, 0);
      expect(p.stats, isEmpty);
      expect(p.flavor, isEmpty);
    });
    test('copyWith replaces fields', () {
      const p = FunnelPeasant();
      final p2 = p.copyWith(
          name: 'Bob',
          hp: 4,
          alive: false,
          graduated: true,
          stats: {'str': 12},
          flavor: {'occupation': 'Farmer'});
      expect(p2.name, 'Bob');
      expect(p2.hp, 4);
      expect(p2.alive, false);
      expect(p2.graduated, true);
      expect(p2.stats['str'], 12);
      expect(p2.flavor['occupation'], 'Farmer');
    });
    test('round-trips through json', () {
      const p = FunnelPeasant(
          name: 'Ada', hp: 3, stats: {'str': 9}, flavor: {'weapon': 'Sling'});
      final back = FunnelPeasant.fromJson(p.toJson());
      expect(back.name, 'Ada');
      expect(back.hp, 3);
      expect(back.stats['str'], 9);
      expect(back.flavor['weapon'], 'Sling');
      expect(back.alive, true);
      expect(back.graduated, false);
    });
    test('fromJson tolerates missing fields', () {
      final p = FunnelPeasant.fromJson(const {});
      expect(p.name, '');
      expect(p.hp, 0);
      expect(p.stats, isEmpty);
    });
  });

  group('FunnelSheet', () {
    test('premade has the seed system + one empty peasant', () {
      final s = FunnelSheet.premade('dcc', const [FunnelPeasant(hp: 1)]);
      expect(s.seedSystem, 'dcc');
      expect(s.peasants.length, 1);
      expect(s.peasants.first.hp, 1);
    });
    test('markGraduated flips one peasant', () {
      const s = FunnelSheet(seedSystem: 'dcc', peasants: [
        FunnelPeasant(name: 'A'),
        FunnelPeasant(name: 'B'),
      ]);
      final s2 = s.markGraduated(1);
      expect(s2.peasants[0].graduated, false);
      expect(s2.peasants[1].graduated, true);
    });
    test('round-trips through json', () {
      const s = FunnelSheet(seedSystem: 'ose', peasants: [
        FunnelPeasant(name: 'A', hp: 4, stats: {'str': 12}),
      ]);
      final back = FunnelSheet.maybeFromJson(s.toJson())!;
      expect(back.seedSystem, 'ose');
      expect(back.peasants.single.name, 'A');
      expect(back.peasants.single.stats['str'], 12);
    });
    test('maybeFromJson returns null for non-map', () {
      expect(FunnelSheet.maybeFromJson(null), isNull);
      expect(FunnelSheet.maybeFromJson('x'), isNull);
    });
    test(
        'maybeFromJson defaults a missing seedSystem to empty + tolerates no peasants',
        () {
      final s = FunnelSheet.maybeFromJson(const {})!;
      expect(s.seedSystem, '');
      expect(s.peasants, isEmpty);
    });
    test('seedVariant round-trips and defaults empty', () {
      const s = FunnelSheet(
          seedSystem: 'custom', seedVariant: 'generic-d20', peasants: []);
      final back = FunnelSheet.maybeFromJson(s.toJson())!;
      expect(back.seedVariant, 'generic-d20');
      expect(FunnelSheet.maybeFromJson(const {})!.seedVariant, '');
      expect(s.copyWith(seedVariant: 'osr').seedVariant, 'osr');
    });
  });

  group('FunnelProfile registry', () {
    test('funnelProfileFor returns null for unknown', () {
      expect(funnelProfileFor('nope'), isNull);
    });
    test('dcc profile shape', () {
      final p = funnelProfileFor('dcc')!;
      expect(p.system, 'dcc');
      expect(p.statKeys.map((s) => s.key),
          containsAll(['str', 'agi', 'sta', 'per', 'int', 'lck']));
      expect(p.flavorFields.map((f) => f.key),
          containsAll(['occupation', 'weapon', 'tradeGoods']));
      expect(p.graduateChoices.map((c) => c.key),
          containsAll(['className', 'alignment']));
    });
    test('dcc seedPeasant has mid-range stats + hpMin hp', () {
      final p = funnelProfileFor('dcc')!;
      final peasant = p.seedPeasant('');
      expect(peasant.stats['str'], p.statDefault);
      expect(peasant.hp, p.hpMin);
      expect(peasant.alive, true);
    });
    test('dcc graduate builds a leveled DCC hero copying stats + hp', () {
      final p = funnelProfileFor('dcc')!;
      const peasant = FunnelPeasant(
        name: 'Survivor',
        hp: 5,
        stats: {'str': 16, 'agi': 12, 'sta': 14, 'per': 9, 'int': 8, 'lck': 11},
        flavor: {'occupation': 'Blacksmith'},
      );
      final hero = p.graduate(
          'h1', peasant, {'className': 'Warrior', 'alignment': 'Lawful'}, '');
      expect(hero.id, 'h1');
      expect(hero.name, 'Survivor');
      expect(hero.dcc, isNotNull);
      expect(hero.dcc!.className, 'Warrior');
      expect(hero.dcc!.alignment, 'Lawful');
      expect(hero.dcc!.stats['str'], 16);
      expect(hero.dcc!.stats['lck'], 11);
      expect(hero.dcc!.lckMax, 11);
      expect(hero.dcc!.currentHp, 5);
      expect(hero.dcc!.maxHp, 5);
      expect(hero.dcc!.occupation, 'Blacksmith');
    });
  });

  group('Character funnel wiring', () {
    test('round-trips a funnel character through json', () {
      const c = Character(
        id: 'f1',
        name: 'Funnel',
        funnel: FunnelSheet(seedSystem: 'dcc', peasants: [
          FunnelPeasant(name: 'A', hp: 3, stats: {'str': 12}),
        ]),
      );
      final back = Character.fromJson(c.toJson());
      expect(back.funnel, isNotNull);
      expect(back.funnel!.seedSystem, 'dcc');
      expect(back.funnel!.peasants.single.name, 'A');
    });
    test('clearFunnel drops the sheet', () {
      const c = Character(
          id: 'f1', name: 'F', funnel: FunnelSheet(seedSystem: 'dcc'));
      expect(c.copyWith(clearFunnel: true).funnel, isNull);
    });
    test('withHpDelta leaves a funnel character unchanged', () {
      const c = Character(
          id: 'f1', name: 'F', funnel: FunnelSheet(seedSystem: 'dcc'));
      expect(identical(c.withHpDelta(-5), c), true);
    });
  });

  group('funnel system registration', () {
    test('funnel is a known tools system', () {
      expect(kKnownSystems, contains('funnel'));
      expect(kSystemCategory['funnel'], SystemCategory.tools);
    });
    test('blurb exists', () {
      expect(kSystemBlurbs['funnel'], isNotNull);
    });
    test('every known system has a short name (no creation-chip drift)', () {
      for (final sys in kKnownSystems) {
        expect(kSystemShortName[sys], isNotNull,
            reason: 'kSystemShortName missing "$sys"');
      }
    });
    test('solo-dcc preset includes funnel', () {
      final p = kCampaignPresets.firstWhere((x) => x.id == 'solo-dcc');
      expect(p.systems, contains('funnel'));
    });
    test('solo-funnel preset resolves', () {
      final p = kCampaignPresets.firstWhere((x) => x.id == 'solo-funnel');
      final systems = presetConfig(p);
      expect(systems, contains('funnel'));
    });
  });

  group('profiles: map-stat hp systems', () {
    const peasant = FunnelPeasant(
      name: 'Hero',
      hp: 7,
      stats: {'str': 15, 'dex': 13, 'con': 14, 'int': 8, 'wis': 9, 'cha': 11},
    );
    test('dnd', () {
      final h = funnelProfileFor('dnd')!
          .graduate('h', peasant, {'className': 'Wizard'}, '');
      expect(h.dnd, isNotNull);
      expect(h.dnd!.abilities['str'], 15);
      expect(h.dnd!.currentHp, 7);
      expect(h.dnd!.maxHp, 7);
      expect(h.dnd!.className, 'Wizard');
      expect(h.name, 'Hero');
    });
    test('shadowdark', () {
      final h = funnelProfileFor('shadowdark')!.graduate(
          'h',
          peasant,
          {'className': 'Wizard', 'ancestry': 'Human', 'alignment': 'Neutral'},
          '');
      expect(h.shadowdark!.abilities['str'], 15);
      expect(h.shadowdark!.currentHp, 7);
      expect(h.shadowdark!.maxHp, 7);
      expect(h.shadowdark!.className, 'Wizard');
      expect(h.shadowdark!.ancestry, 'Human'); // ancestry pick lands
      expect(h.shadowdark!.alignment, 'Neutral'); // alignment pick lands
    });
    test('argosa', () {
      final cls =
          funnelProfileFor('argosa')!.graduateChoices.first.options.first;
      final h = funnelProfileFor('argosa')!
          .graduate('h', peasant, {'className': cls}, '');
      expect(h.argosa!.stats['str'], 15);
      expect(h.argosa!.currentHp, 7);
      expect(h.argosa!.maxHp, 7);
      expect(h.argosa!.className, cls); // class pick lands
    });
    test('ose', () {
      final h = funnelProfileFor('ose')!.graduate(
          'h', peasant, {'className': 'Fighter', 'alignment': 'Lawful'}, '');
      expect(h.ose!.stats['str'], 15);
      expect(h.ose!.currentHp, 7);
      expect(h.ose!.maxHp, 7);
      expect(h.ose!.className, 'Fighter');
      expect(h.ose!.alignment, 'Lawful'); // alignment pick lands
    });
  });

  group('profiles: modifier-stat systems', () {
    test('nimble', () {
      const peasant = FunnelPeasant(
          hp: 12, stats: {'str': 2, 'dex': 1, 'int': 0, 'wis': -1});
      final h = funnelProfileFor('nimble')!
          .graduate('h', peasant, {'className': kNimbleClasses.first}, '');
      expect(h.nimble!.stats['str'], 2);
      expect(h.nimble!.currentHp, 12);
      expect(h.nimble!.maxHp, 12);
      expect(h.nimble!.className, kNimbleClasses.first);
      expect(funnelProfileFor('nimble')!.statDefault, 0);
    });
    test('draw-steel maps stamina', () {
      const peasant = FunnelPeasant(hp: 20, stats: {
        'might': 2,
        'agility': 1,
        'reason': 0,
        'intuition': 0,
        'presence': -1
      });
      final h = funnelProfileFor('draw-steel')!
          .graduate('h', peasant, {'className': kDrawSteelClasses.first}, '');
      expect(h.drawSteel!.characteristics['might'], 2);
      expect(h.drawSteel!.currentStamina, 20);
      expect(h.drawSteel!.maxStamina, 20);
      expect(h.drawSteel!.className, kDrawSteelClasses.first);
    });
    test('knave has no class choice', () {
      expect(funnelProfileFor('knave')!.graduateChoices, isEmpty);
      const peasant = FunnelPeasant(hp: 6, stats: {'str': 3, 'dex': 2});
      final h = funnelProfileFor('knave')!.graduate('h', peasant, const {}, '');
      expect(h.knave!.stats['str'], 3);
      expect(h.knave!.currentHp, 6);
      expect(h.knave!.maxHp, 6);
    });
    test('kal-arath', () {
      const peasant = FunnelPeasant(
          hp: 8, stats: {'str': 3, 'tou': 2, 'agi': 1, 'int': 0, 'pre': -1});
      final h = funnelProfileFor('kal-arath')!.graduate(
          'h',
          peasant,
          {
            'archetype': kKalArathArchetypes.first,
            'pact': kKalArathPacts.first
          },
          '');
      expect(h.kalArath!.stats['str'], 3);
      expect(h.kalArath!.currentHp, 8);
      expect(h.kalArath!.maxHp, 8);
      expect(h.kalArath!.archetype, kKalArathArchetypes.first);
      expect(h.kalArath!.pact, kKalArathPacts.first);
    });
  });

  group('profiles: individual-field + meter systems', () {
    test('cairn maps individual stats + hp + background', () {
      const peasant =
          FunnelPeasant(hp: 5, stats: {'str': 12, 'dex': 9, 'wil': 14});
      final h = funnelProfileFor('cairn')!
          .graduate('h', peasant, {'background': kCairnBackgrounds.first}, '');
      expect(h.cairn!.str, 12);
      expect(h.cairn!.dex, 9);
      expect(h.cairn!.wil, 14);
      expect(h.cairn!.currentHp, 5);
      expect(h.cairn!.maxHp, 5);
      expect(h.cairn!.background, kCairnBackgrounds.first);
    });
    test(
        'ironsworn maps individual stats via variant choice, ignores hp (no pool)',
        () {
      const peasant = FunnelPeasant(
          hp: 4,
          stats: {'edge': 2, 'heart': 1, 'iron': 3, 'shadow': 1, 'wits': 2});
      final h = funnelProfileFor('ironsworn')!
          .graduate('h', peasant, {'variant': 'ironsworn'}, '');
      expect(h.ironsworn!.edge, 2);
      expect(h.ironsworn!.iron, 3);
    });
  });

  group('ironsworn family graduation', () {
    const peasant = FunnelPeasant(
        hp: 3,
        stats: {'edge': 2, 'heart': 1, 'iron': 3, 'shadow': 1, 'wits': 2});
    test('ironsworn profile offers a variant choice', () {
      final p = funnelProfileFor('ironsworn')!;
      final variant = p.graduateChoices.firstWhere((c) => c.key == 'variant');
      expect(variant.options, ['ironsworn', 'starforged', 'sundered_isles']);
    });
    test('graduate builds classic Ironsworn for variant ironsworn', () {
      final h = funnelProfileFor('ironsworn')!
          .graduate('h', peasant, {'variant': 'ironsworn'}, '');
      expect(h.ironsworn, isNotNull);
      expect(h.starforged, isNull);
      expect(h.ironsworn!.iron, 3);
    });
    test('graduate builds Starforged for variant starforged', () {
      final h = funnelProfileFor('ironsworn')!
          .graduate('h', peasant, {'variant': 'starforged'}, '');
      expect(h.starforged, isNotNull);
      expect(h.ironsworn, isNull);
      expect(h.starforged!.isSundered, false);
      expect(h.starforged!.shadow, 1);
    });
    test('graduate builds Sundered Isles for variant sundered_isles', () {
      final h = funnelProfileFor('ironsworn')!
          .graduate('h', peasant, {'variant': 'sundered_isles'}, '');
      expect(h.starforged, isNotNull);
      expect(h.starforged!.isSundered, true);
    });
    test('no standalone starforged/sundered_isles profile', () {
      expect(kFunnelProfiles.containsKey('starforged'), false);
      expect(kFunnelProfiles.containsKey('sundered_isles'), false);
    });
  });

  group('CharacterNotifier funnel', () {
    setUp(() => SharedPreferences.setMockInitialValues({
          'juice.sessions.v1':
              '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
        }));

    test('addFunnel creates a funnel seeded from the system profile', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final id = await c.read(charactersProvider.notifier).addFunnel('dcc');
      final list = await c.read(charactersProvider.future);
      final f = list.firstWhere((x) => x.id == id);
      expect(f.funnel, isNotNull);
      expect(f.funnel!.seedSystem, 'dcc');
      expect(f.funnel!.peasants.length, 1);
      expect(f.funnel!.peasants.first.stats['str'], 10); // dcc statDefault
    });

    test('addFunnel custom seeds from the template variant', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final id = await c
          .read(charactersProvider.notifier)
          .addFunnel('custom', seedVariant: 'osr');
      final f = (await c.read(charactersProvider.future))
          .firstWhere((x) => x.id == id);
      expect(f.funnel!.seedSystem, 'custom');
      expect(f.funnel!.seedVariant, 'osr');
      expect(f.funnel!.peasants.first.stats.keys,
          containsAll(['str', 'dex', 'wil']));
    });

    test('graduateFunnelPeasant spawns a hero + marks the peasant graduated',
        () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(charactersProvider.notifier);
      final fid = await notifier.addFunnel('dcc');
      final funnelChar = (await c.read(charactersProvider.future))
          .firstWhere((x) => x.id == fid);
      final seeded = funnelChar.copyWith(
          funnel: funnelChar.funnel!.copyWith(peasants: [
        funnelChar.funnel!.peasants.first.copyWith(
            name: 'Reaper',
            hp: 6,
            stats: {...funnelChar.funnel!.peasants.first.stats, 'str': 15}),
      ]));
      await notifier.replace(seeded);
      final profile = funnelProfileFor('dcc')!;
      final heroId = await notifier.graduateFunnelPeasant(
          seeded,
          0,
          (id) => profile.graduate(id, seeded.funnel!.peasants[0],
              {'className': 'Warrior', 'alignment': 'Lawful'}, ''));
      final list = await c.read(charactersProvider.future);
      final hero = list.firstWhere((x) => x.id == heroId);
      expect(hero.dcc, isNotNull);
      expect(hero.dcc!.stats['str'], 15);
      expect(hero.name, 'Reaper');
      final funnel = list.firstWhere((x) => x.id == fid);
      expect(funnel.funnel!.peasants[0].graduated, true);
    });
  });

  group('funnelPeasantSchema', () {
    test('non-custom returns the profile fixed schema', () {
      final sc = funnelPeasantSchema('dcc', '');
      final p = funnelProfileFor('dcc')!;
      expect(sc.statKeys.map((s) => s.key), p.statKeys.map((s) => s.key));
      expect(sc.statMin, p.statMin);
      expect(sc.statMax, p.statMax);
      expect(sc.hpMin, p.hpMin);
      expect(sc.hpMax, p.hpMax);
    });
    test('custom derives stat keys from the chosen template', () {
      final g = funnelPeasantSchema('custom', 'generic-d20');
      expect(g.statKeys.map((s) => s.key),
          ['str', 'dex', 'con', 'int', 'wis', 'cha']);
      expect(g.statMin, 3);
      expect(g.statMax, 18);

      final osr = funnelPeasantSchema('custom', 'osr');
      expect(osr.statKeys.map((s) => s.key), ['str', 'dex', 'wil']);

      final pbta = funnelPeasantSchema('custom', 'pbta');
      expect(pbta.statKeys.length, 5);
      expect(pbta.statMin, -1);
      expect(pbta.statMax, 3);

      final blank = funnelPeasantSchema('custom', 'blank');
      expect(blank.statKeys, isEmpty);
      expect(blank.hpMin >= 1, true);
    });
  });

  group('profile registry completeness', () {
    test('every kSystemCategory ruleset has a profile', () {
      final rulesets = kSystemCategory.entries
          .where((e) => e.value == SystemCategory.ruleset)
          .map((e) => e.key)
          .toSet();
      for (final sys in rulesets) {
        expect(kFunnelProfiles.containsKey(sys), true,
            reason: 'missing FunnelProfile for ruleset "$sys"');
      }
    });
    test('every profile is well-formed', () {
      kFunnelProfiles.forEach((sys, p) {
        expect(p.system, sys);
        expect(p.statMin < p.statMax, true, reason: '$sys range');
        expect(p.statDefault >= p.statMin && p.statDefault <= p.statMax, true,
            reason: '$sys default in range');
        expect(p.hpMin <= p.hpMax, true, reason: '$sys hp range');
        for (final c in p.graduateChoices) {
          expect(c.options, isNotEmpty, reason: '$sys choice ${c.key}');
        }
        if (sys == 'custom') {
          expect(funnelPeasantSchema('custom', 'generic-d20').statKeys,
              isNotEmpty);
        } else {
          expect(p.statKeys, isNotEmpty, reason: '$sys statKeys');
        }
        final variant = sys == 'custom' ? 'generic-d20' : '';
        final peasant = p.seedPeasant(variant).copyWith(name: 'X');
        final hero = p.graduate('hid', peasant, p.defaultPicks(), variant);
        expect(hero.id, 'hid');
        expect(hero.name, 'X');
      });
    });
  });

  group('custom funnel profile', () {
    test('custom profile exists with no graduate choices', () {
      final p = funnelProfileFor('custom');
      expect(p, isNotNull);
      expect(p!.graduateChoices, isEmpty);
    });
    test('custom seedPeasant uses the template schema', () {
      final p = funnelProfileFor('custom')!;
      final peasant = p.seedPeasant('osr');
      expect(peasant.stats.keys, containsAll(['str', 'dex', 'wil']));
    });
    test('graduate builds the template blocks + injects stats and hp', () {
      const peasant = FunnelPeasant(name: 'Reaper', hp: 6, stats: {
        'str': 15,
        'dex': 13,
        'con': 14,
        'int': 8,
        'wis': 9,
        'cha': 11
      });
      final h = funnelProfileFor('custom')!
          .graduate('h', peasant, const {}, 'generic-d20');
      expect(h.custom, isNotNull);
      expect(h.name, 'Reaper');
      expect(h.custom!.blocks.any((b) => b.id == 'g-stat'), true);
      expect((h.custom!.values['g-stat'] as Map)['str'], 15);
      expect(h.custom!.values['g-hp'], 6);
    });
    test('graduate into blank template yields an empty custom sheet', () {
      const peasant = FunnelPeasant(name: 'Nobody', hp: 4);
      final h =
          funnelProfileFor('custom')!.graduate('h', peasant, const {}, 'blank');
      expect(h.custom, isNotNull);
      expect(h.custom!.blocks, isEmpty);
      expect(h.name, 'Nobody');
    });
  });
}
