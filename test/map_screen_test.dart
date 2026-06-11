import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/map_builder.dart';
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

  // -- Hex tab ---------------------------------------------------------------

  Future<void> toHexTab(WidgetTester tester) async {
    await tester.tap(find.text('Hex'));
    await tester.pumpAndSettle();
  }

  group('hexAt', () {
    const size = 34.0;
    const cells = [
      (col: -1, row: 0),
      (col: 0, row: 0),
      (col: 1, row: 2),
    ];

    test('cell centers map back to their cell (incl. odd/negative cols)',
        () {
      for (final c in cells) {
        final p = hexCenterFor(c.col, c.row, -1, 0, size);
        expect(hexAt(p, size, cells, minCol: -1, minRow: 0), c);
      }
    });

    test('hexCenterFor matches hand-computed flat-top odd-q literals', () {
      const pad = 2 * size; // 68
      // (0,0) with minCol -1, minRow 0: x = (0-(-1))*1.5*34 + 68 = 119;
      // even col -> no parity shift; y = 0 + 68 = 68.
      expect(hexCenterFor(0, 0, -1, 0, size), const Offset(119, 68));
      // (-1,0): x = 68; col -1 is odd -> y = 68 + sqrt(3)/2*34 ≈ 97.444.
      final odd = hexCenterFor(-1, 0, -1, 0, size);
      expect(odd.dx, 68);
      expect(odd.dy, closeTo(97.444, 0.01));
      // (1,2): x = (1+1)*1.5*34 + 68 = 170; odd col ->
      // y = 2*sqrt(3)*34 + sqrt(3)/2*34 + 68 ≈ 215.222.
      final far = hexCenterFor(1, 2, -1, 0, size);
      expect(far.dx, 170);
      expect(far.dy, closeTo(215.222, 0.01));
    });

    test('point between two centers snaps to the nearest', () {
      final a = hexCenterFor(-1, 0, -1, 0, size);
      final b = hexCenterFor(0, 0, -1, 0, size);
      final nearA = Offset.lerp(a, b, 0.3)!;
      final nearB = Offset.lerp(a, b, 0.7)!;
      expect(hexAt(nearA, size, cells, minCol: -1, minRow: 0),
          (col: -1, row: 0));
      expect(hexAt(nearB, size, cells, minCol: -1, minRow: 0),
          (col: 0, row: 0));
    });

    test('point outside the 0.9*size radius of every center is null', () {
      expect(hexAt(Offset.zero, size, cells, minCol: -1, minRow: 0), isNull);
      expect(hexAt(const Offset(5000, 5000), size, cells,
          minCol: -1, minRow: 0), isNull);
    });
  });

  testWidgets('Travel advances crawl and reveals adjacent hexes',
      (tester) async {
    final container = await pump(tester);
    await toHexTab(tester);
    expect(find.text('No hexes yet. Travel reveals the map as you go.'),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('travel')));
    await tester.pumpAndSettle();
    final crawl = container.read(crawlProvider).valueOrNull!;
    expect(crawl.envRow, isNotNull);
    var s = container.read(mapProvider).valueOrNull!;
    expect(s.hexes.length, 1);
    expect((s.hexes.first.col, s.hexes.first.row), (0, 0));
    expect(s.hexes.first.envRow, crawl.envRow);
    expect(s.hexes.first.lost, crawl.lost);
    expect((s.currentHexCol, s.currentHexRow), (0, 0));
    expect(find.text('Wilderness Travel'), findsOneWidget);

    await tester.tap(find.byKey(const Key('travel')));
    await tester.pumpAndSettle();
    s = container.read(mapProvider).valueOrNull!;
    // From a single revealed hex all 6 neighbors are free: always a new cell.
    expect(s.hexes.length, 2);
    final adjacent =
        hexNeighbors(0, 0).map((n) => (n.col, n.row)).toList();
    expect(adjacent, contains((s.currentHexCol, s.currentHexRow)));
    final crawl2 = container.read(crawlProvider).valueOrNull!;
    final cur = s.hexes.firstWhere(
        (h) => h.col == s.currentHexCol && h.row == s.currentHexRow);
    expect(cur.envRow, crawl2.envRow);
  });

  testWidgets('tap on a faint neighbor opens env picker; manual reveal '
      'persists without moving current', (tester) async {
    final container = await pump(tester,
        mapJson: jsonEncode({
          'hexes': [
            {'col': 0, 'row': 0, 'envRow': 3, 'lost': false},
          ],
          'currentHexCol': 0,
          'currentHexRow': 0,
        }));
    await toHexTab(tester);

    // Cells = (0,0) + its 6 unrevealed neighbors -> minCol = minRow = -1.
    final origin = tester.getTopLeft(find.byKey(const Key('hex-canvas')));
    await tester.tapAt(origin + hexCenterFor(1, 0, -1, -1, 34.0));
    await tester.pumpAndSettle();
    final envNames = data.table('wilderness_environment');
    for (final name in envNames) {
      expect(find.text(name), findsOneWidget);
    }
    await tester.tap(find.text(envNames[6])); // envRow 7
    await tester.pumpAndSettle();

    final s = container.read(mapProvider).valueOrNull!;
    expect(s.hexes.length, 2);
    final h = s.hexes.firstWhere((h) => h.col == 1 && h.row == 0);
    expect(h.envRow, 7);
    expect((s.currentHexCol, s.currentHexRow), (0, 0));
  });

  testWidgets('hex journal snapshot logs count and current env',
      (tester) async {
    final container = await pump(tester,
        mapJson: jsonEncode({
          'hexes': [
            {'col': 0, 'row': 0, 'envRow': 3, 'lost': false},
            {'col': 1, 'row': 0, 'envRow': 7, 'lost': false},
          ],
          'currentHexCol': 1,
          'currentHexRow': 0,
        }));
    await toHexTab(tester);
    await tester.tap(find.byKey(const Key('hex-journal')));
    await tester.pumpAndSettle();
    final entries = container.read(journalProvider).valueOrNull!;
    expect(entries.first.title, 'Wilderness map');
    expect(entries.first.body, contains('2 hexes revealed'));
    expect(entries.first.body,
        contains('current: ${data.table('wilderness_environment')[6]}'));
    expect(find.text('Added to journal'), findsOneWidget);
  });
}
