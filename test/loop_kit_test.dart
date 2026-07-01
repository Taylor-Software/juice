// test/loop_kit_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/custom_table.dart';
import 'package:juice_oracle/engine/loop_kit.dart';
import 'package:juice_oracle/engine/quick_ref.dart';

void main() {
  group('LoopKit encode/decode', () {
    test('round-trips name/system/tables/refCards/scene', () {
      const kit = LoopKit(
        name: 'Ash and Embers',
        system: 'ironsworn',
        tables: [
          CustomTable(id: 't1', name: 'Ashland Omens', rows: [
            CustomRow('A crow refuses to fly'),
            CustomRow('The ash falls upward for a moment'),
          ]),
        ],
        refCards: [
          UserRefCard(id: 'c1', title: 'Ashland Facts', sections: [
            QuickRefSection('Setting', ['The war ended, the ash did not.']),
          ]),
        ],
        sceneTitle: 'Cinders on the Wind',
        sceneBody: 'You wake in a burned grove. Something is still burning.',
      );
      final back = decodeLoopKit(encodeLoopKit(kit));
      expect(back, isNotNull);
      expect(back!.name, 'Ash and Embers');
      expect(back.system, 'ironsworn');
      expect(back.tables, hasLength(1));
      expect(back.tables.single.name, 'Ashland Omens');
      expect(back.tables.single.rows.map((r) => r.text).toList(),
          ['A crow refuses to fly', 'The ash falls upward for a moment']);
      expect(back.refCards, hasLength(1));
      expect(back.refCards.single.title, 'Ashland Facts');
      expect(back.refCards.single.sections.single.lines,
          ['The war ended, the ash did not.']);
      expect(back.sceneTitle, 'Cinders on the Wind');
      expect(back.sceneBody,
          'You wake in a burned grove. Something is still burning.');
    });

    test('system is optional and omitted when null', () {
      const kit = LoopKit(name: 'No System');
      final json = jsonDecode(encodeLoopKit(kit)) as Map;
      expect(json.containsKey('system'), isFalse);
      final back = decodeLoopKit(encodeLoopKit(kit));
      expect(back!.system, isNull);
    });

    test('empty tables/refCards/scene round-trip as empty, not null', () {
      const kit = LoopKit(name: 'Bare');
      final back = decodeLoopKit(encodeLoopKit(kit));
      expect(back!.tables, isEmpty);
      expect(back.refCards, isEmpty);
      expect(back.sceneTitle, '');
      expect(back.sceneBody, '');
    });

    test('wrong kind decodes to null', () {
      expect(
          decodeLoopKit(
              '{"kind":"something-else","v":1,"name":"x","tables":[],"refCards":[],"scene":{"title":"","body":""}}'),
          isNull);
    });

    test('junk table/refCard entries are dropped, valid ones kept', () {
      final raw = jsonEncode({
        'kind': kLoopKitKind,
        'v': 1,
        'name': 'Mixed',
        'tables': [
          42,
          const CustomTable(id: 'a', name: 'A', rows: [CustomRow('X')])
              .toJson(),
        ],
        'refCards': [
          'not a map',
          const UserRefCard(id: 'c', title: 'C', sections: []).toJson(),
        ],
        'scene': {'title': 'S', 'body': 'B'},
      });
      final back = decodeLoopKit(raw);
      expect(back, isNotNull);
      expect(back!.tables, hasLength(1));
      expect(back.tables.single.name, 'A');
      expect(back.refCards, hasLength(1));
      expect(back.refCards.single.title, 'C');
    });

    test('missing name decodes to null', () {
      final raw = jsonEncode({
        'kind': kLoopKitKind,
        'v': 1,
        'tables': [],
        'refCards': [],
        'scene': {'title': '', 'body': ''},
      });
      expect(decodeLoopKit(raw), isNull);
    });

    test('unparseable top-level JSON throws FormatException', () {
      expect(() => decodeLoopKit('not json'), throwsFormatException);
    });
  });
}
