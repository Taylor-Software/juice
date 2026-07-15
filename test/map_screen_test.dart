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
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/state/play_context.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  final data = OracleData(
      jsonDecode(File('assets/oracle_data.json').readAsStringSync())
          as Map<String, dynamic>);

  // The Dungeon/Hex tab chrome now lives in maps_tab.dart; these tests pump
  // the public panes directly.
  Future<ProviderContainer> pumpDungeon(WidgetTester tester,
      {String? mapJson}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      if (mapJson != null) 'juice.map.v1.default': mapJson,
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(body: DungeonMapPane(oracle: Oracle(data))))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(DungeonMapPane)));
  }

  Future<ProviderContainer> pumpHex(WidgetTester tester,
      {String? mapJson}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      if (mapJson != null) 'juice.map.v1.default': mapJson,
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(body: HexMapPane(oracle: Oracle(data))))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(HexMapPane)));
  }

  /// Secondary map controls (journal/snapshot/reset, dungeon-site chips, the
  /// up-to-world chip, hexcrawl generation) are folded behind the chrome's
  /// Tools toggle so the canvas owns the pane — open it before reaching them.
  Future<void> openTools(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('map-tools-toggle')));
    await tester.pumpAndSettle();
  }

  // Two rooms side by side at known coordinates so taps are deterministic.
  String seededMap({List<Map<String, dynamic>>? hexes}) => jsonEncode({
        'rooms': [
          {
            'id': 'a',
            'x': 0,
            'y': 0,
            'title': 'Alpha',
            'detail': 'Alpha detail'
          },
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
    final container = await pumpDungeon(tester);
    expect(
        find.text('No rooms yet. New room rolls the dungeon oracle '
            'and maps it.'),
        findsOneWidget);
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

  // Regression guard for the full-bleed map chrome. Both panes used to stack
  // controls, chips and detail cards as Column siblings around
  // Expanded(canvas), so the map got only the leftovers from both ends. The
  // canvas now owns the pane and the chrome floats over it.
  testWidgets('the canvas owns the pane; the detail card floats over it',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDungeon(tester, mapJson: seededMap());

    final paneH = tester.getSize(find.byType(DungeonMapPane)).height;
    final viewport = find.ancestor(
        of: find.byKey(const Key('dungeon-canvas')),
        matching: find.byType(InteractiveViewer));
    expect(tester.getSize(viewport).height, paneH,
        reason: 'the canvas viewport should fill the pane, not share it');

    // Selecting a room must not shrink the map — the card floats over it.
    final origin = tester.getTopLeft(find.byKey(const Key('dungeon-canvas')));
    await tester.tapAt(origin + const Offset(56, 56));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-detail-card')), findsOneWidget);
    expect(tester.getSize(viewport).height, paneH,
        reason: 'the detail card stole height from the canvas');
  });

  testWidgets('secondary controls fold away behind the Tools toggle',
      (tester) async {
    await pumpDungeon(tester, mapJson: seededMap());
    expect(find.byKey(const Key('dungeon-reset')), findsNothing);
    // The pane's main verb stays one tap away, never folded.
    expect(find.byKey(const Key('new-room')), findsOneWidget);
    await openTools(tester);
    expect(find.byKey(const Key('dungeon-reset')), findsOneWidget);
  });

  testWidgets('tap selects a room; Linger appends detail and shows result',
      (tester) async {
    final container = await pumpDungeon(tester, mapJson: seededMap());
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
    final container = await pumpDungeon(tester, mapJson: seededMap());
    await openTools(tester);
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
    final container = await pumpDungeon(tester,
        mapJson: seededMap(hexes: [
          {'col': 0, 'row': 0, 'envRow': 3, 'lost': false},
        ]));
    await openTools(tester);
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

  // -- Hex --------------------------------------------------------------------

  group('hexAt', () {
    const size = 34.0;
    const cells = [
      (col: -1, row: 0),
      (col: 0, row: 0),
      (col: 1, row: 2),
    ];

    test('cell centers map back to their cell (incl. odd/negative cols)', () {
      for (final c in cells) {
        final p = hexCenterFor(c.col, c.row, -1, 0, size);
        expect(hexAt(p, size, cells, minCol: -1, minRow: 0), c);
      }
    });

    test('hexCenterFor matches hand-computed flat-top odd-q literals', () {
      // pad = 2 * size = 68 throughout.
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
      expect(
          hexAt(nearA, size, cells, minCol: -1, minRow: 0), (col: -1, row: 0));
      expect(
          hexAt(nearB, size, cells, minCol: -1, minRow: 0), (col: 0, row: 0));
    });

    test('point outside the 0.9*size radius of every center is null', () {
      expect(hexAt(Offset.zero, size, cells, minCol: -1, minRow: 0), isNull);
      expect(
          hexAt(const Offset(5000, 5000), size, cells, minCol: -1, minRow: 0),
          isNull);
    });
  });

  testWidgets('Travel advances crawl and reveals adjacent hexes',
      (tester) async {
    final container = await pumpHex(tester);
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
    final adjacent = hexNeighbors(0, 0).map((n) => (n.col, n.row)).toList();
    expect(adjacent, contains((s.currentHexCol, s.currentHexRow)));
    final crawl2 = container.read(crawlProvider).valueOrNull!;
    final cur = s.hexes.firstWhere(
        (h) => h.col == s.currentHexCol && h.row == s.currentHexRow);
    expect(cur.envRow, crawl2.envRow);
  });

  testWidgets(
      'tap on a faint neighbor opens env picker; manual reveal '
      'persists without moving current', (tester) async {
    final container = await pumpHex(tester,
        mapJson: jsonEncode({
          'hexes': [
            {'col': 0, 'row': 0, 'envRow': 3, 'lost': false},
          ],
          'currentHexCol': 0,
          'currentHexRow': 0,
        }));

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
    final container = await pumpHex(tester,
        mapJson: jsonEncode({
          'hexes': [
            {'col': 0, 'row': 0, 'envRow': 3, 'lost': false},
            {'col': 1, 'row': 0, 'envRow': 7, 'lost': false},
          ],
          'currentHexCol': 1,
          'currentHexRow': 0,
        }));
    await openTools(tester);
    await tester.tap(find.byKey(const Key('hex-journal')));
    await tester.pumpAndSettle();
    final entries = container.read(journalProvider).valueOrNull!;
    expect(entries.first.title, 'Wilderness map');
    expect(entries.first.body, contains('2 hexes revealed'));
    expect(entries.first.body,
        contains('current: ${data.table('wilderness_environment')[6]}'));
    expect(find.text('Added to journal'), findsOneWidget);
  });

  // -- Encounter pin ----------------------------------------------------------

  testWidgets('dungeon detail card links and unlinks the encounter location',
      (tester) async {
    final container = await pumpDungeon(tester, mapJson: seededMap());
    final origin = tester.getTopLeft(find.byKey(const Key('dungeon-canvas')));
    await tester.tapAt(origin + const Offset(56, 56)); // select room a
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('room-detail-card')), findsOneWidget);
    expect(find.text('Set encounter here'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dungeon-encounter-toggle')));
    await tester.pumpAndSettle();
    expect(container.read(encounterProvider).valueOrNull!.locationRef?.roomId,
        'a');
    expect(find.text('Encounter here ✓'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dungeon-encounter-toggle')));
    await tester.pumpAndSettle();
    expect(container.read(encounterProvider).valueOrNull!.locationRef, isNull);
  });

  testWidgets('dungeon detail card jumps to the encounter when linked',
      (tester) async {
    final container = await pumpDungeon(tester, mapJson: seededMap());
    final origin = tester.getTopLeft(find.byKey(const Key('dungeon-canvas')));
    await tester.tapAt(origin + const Offset(56, 56)); // select room a
    await tester.pumpAndSettle();
    // No jump button until this cell is the encounter location.
    expect(find.byKey(const Key('dungeon-encounter-goto')), findsNothing);

    await tester.tap(find.byKey(const Key('dungeon-encounter-toggle')));
    await tester.pumpAndSettle();
    // Linked → the jump button appears and routes to Track › Encounter.
    await tester.tap(find.byKey(const Key('dungeon-encounter-goto')));
    await tester.pumpAndSettle();
    final route = container.read(shellRouteProvider);
    expect(route.destination, Destination.track);
    expect(route.subtab, 'encounter');
  });

  testWidgets('hex detail card links the encounter to the selected hex',
      (tester) async {
    // The hex detail card (and so the toggle) is gated behind the hexcrawl
    // opt-in, so enable it on the seeded session.
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1': '{"active":"default","sessions":[{"id":"default",'
          '"name":"C1","systems":["juice","hexcrawl"]}]}',
      'juice.map.v1.default': jsonEncode({
        'hexes': [
          {'col': 0, 'row': 0, 'envRow': 3, 'lost': false},
        ],
        'currentHexCol': 0,
        'currentHexRow': 0,
      }),
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(body: HexMapPane(oracle: Oracle(data))))));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HexMapPane)));

    // Cells = (0,0) + 6 neighbors -> minCol = minRow = -1.
    final origin = tester.getTopLeft(find.byKey(const Key('hex-canvas')));
    await tester.tapAt(origin + hexCenterFor(0, 0, -1, -1, 34.0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hex-detail-card')), findsOneWidget);

    await tester.tap(find.byKey(const Key('hex-encounter-toggle')));
    await tester.pumpAndSettle();
    final loc = container.read(encounterProvider).valueOrNull!.locationRef;
    expect(loc?.hexCol, 0);
    expect(loc?.hexRow, 0);
  });

  testWidgets(
      'hex detail card anchors the dungeon: Dungeon here → Enter dungeon + '
      'Unlink', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1': '{"active":"default","sessions":[{"id":"default",'
          '"name":"C1","systems":["juice","hexcrawl"]}]}',
      'juice.map.v1.default': jsonEncode({
        'hexes': [
          {'col': 0, 'row': 0, 'envRow': 3, 'lost': false},
        ],
        'currentHexCol': 0,
        'currentHexRow': 0,
      }),
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(body: HexMapPane(oracle: Oracle(data))))));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HexMapPane)));

    final origin = tester.getTopLeft(find.byKey(const Key('hex-canvas')));
    await tester.tapAt(origin + hexCenterFor(0, 0, -1, -1, 34.0));
    await tester.pumpAndSettle();

    // Unanchored: the place-dungeon chip shows; anchor it.
    await tester.ensureVisible(find.byKey(const Key('hex-place-dungeon')));
    await tester.tap(find.byKey(const Key('hex-place-dungeon')));
    await tester.pumpAndSettle();
    final m = container.read(mapProvider).valueOrNull!;
    expect(m.anchorHexCol, 0);
    expect(m.anchorHexRow, 0);

    // Anchored: Enter dungeon navigates to the dungeon subtab.
    await tester.ensureVisible(find.byKey(const Key('hex-enter-dungeon')));
    await tester.tap(find.byKey(const Key('hex-enter-dungeon')));
    await tester.pumpAndSettle();
    final route = container.read(shellRouteProvider);
    expect(route.destination, Destination.map);
    expect(route.subtab, 'dungeon');

    // Unlink clears the anchor.
    await tester.ensureVisible(find.byKey(const Key('hex-unlink-dungeon')));
    await tester.tap(find.byKey(const Key('hex-unlink-dungeon')));
    await tester.pumpAndSettle();
    expect(container.read(mapProvider).valueOrNull!.hasAnchor, isFalse);
  });

  testWidgets('backlink sheet row previews the entry; Open journal navigates',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1': '{"active":"default","sessions":[{"id":"default",'
          '"name":"C1","systems":["juice","hexcrawl"]}]}',
      'juice.map.v1.default': jsonEncode({
        'hexes': [
          {'col': 0, 'row': 0, 'envRow': 3, 'lost': false},
        ],
        'currentHexCol': 0,
        'currentHexRow': 0,
      }),
      'juice.journal.v2.default': '[{"id":"n1",'
          '"timestamp":"2026-06-12T10:00:00.000Z","title":"Ambush",'
          '"body":"Goblins strike.","kind":"text","tags":[],'
          '"loc":{"hexCol":0,"hexRow":0}}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(body: HexMapPane(oracle: Oracle(data))))));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HexMapPane)));

    final origin = tester.getTopLeft(find.byKey(const Key('hex-canvas')));
    await tester.tapAt(origin + hexCenterFor(0, 0, -1, -1, 34.0));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('loc-entries-0-0')));
    await tester.tap(find.byKey(const Key('loc-entries-0-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('loc-entry-row-n1')));
    await tester.pumpAndSettle();

    // Preview dialog shows title + body.
    expect(find.byKey(const Key('entry-preview-n1')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('entry-preview-n1')),
            matching: find.text('Goblins strike.')),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('entry-preview-open-n1')));
    await tester.pumpAndSettle();
    expect(container.read(shellRouteProvider).destination, Destination.journal);
    // Both the preview and the backlink sheet are gone.
    expect(find.byKey(const Key('entry-preview-n1')), findsNothing);
    expect(find.byKey(const Key('loc-entry-row-n1')), findsNothing);
  });

  testWidgets(
      'hex detail card links a sketch map: pick, open chip shows title, unlink',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1': '{"active":"default","sessions":[{"id":"default",'
          '"name":"C1","systems":["juice","hexcrawl"]}]}',
      'juice.map.v1.default': jsonEncode({
        'hexes': [
          {'col': 0, 'row': 0, 'envRow': 3, 'lost': false},
        ],
        'currentHexCol': 0,
        'currentHexRow': 0,
      }),
      'juice.journal.v2.default': '[{"id":"s1",'
          '"timestamp":"2026-06-12T09:00:00.000Z","title":"Town map",'
          '"body":"","kind":"sketch","tags":[],'
          '"payload":{"v":1,"sketch":{"v":1,"strokes":[],"w":100,"h":100}}}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(body: HexMapPane(oracle: Oracle(data))))));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HexMapPane)));

    final origin = tester.getTopLeft(find.byKey(const Key('hex-canvas')));
    await tester.tapAt(origin + hexCenterFor(0, 0, -1, -1, 34.0));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('hex-link-sketch')));
    await tester.tap(find.byKey(const Key('hex-link-sketch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-pick-s1')));
    await tester.pumpAndSettle();

    final hex = container
        .read(mapProvider)
        .valueOrNull!
        .hexes
        .firstWhere((x) => x.col == 0 && x.row == 0);
    expect(hex.sketchEntryId, 's1');
    await tester.ensureVisible(find.byKey(const Key('hex-open-sketch')));
    expect(find.text('Map: Town map'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('hex-unlink-sketch')));
    await tester.tap(find.byKey(const Key('hex-unlink-sketch')));
    await tester.pumpAndSettle();
    expect(
        container
            .read(mapProvider)
            .valueOrNull!
            .hexes
            .firstWhere((x) => x.col == 0 && x.row == 0)
            .sketchEntryId,
        isNull);
  });

  testWidgets(
      'Dungeon-here on a second hex creates a new dungeon; switcher chips '
      'switch the active dungeon', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1': '{"active":"default","sessions":[{"id":"default",'
          '"name":"C1","systems":["juice","hexcrawl"]}]}',
      'juice.map.v1.default': jsonEncode({
        'dungeons': [
          {
            'id': 'a',
            'name': 'Crypt',
            'anchorHexCol': 5,
            'anchorHexRow': 5,
          },
        ],
        'activeDungeon': 'a',
        'hexes': [
          {'col': 0, 'row': 0, 'envRow': 3, 'lost': false},
        ],
        'currentHexCol': 0,
        'currentHexRow': 0,
      }),
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(body: HexMapPane(oracle: Oracle(data))))));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HexMapPane)));

    final origin = tester.getTopLeft(find.byKey(const Key('hex-canvas')));
    await tester.tapAt(origin + hexCenterFor(0, 0, -1, -1, 34.0));
    await tester.pumpAndSettle();

    // Active dungeon already anchored elsewhere → Dungeon-here creates a NEW
    // dungeon anchored to this hex and makes it active.
    await tester.ensureVisible(find.byKey(const Key('hex-place-dungeon')));
    await tester.tap(find.byKey(const Key('hex-place-dungeon')));
    await tester.pumpAndSettle();
    final m = container.read(mapProvider).valueOrNull!;
    expect(m.dungeons, hasLength(2));
    expect(m.activeDungeon!.name, 'Dungeon 2');
    expect(m.dungeonAnchoredAt(0, 0)!.id, m.activeDungeon!.id);
    // The Enter chip names the anchored dungeon.
    await tester.ensureVisible(find.byKey(const Key('hex-enter-dungeon')));
    expect(find.text('Enter Dungeon 2'), findsOneWidget);
  });

  testWidgets('dungeon pane switcher lists dungeons and switches active',
      (tester) async {
    final container = await pumpDungeon(tester,
        mapJson: jsonEncode({
          'dungeons': [
            {
              'id': 'a',
              'name': 'Crypt',
              'levels': [
                {
                  'depth': 1,
                  'rooms': [
                    {'id': 'r1', 'x': 0, 'y': 0, 'title': 'Bone Hall'},
                  ],
                  'corridors': [],
                },
              ],
            },
            {'id': 'b', 'name': 'Mine'},
          ],
          'activeDungeon': 'a',
          'hexes': [],
          'currentHexCol': null,
          'currentHexRow': null,
        }));

    await openTools(tester);
    expect(find.byKey(const Key('dungeon-site-chip-a')), findsOneWidget);
    expect(find.byKey(const Key('dungeon-site-chip-b')), findsOneWidget);
    expect(find.byKey(const Key('dungeon-new-site')), findsOneWidget);

    await tester.tap(find.byKey(const Key('dungeon-site-chip-b')));
    await tester.pumpAndSettle();
    expect(
        container.read(mapProvider).valueOrNull!.activeDungeon!.name, 'Mine');
    // Mine has no rooms yet — the pane shows the empty state.
    expect(find.byKey(const Key('dungeon-canvas')), findsNothing);

    // New dungeon appends and becomes active.
    await tester.tap(find.byKey(const Key('dungeon-new-site')));
    await tester.pumpAndSettle();
    final m = container.read(mapProvider).valueOrNull!;
    expect(m.dungeons, hasLength(3));
    expect(m.activeDungeon!.name, 'Dungeon 3');
  });

  testWidgets('dungeon pane shows the up-to-world chip when anchored',
      (tester) async {
    final container = await pumpDungeon(tester,
        mapJson: jsonEncode({
          'levels': [
            {
              'depth': 1,
              'rooms': [
                {'id': 'a', 'x': 0, 'y': 0, 'title': 'Alpha'},
              ],
              'corridors': [],
            },
          ],
          'hexes': [],
          'currentHexCol': null,
          'currentHexRow': null,
          'anchorHexCol': 2,
          'anchorHexRow': 3,
        }));

    await openTools(tester);
    expect(find.byKey(const Key('dungeon-up-world')), findsOneWidget);
    expect(find.textContaining('Hex (2, 3)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dungeon-up-world')));
    await tester.pumpAndSettle();
    final route = container.read(shellRouteProvider);
    expect(route.destination, Destination.map);
    expect(route.subtab, 'world');
    // The spine now points at the anchor hex (world pane preselects it).
    final loc = container.read(playContextProvider).valueOrNull?.activeLocation;
    expect(loc?.hexCol, 2);
    expect(loc?.hexRow, 3);
  });
}
