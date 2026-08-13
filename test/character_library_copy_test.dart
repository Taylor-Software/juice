import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/character_library.dart';
import 'package:loreseer/engine/models.dart';

void main() {
  final src = Character(
    id: 'orig',
    name: 'Brakka',
    note: 'scarred',
    stats: const [CharStat(label: 'STR', value: '14')],
    starred: true,
    role: CharacterRole.companion,
    conditions: const ['poisoned'],
    coins: 7,
    polarityId: 'pg-1',
    dnd: DndSheet.premade(),
  );

  test('libraryCopy: fresh id, polarityId dropped, rest preserved', () {
    final copy = libraryCopy(src, 'lib-1');
    expect(copy.id, 'lib-1');
    expect(copy.polarityId, isNull);
    expect(copy.name, 'Brakka');
    expect(copy.note, 'scarred');
    expect(copy.stats.single.label, 'STR');
    expect(copy.dnd, isNotNull);
    expect(copy.starred, isTrue); // library keeps flags as captured
    expect(copy.role, CharacterRole.companion);
    expect(copy.conditions, ['poisoned']);
    expect(copy.coins, 7);
    // Source untouched.
    expect(src.id, 'orig');
    expect(src.polarityId, 'pg-1');
  });

  test('campaignCopy: also resets role to pc and clears starred', () {
    final copy = campaignCopy(src, 'camp-1');
    expect(copy.id, 'camp-1');
    expect(copy.polarityId, isNull);
    expect(copy.role, CharacterRole.pc);
    expect(copy.starred, isFalse);
    expect(copy.conditions, ['poisoned']); // play state comes along
    expect(copy.dnd, isNotNull);
  });
}
