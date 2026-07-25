import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/custom_sheet.dart';
import 'package:juice_oracle/engine/models.dart';

/// Character carries one nullable field per sheet system, and each one has to
/// be threaded through the constructor, copyWith, toJson, fromJson, and (when
/// it has a pool) the HP contract. The compiler cannot tell you when you miss
/// one — and a forgotten `toJson` branch silently drops a player's whole sheet
/// on export, which is the worst failure this app has.
///
/// These tests are that missing check. Adding a 17th sheet system means adding
/// it to [_slots] and watching this file fail until it is wired end to end.
void main() {
  // Every sheet slot: its JSON key, a Character carrying only that sheet, and
  // whether that sheet is expected to carry an HP pool.
  final slots = <({String key, Character sample, bool hasHp})>[
    (
      key: 'ironsworn',
      sample:
          Character(id: 'c', name: 'n', ironsworn: IronswornSheet.premade()),
      hasHp: false
    ),
    (
      key: 'starforged',
      sample:
          Character(id: 'c', name: 'n', starforged: StarforgedSheet.premade()),
      hasHp: false
    ),
    (
      key: 'dnd',
      sample: Character(id: 'c', name: 'n', dnd: DndSheet.premade()),
      hasHp: true
    ),
    (
      key: 'shadowdark',
      sample:
          Character(id: 'c', name: 'n', shadowdark: ShadowdarkSheet.premade()),
      hasHp: true
    ),
    (
      key: 'nimble',
      sample: const Character(id: 'c', name: 'n', nimble: NimbleSheet()),
      hasHp: true
    ),
    (
      key: 'drawSteel',
      sample: const Character(id: 'c', name: 'n', drawSteel: DrawSteelSheet()),
      hasHp: true
    ),
    (
      key: 'argosa',
      sample: const Character(id: 'c', name: 'n', argosa: ArgosaSheet()),
      hasHp: true
    ),
    (
      key: 'cairn',
      sample: const Character(id: 'c', name: 'n', cairn: CairnSheet()),
      hasHp: true
    ),
    (
      key: 'knave',
      sample: const Character(id: 'c', name: 'n', knave: KnaveSheet()),
      hasHp: true
    ),
    (
      key: 'embark',
      sample: const Character(id: 'c', name: 'n', embark: EmbarkSheet()),
      hasHp: true
    ),
    (
      key: 'ose',
      sample: const Character(id: 'c', name: 'n', ose: OseSheet()),
      hasHp: true
    ),
    (
      key: 'kalArath',
      sample: const Character(id: 'c', name: 'n', kalArath: KalArathSheet()),
      hasHp: true
    ),
    (
      key: 'dcc',
      sample: const Character(id: 'c', name: 'n', dcc: DccSheet()),
      hasHp: true
    ),
    (
      key: 'custom',
      sample: const Character(id: 'c', name: 'n', custom: CustomSheet()),
      hasHp: false
    ),
    (
      key: 'funnel',
      sample: const Character(id: 'c', name: 'n', funnel: FunnelSheet()),
      hasHp: false
    ),
  ];

  group('every sheet slot survives a JSON round-trip', () {
    for (final slot in slots) {
      test('${slot.key} is written and read back', () {
        final json = slot.sample.toJson();
        expect(json.containsKey(slot.key), isTrue,
            reason: '${slot.key} is missing from Character.toJson — this '
                'sheet would be silently dropped on campaign export');

        final back = Character.fromJson(json);
        expect(back.toJson()[slot.key], isNotNull,
            reason: '${slot.key} is missing from Character.fromJson — this '
                'sheet would be silently dropped on campaign import');
        // Round-trip is stable, not merely non-null.
        expect(back.toJson(), equals(json));
      });
    }

    test('the slot list matches what toJson actually emits', () {
      // Union of every sheet key any sample produces, minus the always-present
      // scalar fields. If a new sheet field is added to Character and wired
      // into toJson but NOT added to `slots`, this catches it.
      final emitted = <String>{};
      for (final slot in slots) {
        emitted.addAll(slot.sample.toJson().keys);
      }
      const alwaysPresent = {'id', 'name', 'note', 'stats', 'tracks', 'tags'};
      expect(emitted.difference(alwaysPresent),
          equals(slots.map((s) => s.key).toSet()));
    });
  });

  group('the HP contract covers exactly the pooled sheets', () {
    for (final slot in slots) {
      test('${slot.key} ${slot.hasHp ? "has a pool" : "has no pool"}', () {
        expect(slot.sample.hpSheet != null, slot.hasHp);
        expect(characterHpPool(slot.sample) != null, slot.hasHp);
      });
    }

    test('damage applies to whichever pooled sheet is present', () {
      for (final slot in slots.where((s) => s.hasHp)) {
        final full = characterHpPool(slot.sample)!;
        final hurt = slot.sample.withHpDelta(-1);
        final after = characterHpPool(hurt)!;
        expect(after.$1, full.$1 - 1,
            reason: '${slot.key}: withHpDelta did not reach its pool');
        expect(after.$2, full.$2, reason: '${slot.key}: max should not move');
      }
    });

    test('damage clamps at zero rather than going negative', () {
      for (final slot in slots.where((s) => s.hasHp)) {
        final dead = slot.sample.withHpDelta(-9999);
        expect(characterHpPool(dead)!.$1, 0, reason: slot.key);
      }
    });

    test('healing clamps at max', () {
      for (final slot in slots.where((s) => s.hasHp)) {
        final maxHp = characterHpPool(slot.sample)!.$2;
        final healed = slot.sample.withHpDelta(9999);
        expect(characterHpPool(healed)!.$1, maxHp, reason: slot.key);
      }
    });

    test('a pool-less sheet falls back to the first generic track', () {
      const c = Character(
        id: 'c',
        name: 'n',
        ironsworn: null,
        tracks: [CharTrack(label: 'Health', current: 4, max: 5)],
      );
      expect(characterHpPool(c), (4, 5));
      expect(characterHpPool(c.withHpDelta(-1)), (3, 5));
    });
  });
}
