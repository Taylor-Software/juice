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
    expect(
        buildToolRegistry(family: []).any((t) => t.id == 'moves'), isFalse);
    expect(buildToolRegistry(family: ['starforged']).any((t) => t.id == 'moves'),
        isTrue);
  });

  test('expected entry count and core ids', () {
    final tools = buildToolRegistry(family: []);
    expect(tools, hasLength(13));
    expect(buildToolRegistry(family: ['classic']), hasLength(14));
    expect(tools.map((t) => t.id), containsAll([
      'fate-check', 'roll-high', 'mythic', 'dice',
      'gen-story', 'gen-npcs', 'gen-exploration', 'gen-encounters',
      'gen-details', 'threads-characters', 'tables', 'encounter', 'maps',
    ]));
  });
}
