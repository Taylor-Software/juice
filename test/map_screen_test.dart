import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/map_screen.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  final data = OracleData(
      jsonDecode(File('assets/oracle_data.json').readAsStringSync())
          as Map<String, dynamic>);

  Future<ProviderContainer> pump(WidgetTester tester, {String? mapJson}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      if (mapJson != null) 'juice.map.v1.default': mapJson,
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(body: MapScreen(oracle: Oracle(data))))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MapScreen)));
  }

  // Two rooms side by side at known coordinates so taps are deterministic.
  String seededMap({List<Map<String, dynamic>>? hexes}) => jsonEncode({
        'rooms': [
          {'id': 'a', 'x': 0, 'y': 0, 'title': 'Alpha', 'detail': 'Alpha detail'},
          {'id': 'b', 'x': 1, 'y': 0, 'title': 'Beta', 'detail': 'Beta detail'},
        ],
        'corridors': [
          ['a', 'b'],
        ],
        'currentRoomId': 'b',
        'hexes': hexes ?? const [],
      });

  group('roomIdAt', () {
    const cell = 56.0;
    const rooms = [
      DungeonRoom(id: 'c', x: -1, y: 0, title: 'C'),
      DungeonRoom(id: 'a', x: 0, y: 0, title: 'A'),
      DungeonRoom(id: 'b', x: 1, y: 0, title: 'B'),
    ];

    test('hit inside a room rect (incl. negative grid coords)', () {
      // pad = 28; room c renders with its cell origin at (28, 28).
      expect(roomIdAt(rooms, const Offset(56, 56), cell), 'c');
      expect(roomIdAt(rooms, const Offset(112, 56), cell), 'a');
      expect(roomIdAt(rooms, const Offset(168, 56), cell), 'b');
    });

    test('miss between rooms and in the padding', () {
      // Between a and b: a's rect ends at 134, b's starts at 146.
      expect(roomIdAt(rooms, const Offset(140, 56), cell), isNull);
      expect(roomIdAt(rooms, const Offset(0, 0), cell), isNull);
      expect(roomIdAt(const [], const Offset(56, 56), cell), isNull);
    });
  });

  testWidgets('New room twice grows a connected dungeon; canvas paints',
      (tester) async {
    final container = await pump(tester);
    expect(find.text('No rooms yet. New room rolls the dungeon oracle '
        'and maps it.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-room')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-room')));
    await tester.pumpAndSettle();
    final s = container.read(mapProvider).valueOrNull!;
    expect(s.rooms.length, 2);
    expect(s.corridors, [
      [s.rooms[0].id, s.rooms[1].id],
    ]);
    expect(s.currentRoomId, s.rooms[1].id);
    expect(find.byKey(const Key('dungeon-canvas')), findsOneWidget);
  });

  testWidgets('tap selects a room; Linger appends detail and shows result',
      (tester) async {
    final container = await pump(tester, mapJson: seededMap());
    // Room a (0,0) with minX 0: cell origin (28,28), center (56,56).
    final origin = tester.getTopLeft(find.byKey(const Key('dungeon-canvas')));
    await tester.tapAt(origin + const Offset(56, 56));
    await tester.pumpAndSettle();
    expect(container.read(mapProvider).valueOrNull!.currentRoomId, 'a');
    expect(find.byKey(const Key('room-detail-card')), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);

    await tester.tap(find.byKey(const Key('linger')));
    await tester.pumpAndSettle();
    final room = container
        .read(mapProvider)
        .valueOrNull!
        .rooms
        .firstWhere((r) => r.id == 'a');
    expect(room.detail, startsWith('Alpha detail\n'));
    expect(room.detail.length, greaterThan('Alpha detail\n'.length));
    expect(find.text('Dungeon Linger'), findsOneWidget);
  });

  testWidgets('journal snapshot logs room count and titles', (tester) async {
    final container = await pump(tester, mapJson: seededMap());
    await tester.tap(find.byKey(const Key('dungeon-journal')));
    await tester.pumpAndSettle();
    final entries = container.read(journalProvider).valueOrNull!;
    expect(entries.first.title, 'Dungeon map');
    expect(entries.first.body, contains('2 rooms'));
    expect(entries.first.body, contains('Alpha'));
    expect(entries.first.body, contains('Beta'));
    expect(find.text('Added to journal'), findsOneWidget);
  });

  testWidgets('reset confirm clears rooms but keeps revealed hexes',
      (tester) async {
    final container = await pump(tester,
        mapJson: seededMap(hexes: [
          {'col': 0, 'row': 0, 'envRow': 3, 'lost': false},
        ]));
    await tester.tap(find.byKey(const Key('dungeon-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    final s = container.read(mapProvider).valueOrNull!;
    expect(s.rooms, isEmpty);
    expect(s.corridors, isEmpty);
    expect(s.currentRoomId, isNull);
    expect(s.hexes.length, 1);
  });
}
