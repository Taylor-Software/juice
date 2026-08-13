import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/character_library.dart';
import 'package:loreseer/engine/models.dart';

void main() {
  Character bare({
    DndSheet? dnd,
    IronswornSheet? ironsworn,
    StarforgedSheet? starforged,
    FunnelSheet? funnel,
  }) =>
      Character(
        id: 'x',
        name: 'X',
        dnd: dnd,
        ironsworn: ironsworn,
        starforged: starforged,
        funnel: funnel,
      );

  test('sheetLabel: generic when no sheet field is set', () {
    expect(sheetLabel(bare()), 'Generic');
  });

  test('sheetLabel: dnd', () {
    expect(sheetLabel(bare(dnd: DndSheet.premade())), 'D&D 5e');
  });

  test('sheetLabel: ironsworn', () {
    expect(sheetLabel(bare(ironsworn: IronswornSheet.premade())), 'Ironsworn');
  });

  test('sheetLabel: starforged (also backs Sundered Isles)', () {
    expect(
        sheetLabel(bare(starforged: StarforgedSheet.premade())), 'Starforged');
  });

  test('sheetLabel: 0-level funnel', () {
    expect(sheetLabel(bare(funnel: const FunnelSheet(peasants: []))),
        '0-Level Funnel');
  });
}
