import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/quick_ref.dart';
import 'package:juice_oracle/engine/system_primer.dart';
import 'package:juice_oracle/shared/home_shell.dart';

void main() {
  test('EmbarkSheet round-trips toJson/maybeFromJson', () {
    const s = EmbarkSheet(
      className: 'Mage',
      stats: {'str': -1, 'dex': 2, 'wil': 4, 'int': 3},
      level: 3,
      maxHp: 8,
      currentHp: 5,
      injuries: 1,
      av: 2,
      resource: 2,
      resourceMax: 4,
      sp: '125',
      skills: 'Arcana',
      languages: 'Common, Sky Speech',
      notes: 'n',
    );
    final back = EmbarkSheet.maybeFromJson(s.toJson())!;
    expect(back.className, 'Mage');
    expect(back.stats['str'], -1);
    expect(back.stats['wil'], 4);
    expect(back.currentHp, 5);
    expect(back.injuries, 1);
    expect(back.av, 2);
    expect(back.resource, 2);
    expect(back.resourceMax, 4);
    expect(back.sp, '125');
    expect(back.skills, 'Arcana');
    expect(EmbarkSheet.maybeFromJson('nope'), isNull);
  });

  test('EmbarkSheet copyWith clamps stats, hp, injuries, av, level, resource',
      () {
    const s = EmbarkSheet(maxHp: 6, currentHp: 3, resourceMax: 2, resource: 2);
    expect(s.copyWith(stats: {...s.stats, 'str': 9}).stats['str'], 4);
    expect(s.copyWith(stats: {...s.stats, 'str': -5}).stats['str'], -1);
    expect(s.copyWith(currentHp: 99).currentHp, 6);
    expect(s.copyWith(currentHp: -1).currentHp, 0);
    expect(s.copyWith(injuries: 9).injuries, 3);
    expect(s.copyWith(av: 9).av, 4);
    expect(s.copyWith(level: 0).level, 1);
    expect(s.copyWith(level: 99).level, 6);
    // resource is clamped to resourceMax
    expect(s.copyWith(resource: 9).resource, 2);
    expect(s.copyWith(resourceMax: 0).resource, 0);
  });

  test('kEmbarkStats has the 4 attributes; classes has 6', () {
    expect(kEmbarkStats, ['str', 'dex', 'wil', 'int']);
    expect(kEmbarkClasses.length, 6);
    expect(kEmbarkClasses.contains('Warrior'), isTrue);
    expect(kEmbarkClasses.contains('Barbarian'), isTrue);
  });

  test('embarkResourceLabel maps class to its pool name', () {
    expect(embarkResourceLabel('Warrior'), 'Grit');
    expect(embarkResourceLabel('Mage'), 'Spell Dice');
    expect(embarkResourceLabel('Invoker'), 'Spell Dice');
    expect(embarkResourceLabel('Bard'), 'Flair');
    expect(embarkResourceLabel('Scout'), 'Resource');
    expect(embarkResourceLabel('Barbarian'), 'Resource');
  });

  test('Character round-trips embark + withHpDelta + characterHpPool', () {
    const c = Character(
      id: 'c1',
      name: 'Ash',
      embark: EmbarkSheet(maxHp: 6, currentHp: 6),
    );
    final back = Character.fromJson(c.toJson());
    expect(back.embark, isNotNull);
    expect(c.withHpDelta(-4).embark!.currentHp, 2);
    expect(c.withHpDelta(99).embark!.currentHp, 6);
    expect(c.withHpDelta(-99).embark!.currentHp, 0);
    expect(characterHpPool(c), (6, 6));
  });

  test('Character.forSheet embark seeds an EmbarkSheet', () {
    final c = Character.forSheet('embark', 'x1');
    expect(c.embark, isNotNull);
    expect(c.embark!.className, 'Warrior');
  });

  test('embark is a known opt-in ruleset, NOT in kAllSystems', () {
    expect(kKnownSystems.contains('embark'), isTrue);
    expect(kSystemCategory['embark'], SystemCategory.ruleset);
    expect(kAllSystems.contains('embark'), isFalse);
  });

  test('kSystemBlurbs embark carries CC BY-SA attribution', () {
    final blurb = kSystemBlurbs['embark'] ?? '';
    expect(blurb.toLowerCase(), contains('infinite fractal'));
    expect(blurb.toLowerCase(), contains('cc by-sa'));
  });

  test('embark resolves system + primer + quick ref', () {
    expect(resolveSystem({'embark'}, {}), 'embark');
    expect(resolveSystemPrimer({'embark'}, {}), contains('d12'));
    expect(kSystemQuickRefs['embark'], isNotNull);
    expect(resolveSystemQuickRef({'embark'}, {})!.system, 'embark');
  });
}
