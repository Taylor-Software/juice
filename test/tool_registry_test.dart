import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
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
    expect(tools, hasLength(13));
    expect(buildToolRegistry(family: ['classic']), hasLength(14));
    expect(
        tools.map((t) => t.id),
        containsAll([
          'fate-check',
          'roll-high',
          'mythic',
          'dice',
          'threads-characters',
          'tables',
          'encounter',
          'maps',
          'verdant',
          'party-emulator',
          'sidekick-dialogue',
          'behavior-tables',
          'help',
        ]));
  });

  test('Help group is last and hosts the help tool', () {
    expect(toolGroups.last, 'Help');
    final tool =
        buildToolRegistry(family: []).singleWhere((t) => t.id == 'help');
    expect(tool.group, 'Help');
    expect(tool.label, 'Help');
    expect(tool.icon, Icons.help_outline);
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

  test('sidekick-dialogue sits in Party between the other two party tools', () {
    final tools = buildToolRegistry(family: []);
    final ids = tools.map((t) => t.id).toList();
    expect(ids.indexOf('sidekick-dialogue'),
        greaterThan(ids.indexOf('party-emulator')));
    expect(ids.indexOf('sidekick-dialogue'),
        lessThan(ids.indexOf('behavior-tables')));
    final tool = tools.singleWhere((t) => t.id == 'sidekick-dialogue');
    expect(tool.group, 'Party');
    expect(tool.label, 'Sidekick Dialogue');
    expect(tool.badge, 'PET');
    expect(tool.icon, Icons.forum_outlined);
  });

  // -- System profile tests (Task 3) ------------------------------------------

  test('toolSystem covers every possible tool id', () {
    // The set of ids the registry can produce (with all systems + a family).
    final allIds = buildToolRegistry(family: ['classic'], systems: kAllSystems)
        .map((t) => t.id)
        .toSet();
    for (final id in allIds) {
      expect(toolSystem.containsKey(id), isTrue,
          reason: 'toolSystem missing entry for $id');
    }
    // All values are in the expected system set.
    const validSystems = {
      'juice',
      'mythic',
      'ironsworn',
      'party',
      'verdant',
      'lonelog',
      'hexcrawl',
      'core'
    };
    for (final v in toolSystem.values) {
      expect(validSystems.contains(v), isTrue, reason: 'unknown system $v');
    }
  });

  test(
      'juice-only profile includes fate-check, roll-high, maps, tables '
      'and core tools but excludes mythic and party tools', () {
    final tools = buildToolRegistry(family: [], systems: {'juice'});
    final ids = tools.map((t) => t.id).toSet();
    // Included (juice + core).
    expect(
        ids,
        containsAll([
          'fate-check',
          'roll-high',
          'maps',
          'tables',
          'dice',
          'encounter',
          'threads-characters',
          'help'
        ]));
    // Excluded (mythic / party).
    expect(ids, isNot(contains('mythic')));
    expect(ids, isNot(contains('party-emulator')));
    expect(ids, isNot(contains('behavior-tables')));
    expect(ids, isNot(contains('sidekick-dialogue')));
    // Excluded (verdant not enabled).
    expect(ids, isNot(contains('verdant')));
    // Moves absent because family is empty.
    expect(ids, isNot(contains('moves')));
  });

  test('verdant gating: tool present only when the verdant system is enabled',
      () {
    expect(
        buildToolRegistry(family: [], systems: {'juice'})
            .any((t) => t.id == 'verdant'),
        isFalse);
    expect(
        buildToolRegistry(family: [], systems: {'juice', 'verdant'})
            .any((t) => t.id == 'verdant'),
        isTrue);
  });

  test('ironsworn disabled: moves absent even with a non-empty family', () {
    final tools = buildToolRegistry(family: ['classic'], systems: {'juice'});
    expect(tools.any((t) => t.id == 'moves'), isFalse);
  });

  test('ironsworn enabled with family: moves present', () {
    final tools =
        buildToolRegistry(family: ['classic'], systems: {'ironsworn', 'juice'});
    expect(tools.any((t) => t.id == 'moves'), isTrue);
  });

  test('lonelog-ref gating: present only when the lonelog system is enabled',
      () {
    expect(
        buildToolRegistry(family: [], systems: {'juice'})
            .any((t) => t.id == 'lonelog-ref'),
        isFalse);
    final tools = buildToolRegistry(family: [], systems: {'juice', 'lonelog'});
    final tool = tools.singleWhere((t) => t.id == 'lonelog-ref');
    expect(tool.group, 'Reference');
    expect(tool.label, 'Lonelog Notation');
    expect(tool.badge, 'Lonelog');
  });

  test('resources gating: present only when the lonelog system is enabled', () {
    expect(
        buildToolRegistry(family: [], systems: {'juice'})
            .any((t) => t.id == 'resources'),
        isFalse);
    final tool = buildToolRegistry(family: [], systems: {'juice', 'lonelog'})
        .singleWhere((t) => t.id == 'resources');
    expect(tool.group, 'Characters & Threads');
    expect(tool.label, 'Resource Tracker');
    expect(tool.badge, 'Lonelog');
  });

  test('battle gating: present only when the lonelog system is enabled', () {
    expect(
        buildToolRegistry(family: [], systems: {'juice'})
            .any((t) => t.id == 'battle'),
        isFalse);
    final tool = buildToolRegistry(family: [], systems: {'juice', 'lonelog'})
        .singleWhere((t) => t.id == 'battle');
    expect(tool.group, 'Encounters & Combat');
    expect(tool.label, 'Battle Tracker');
    expect(tool.badge, 'Lonelog');
  });

  test('hexcrawl gating: present only when the hexcrawl feature is enabled',
      () {
    expect(
        buildToolRegistry(family: [], systems: {'juice'})
            .any((t) => t.id == 'hexcrawl'),
        isFalse);
    final tool = buildToolRegistry(family: [], systems: {'juice', 'hexcrawl'})
        .singleWhere((t) => t.id == 'hexcrawl');
    expect(tool.group, 'Exploration');
    expect(tool.label, 'Hexcrawl');
  });

  // -- Mode gating (GM/Party) -------------------------------------------------

  test('gm mode drops party-only tools and moves from the registry', () {
    final ids = buildToolRegistry(
      family: ['classic'],
      systems: {'party', 'ironsworn', 'juice'},
      mode: CampaignMode.gm,
    ).map((t) => t.id).toSet();
    expect(ids, isNot(contains('party-emulator')));
    expect(ids, isNot(contains('sidekick-dialogue')));
    expect(ids, isNot(contains('behavior-tables')));
    expect(ids, isNot(contains('moves')));
    // Mode-neutral tools survive.
    expect(ids, containsAll(['fate-check', 'encounter', 'help']));
  });

  test('party mode keeps party-only tools and moves', () {
    final ids = buildToolRegistry(
      family: ['classic'],
      systems: {'party', 'ironsworn'},
      mode: CampaignMode.party,
    ).map((t) => t.id).toSet();
    expect(
        ids,
        containsAll([
          'party-emulator',
          'sidekick-dialogue',
          'behavior-tables',
          'moves',
        ]));
  });

  test('mode defaults to party (party tools present without an explicit mode)',
      () {
    final ids = buildToolRegistry(family: [], systems: {'party'})
        .map((t) => t.id)
        .toSet();
    expect(ids, contains('party-emulator'));
  });
}
