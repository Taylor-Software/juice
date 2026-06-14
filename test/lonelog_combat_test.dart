import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/lonelog_combat.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('renders a [COMBAT] block with foe tags and the outcome', () {
    const s = EncounterState(round: 3, combatants: [
      Combatant(
          id: '1',
          name: 'Goblin A',
          initiative: 12,
          track: CharTrack(label: 'HP', current: 0, max: 6),
          tags: ['prone'],
          defeated: true),
      Combatant(
          id: '2',
          name: 'Hero',
          initiative: 15,
          track: CharTrack(label: 'HP', current: 5, max: 10)),
    ]);
    final out = encounterToLonelog(s);
    expect(out, startsWith('[COMBAT]'));
    expect(out, contains('Rd3 Roster:'));
    expect(out, contains('[F:Goblin A|HP 0/6, prone, defeated]'));
    expect(out, contains('[F:Hero|HP 5/10]'));
    expect(out, contains('=> defeated: Goblin A'));
    expect(out, endsWith('[/COMBAT]'));
  });

  test('no defeated -> outcome says so; a bare combatant has no fields', () {
    const s = EncounterState(round: 1, combatants: [
      Combatant(id: '1', name: 'Rat', initiative: 5),
    ]);
    final out = encounterToLonelog(s);
    expect(out, contains('[F:Rat]'));
    expect(out, contains('=> no combatants defeated'));
  });

  test('sanitizes delimiter chars in combatant names', () {
    const s = EncounterState(combatants: [
      Combatant(id: '1', name: 'A|B]C', initiative: 1),
    ]);
    expect(encounterToLonelog(s), contains('[F:A/B)C]'));
  });
}
