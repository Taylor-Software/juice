import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/tool_registry.dart';

void main() {
  test('ids unique, groups ordered, every tool in a known group', () {
    final tools = buildToolRegistry(family: ['classic', 'delve']);
    final ids = tools.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final t in tools) {
      expect(toolGroups, contains(t.group));
    }
  });

  test('moves tool present only when a family is enabled', () {
    expect(buildToolRegistry(family: []).any((t) => t.id == 'moves'), isFalse);
    expect(
        buildToolRegistry(family: ['starforged']).any((t) => t.id == 'moves'),
        isTrue);
  });

  test('expected entry count and core ids', () {
    final tools = buildToolRegistry(family: []);
    expect(tools, hasLength(15));
    expect(buildToolRegistry(family: ['classic']), hasLength(16));
    expect(
        tools.map((t) => t.id),
        containsAll([
          'fate-check',
          'roll-high',
          'mythic',
          'dice',
          'gen-story',
          'gen-npcs',
          'gen-exploration',
          'gen-encounters',
          'gen-details',
          'threads-characters',
          'tables',
          'encounter',
          'maps',
          'party-emulator',
          'behavior-tables',
        ]));
  });

  test('Party group sits after NPCs & Dialog and hosts behavior-tables', () {
    expect(
        toolGroups.indexOf('Party'), toolGroups.indexOf('NPCs & Dialog') + 1);
    final tool = buildToolRegistry(family: [])
        .singleWhere((t) => t.id == 'behavior-tables');
    expect(tool.group, 'Party');
    expect(tool.label, 'Behavior Tables');
    expect(tool.badge, 'Triple-O');
  });

  test('party-emulator sits in Party before behavior-tables', () {
    final tools = buildToolRegistry(family: []);
    final ids = tools.map((t) => t.id).toList();
    expect(ids.indexOf('party-emulator'),
        lessThan(ids.indexOf('behavior-tables')));
    final tool = tools.singleWhere((t) => t.id == 'party-emulator');
    expect(tool.group, 'Party');
    expect(tool.label, 'Party Emulator');
    expect(tool.badge, 'Triple-O');
  });
}
