import 'custom_sheet.dart';

/// A named starter schema (a pre-seeded block list). Generic mechanics only —
/// no game names, prose, or setting (facts-only).
class CustomTemplate {
  const CustomTemplate(
      {required this.id, required this.label, required this.blocks});
  final String id;
  final String label;
  final List<CustomBlock> blocks;
}

const kCustomTemplates = <CustomTemplate>[
  CustomTemplate(id: 'blank', label: 'Blank', blocks: []),
  CustomTemplate(id: 'generic-d20', label: 'Generic d20', blocks: [
    CustomBlock(id: 'g-stat', type: CustomBlockType.stat, label: 'Abilities', config: {
      'stats': [
        {'key': 'str', 'label': 'STR'},
        {'key': 'dex', 'label': 'DEX'},
        {'key': 'con', 'label': 'CON'},
        {'key': 'int', 'label': 'INT'},
        {'key': 'wis', 'label': 'WIS'},
        {'key': 'cha', 'label': 'CHA'},
      ],
      'min': 3,
      'max': 18,
      'modFormula': 'fived',
    }),
    CustomBlock(id: 'g-hp', type: CustomBlockType.hp, label: 'HP', config: {'allowTemp': false}),
    CustomBlock(id: 'g-ac', type: CustomBlockType.counter, label: 'AC', config: {'min': 0, 'max': 30, 'step': 1}),
    CustomBlock(id: 'g-saves', type: CustomBlockType.roll, label: 'Saves', config: {
      'rows': ['Fortitude', 'Reflex', 'Will'],
      'roll': {'dc': 1, 'ds': 20, 'ab': true, 'dir': 'high', 'tk': 'prompt', 'crit': 'none'},
    }),
    CustomBlock(id: 'g-cond', type: CustomBlockType.conditions, label: 'Conditions'),
    CustomBlock(id: 'g-notes', type: CustomBlockType.freeform, label: 'Notes', config: {'multiline': true}),
  ]),
  CustomTemplate(id: 'osr', label: 'OSR roll-under', blocks: [
    CustomBlock(id: 'o-stat', type: CustomBlockType.stat, label: 'Abilities', config: {
      'stats': [
        {'key': 'str', 'label': 'STR'},
        {'key': 'dex', 'label': 'DEX'},
        {'key': 'wil', 'label': 'WIL'},
      ],
      'min': 3,
      'max': 18,
      'modFormula': 'raw',
    }),
    CustomBlock(id: 'o-saves', type: CustomBlockType.roll, label: 'Saves', config: {
      'rows': ['STR', 'DEX', 'WIL'],
      'roll': {'dc': 1, 'ds': 20, 'ab': false, 'dir': 'low', 'tk': 'rowValue', 'crit': 'none'},
    }),
    CustomBlock(id: 'o-hp', type: CustomBlockType.hp, label: 'HP', config: {'allowTemp': false}),
    CustomBlock(id: 'o-cond', type: CustomBlockType.conditions, label: 'Conditions'),
    CustomBlock(id: 'o-notes', type: CustomBlockType.freeform, label: 'Notes', config: {'multiline': true}),
  ]),
  CustomTemplate(id: 'pbta', label: '2d6 PbtA', blocks: [
    CustomBlock(id: 'p-stat', type: CustomBlockType.stat, label: 'Stats', config: {
      'stats': [
        {'key': 'cool', 'label': 'COOL'},
        {'key': 'hard', 'label': 'HARD'},
        {'key': 'hot', 'label': 'HOT'},
        {'key': 'sharp', 'label': 'SHARP'},
        {'key': 'weird', 'label': 'WEIRD'},
      ],
      'min': -1,
      'max': 3,
      'modFormula': 'scoreIsMod',
    }),
    CustomBlock(id: 'p-moves', type: CustomBlockType.roll, label: 'Moves', config: {
      'rows': ['Act under fire', 'Go aggro'],
      'roll': {
        'dc': 2,
        'ds': 6,
        'ab': true,
        'dir': 'high',
        'tk': 'fixed',
        'ft': 0,
        'bands': [
          {'t': 10, 'l': 'Strong hit'},
          {'t': 7, 'l': 'Weak hit'},
          {'t': 0, 'l': 'Miss'},
        ],
        'crit': 'none',
      },
    }),
    CustomBlock(id: 'p-cond', type: CustomBlockType.conditions, label: 'Conditions'),
    CustomBlock(id: 'p-notes', type: CustomBlockType.freeform, label: 'Notes', config: {'multiline': true}),
  ]),
];
