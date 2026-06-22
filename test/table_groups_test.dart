import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/table_groups.dart';

void main() {
  test('groups by prefix; singletons and no-underscore keys go to General', () {
    final groups = groupTableKeys([
      'quest_objective',
      'quest_location',
      'npc_need',
      'npc_motive',
      'color', // no underscore -> General
      'random_event', // singleton prefix -> General
      'pay_the_price', // singleton prefix -> General
    ]);
    final byLabel = {for (final g in groups) g.label: g.keys};

    expect(byLabel['Quest'], ['quest_location', 'quest_objective']);
    expect(byLabel['NPC'], ['npc_motive', 'npc_need']);
    expect(byLabel['General'],
        containsAll(['color', 'random_event', 'pay_the_price']));
  });

  test('npc prefix gets the NPC label override', () {
    final groups = groupTableKeys(['npc_a', 'npc_b']);
    expect(groups.single.label, 'NPC');
  });

  test('General is pinned last; other groups sorted alphabetically', () {
    final labels = groupTableKeys([
      'wilderness_a', 'wilderness_b', // Wilderness
      'color', // General
      'idea_a', 'idea_b', // Idea
    ]).map((g) => g.label).toList();
    expect(labels, ['Idea', 'Wilderness', 'General']);
  });

  test('every key is placed exactly once (count preserved)', () {
    final input = [
      'quest_a',
      'quest_b',
      'quest_c',
      'npc_x',
      'npc_y',
      'lonely',
      'solo_one',
      'because',
    ];
    final out = groupTableKeys(input).expand((g) => g.keys).toList()..sort();
    expect(out, equals([...input]..sort()));
  });

  test('empty input yields no groups', () {
    expect(groupTableKeys(const []), isEmpty);
  });
}
