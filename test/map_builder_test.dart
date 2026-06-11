import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/map_builder.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/campaign_io.dart';
import 'package:juice_oracle/state/providers.dart';

ProviderContainer _container({String? mapJson}) {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    if (mapJson != null) 'juice.map.v1.default': mapJson,
  });
  return ProviderContainer();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Map models', () {
    test('full MapState round-trips through JSON', () {
      const s = MapState(
        rooms: [
          DungeonRoom(id: 'r0', x: 0, y: 0, title: 'Entry', detail: 'Dusty'),
          DungeonRoom(id: 'r1', x: 1, y: 0, title: 'Hall'),
        ],
        corridors: [
          ['r0', 'r1'],
        ],
        currentRoomId: 'r1',
        hexes: [
          HexCell(col: 0, row: 0, envRow: 3),
          HexCell(col: 1, row: 0, envRow: 7, lost: true),
        ],
        currentHexCol: 1,
        currentHexRow: 0,
      );
      final back = MapState.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.rooms, hasLength(2));
      expect(back.rooms[0].id, 'r0');
      expect(back.rooms[0].x, 0);
      expect(back.rooms[0].y, 0);
      expect(back.rooms[0].title, 'Entry');
      expect(back.rooms[0].detail, 'Dusty');
      expect(back.rooms[1].detail, '');
      expect(back.corridors, [
        ['r0', 'r1'],
      ]);
      expect(back.currentRoomId, 'r1');
      expect(back.hexes, hasLength(2));
      expect(back.hexes[0].col, 0);
      expect(back.hexes[0].row, 0);
      expect(back.hexes[0].envRow, 3);
      expect(back.hexes[0].lost, isFalse);
      expect(back.hexes[1].envRow, 7);
      expect(back.hexes[1].lost, isTrue);
      expect(back.currentHexCol, 1);
      expect(back.currentHexRow, 0);
    });

    test('tolerant parse: empty map gives empty state', () {
      final s = MapState.fromJson(<String, dynamic>{});
      expect(s.rooms, isEmpty);
      expect(s.corridors, isEmpty);
      expect(s.currentRoomId, isNull);
      expect(s.hexes, isEmpty);
      expect(s.currentHexCol, isNull);
      expect(s.currentHexRow, isNull);
    });

    test('tolerant parse: junk corridor/room/hex entries are skipped', () {
      final s = MapState.fromJson(jsonDecode(jsonEncode({
        'rooms': [
          {'id': 'r0', 'x': 2, 'y': 3, 'title': 'T'},
          'junk',
          42,
          {'x': 1}, // no id: malformed, skipped
        ],
        'corridors': [
          ['a', 'b'],
          ['only-one'],
          'junk',
          42,
          ['x', 'y', 'z'],
          [1, 2],
        ],
        'hexes': [
          {'col': 0, 'row': 0, 'envRow': 4},
          {'col': 'x', 'row': 0}, // non-int coord: skipped
          'junk',
          {'col': 1, 'row': 1, 'envRow': 99}, // envRow clamps into 1..10
        ],
      })) as Map<String, dynamic>);
      expect(s.rooms.single.id, 'r0');
      expect(s.rooms.single.title, 'T');
      expect(s.corridors, [
        ['a', 'b'],
      ]);
      expect(s.hexes, hasLength(2));
      expect(s.hexes[0].envRow, 4);
      expect(s.hexes[1].envRow, 10);
    });
  });

  group('nextRoomPosition', () {
    test('first room goes to the origin, attached to nothing', () {
      final pos = nextRoomPosition(const [], null, Dice(Random(1)));
      expect(pos.x, 0);
      expect(pos.y, 0);
      expect(pos.attachTo, isNull);
    });

    test('is deterministic under a seeded Dice', () {
      const rooms = [
        DungeonRoom(id: 'r0', x: 0, y: 0, title: 'A'),
        DungeonRoom(id: 'r1', x: 0, y: -1, title: 'B'),
      ];
      final a = nextRoomPosition(rooms, 'r0', Dice(Random(42)));
      final b = nextRoomPosition(rooms, 'r0', Dice(Random(42)));
      expect(a, b);
    });

    test('seed-grown 30-room dungeon never overlaps and stays connected', () {
      final dice = Dice(Random(7));
      final rooms = <DungeonRoom>[];
      final corridors = <List<String>>[];
      String? current;
      for (var i = 0; i < 30; i++) {
        final pos = nextRoomPosition(rooms, current, dice);
        final room = DungeonRoom(id: 'r$i', x: pos.x, y: pos.y, title: 'R$i');
        if (pos.attachTo != null) corridors.add([pos.attachTo!, room.id]);
        rooms.add(room);
        current = room.id;
      }
      // No two rooms share a cell.
      expect(rooms.map((r) => '${r.x},${r.y}').toSet(), hasLength(30));
      // Every corridor endpoint is a real room.
      final ids = rooms.map((r) => r.id).toSet();
      for (final c in corridors) {
        expect(ids, containsAll(c));
      }
      expect(corridors, hasLength(29)); // one per room after the first
      // BFS over corridors from the first room reaches all 30.
      final adjacency = <String, List<String>>{};
      for (final c in corridors) {
        adjacency.putIfAbsent(c[0], () => []).add(c[1]);
        adjacency.putIfAbsent(c[1], () => []).add(c[0]);
      }
      final reached = {rooms.first.id};
      final queue = [rooms.first.id];
      while (queue.isNotEmpty) {
        for (final n in adjacency[queue.removeAt(0)] ?? const <String>[]) {
          if (reached.add(n)) queue.add(n);
        }
      }
      expect(reached, hasLength(30));
    });

    test('boxed-in current room walks to a neighbor with free space', () {
      // Plus shape: center fully enclosed by 4 rooms.
      const rooms = [
        DungeonRoom(id: 'center', x: 0, y: 0, title: 'C'),
        DungeonRoom(id: 'n', x: 0, y: -1, title: 'N'),
        DungeonRoom(id: 'e', x: 1, y: 0, title: 'E'),
        DungeonRoom(id: 's', x: 0, y: 1, title: 'S'),
        DungeonRoom(id: 'w', x: -1, y: 0, title: 'W'),
      ];
      final occupied = rooms.map((r) => '${r.x},${r.y}').toSet();
      for (var seed = 0; seed < 10; seed++) {
        final pos = nextRoomPosition(rooms, 'center', Dice(Random(seed)));
        expect(pos.attachTo, isNotNull);
        expect(pos.attachTo, isNot('center'));
        expect(occupied, isNot(contains('${pos.x},${pos.y}')));
      }
    });
  });

  group('hexNeighbors', () {
    test('returns 6 distinct cells', () {
      for (final (col, row) in [(0, 0), (1, 0), (-1, 2), (2, -3)]) {
        final n = hexNeighbors(col, row);
        expect(n, hasLength(6));
        expect(n.toSet(), hasLength(6));
        expect(n, isNot(contains((col: col, row: row))));
      }
    });

    test('is symmetric across odd and even columns', () {
      // a in neighbors(b) <=> b in neighbors(a) for every cell in a patch
      // spanning negative/positive odd/even columns.
      for (var col = -2; col <= 2; col++) {
        for (var row = -2; row <= 2; row++) {
          for (final n in hexNeighbors(col, row)) {
            expect(
              hexNeighbors(n.col, n.row),
              contains((col: col, row: row)),
              reason: '($col,$row) -> (${n.col},${n.row}) not symmetric',
            );
          }
        }
      }
    });
  });

  group('nextHexPosition', () {
    test('empty field starts at the origin', () {
      final pos = nextHexPosition(const [], null, null, Dice(Random(1)));
      expect((pos.col, pos.row, pos.alreadyRevealed), (0, 0, false));
    });

    test('is deterministic under a seeded Dice', () {
      const hexes = [HexCell(col: 0, row: 0, envRow: 1)];
      final a = nextHexPosition(hexes, 0, 0, Dice(Random(42)));
      final b = nextHexPosition(hexes, 0, 0, Dice(Random(42)));
      expect(a, b);
    });

    test('20-step reveal walk stays adjacent and never duplicates cells', () {
      final dice = Dice(Random(99));
      final hexes = <HexCell>[];
      int? curCol, curRow;
      for (var i = 0; i < 20; i++) {
        final pos = nextHexPosition(hexes, curCol, curRow, dice);
        final existing =
            hexes.any((h) => h.col == pos.col && h.row == pos.row);
        if (pos.alreadyRevealed) {
          expect(existing, isTrue); // re-entry returns a known cell
        } else {
          expect(existing, isFalse); // fresh cells are distinct
          hexes.add(HexCell(col: pos.col, row: pos.row, envRow: 1));
        }
        if (curCol != null) {
          expect(hexNeighbors(curCol, curRow!),
              contains((col: pos.col, row: pos.row)),
              reason: 'step $i not adjacent to current');
        }
        curCol = pos.col;
        curRow = pos.row;
      }
    });

    test('fully surrounded current re-enters a revealed neighbor', () {
      final hexes = [
        const HexCell(col: 0, row: 0, envRow: 1),
        for (final n in hexNeighbors(0, 0))
          HexCell(col: n.col, row: n.row, envRow: 1),
      ];
      final pos = nextHexPosition(hexes, 0, 0, Dice(Random(3)));
      expect(pos.alreadyRevealed, isTrue);
      expect(hexNeighbors(0, 0), contains((col: pos.col, row: pos.row)));
    });
  });

  group('MapNotifier dungeon', () {
    test('addRoom persists, connects, and sets the current room', () async {
      final container = _container();
      addTearDown(container.dispose);
      final n = container.read(mapProvider.notifier);
      final dice = Dice(Random(11));
      final r0 = await n.addRoom(title: 'Entry', detail: 'd0', dice: dice);
      final r1 = await n.addRoom(title: 'Hall', detail: 'd1', dice: dice);
      final s = await container.read(mapProvider.future);
      expect(s.rooms.map((r) => r.id), [r0.id, r1.id]);
      expect((s.rooms[0].x, s.rooms[0].y), (0, 0));
      expect(s.corridors, [
        [r0.id, r1.id],
      ]);
      expect(s.currentRoomId, r1.id);
      // The second room sits in a free 4-neighbor cell of the first.
      final dx = (s.rooms[1].x - s.rooms[0].x).abs();
      final dy = (s.rooms[1].y - s.rooms[0].y).abs();
      expect(dx + dy, 1);
    });

    test('selectRoom moves current; unknown id is a no-op', () async {
      final container = _container();
      addTearDown(container.dispose);
      final n = container.read(mapProvider.notifier);
      final dice = Dice(Random(11));
      final r0 = await n.addRoom(title: 'A', detail: '', dice: dice);
      await n.addRoom(title: 'B', detail: '', dice: dice);
      await n.selectRoom(r0.id);
      expect((await container.read(mapProvider.future)).currentRoomId, r0.id);
      await n.selectRoom('nope');
      expect((await container.read(mapProvider.future)).currentRoomId, r0.id);
    });

    test('appendRoomDetail appends a linger line', () async {
      final container = _container();
      addTearDown(container.dispose);
      final n = container.read(mapProvider.notifier);
      final r0 = await n.addRoom(
          title: 'A', detail: 'base', dice: Dice(Random(11)));
      await n.appendRoomDetail(r0.id, 'linger line');
      final s = await container.read(mapProvider.future);
      expect(s.rooms.single.detail, 'base\nlinger line');
    });
  });

  group('MapNotifier hexes', () {
    test('revealHex seeds the origin then moves to an adjacent cell',
        () async {
      final container = _container();
      addTearDown(container.dispose);
      final n = container.read(mapProvider.notifier);
      final dice = Dice(Random(5));
      final h0 = await n.revealHex(envRow: 3, lost: false, dice: dice);
      expect((h0.col, h0.row), (0, 0));
      expect(h0.envRow, 3);
      var s = await container.read(mapProvider.future);
      expect((s.currentHexCol, s.currentHexRow), (0, 0));
      final h1 = await n.revealHex(envRow: 7, lost: true, dice: dice);
      s = await container.read(mapProvider.future);
      expect(s.hexes, hasLength(2));
      expect(hexNeighbors(0, 0), contains((col: h1.col, row: h1.row)));
      expect((s.currentHexCol, s.currentHexRow), (h1.col, h1.row));
      expect(s.hexes[1].envRow, 7);
      expect(s.hexes[1].lost, isTrue);
    });

    test('revealHex onto a fully revealed ring re-enters and updates lost',
        () async {
      final seeded = MapState(
        hexes: [
          const HexCell(col: 0, row: 0, envRow: 1),
          for (final n in hexNeighbors(0, 0))
            HexCell(col: n.col, row: n.row, envRow: 2),
        ],
        currentHexCol: 0,
        currentHexRow: 0,
      );
      final container = _container(mapJson: jsonEncode(seeded.toJson()));
      addTearDown(container.dispose);
      final n = container.read(mapProvider.notifier);
      final h = await n.revealHex(envRow: 9, lost: true, dice: Dice(Random(2)));
      final s = await container.read(mapProvider.future);
      expect(s.hexes, hasLength(7)); // nothing appended
      expect(h.envRow, 2); // existing cell keeps its environment
      expect(h.lost, isTrue); // but the lost flag updates
      expect((s.currentHexCol, s.currentHexRow), (h.col, h.row));
    });

    test('revealHexAt reveals manually without moving current; occupied no-op',
        () async {
      final container = _container();
      addTearDown(container.dispose);
      final n = container.read(mapProvider.notifier);
      await n.revealHexAt(2, 3, 5);
      var s = await container.read(mapProvider.future);
      expect(s.hexes.single.envRow, 5);
      expect(s.currentHexCol, isNull);
      expect(s.currentHexRow, isNull);
      await n.revealHexAt(2, 3, 9); // occupied: no-op
      s = await container.read(mapProvider.future);
      expect(s.hexes.single.envRow, 5);
    });
  });

  group('MapNotifier resets and persistence', () {
    Future<ProviderContainer> seeded() async {
      final container = _container();
      final n = container.read(mapProvider.notifier);
      final dice = Dice(Random(8));
      await n.addRoom(title: 'A', detail: '', dice: dice);
      await n.revealHex(envRow: 4, lost: false, dice: dice);
      return container;
    }

    test('resetDungeon clears the dungeon but keeps hexes', () async {
      final container = await seeded();
      addTearDown(container.dispose);
      await container.read(mapProvider.notifier).resetDungeon();
      final s = await container.read(mapProvider.future);
      expect(s.rooms, isEmpty);
      expect(s.corridors, isEmpty);
      expect(s.currentRoomId, isNull);
      expect(s.hexes, hasLength(1));
      expect((s.currentHexCol, s.currentHexRow), (0, 0));
    });

    test('resetHexes clears the hex field but keeps the dungeon', () async {
      final container = await seeded();
      addTearDown(container.dispose);
      await container.read(mapProvider.notifier).resetHexes();
      final s = await container.read(mapProvider.future);
      expect(s.hexes, isEmpty);
      expect(s.currentHexCol, isNull);
      expect(s.currentHexRow, isNull);
      expect(s.rooms, hasLength(1));
      expect(s.currentRoomId, s.rooms.single.id);
    });

    test('state persists under the session key across container rebuild',
        () async {
      final container = await seeded();
      container.dispose();
      final fresh = ProviderContainer(); // same mock prefs store
      addTearDown(fresh.dispose);
      final s = await fresh.read(mapProvider.future);
      expect(s.rooms.single.title, 'A');
      expect(s.hexes.single.envRow, 4);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('juice.map.v1.default'), contains('"title":"A"'));
    });
  });

  group('Campaign file map key', () {
    test('round-trips through encode/parse and rejects wrong shape', () {
      const s = MapState(
        rooms: [DungeonRoom(id: 'r0', x: 0, y: 0, title: 'Entry')],
        currentRoomId: 'r0',
        hexes: [HexCell(col: 0, row: 0, envRow: 6)],
        currentHexCol: 0,
        currentHexRow: 0,
      );
      final out = encodeCampaign(
        name: 'C1',
        savedAt: DateTime(2026, 6, 11),
        rawByKey: {'juice.map.v1': jsonEncode(s.toJson())},
      );
      final parsed = parseCampaign(out);
      expect(parsed.rawByKey['juice.map.v1'], contains('"title":"Entry"'));
      expect(parsed.rawByKey['juice.map.v1'], contains('"envRow":6'));
      expect(
        () => parseCampaign('{"app":"juice-oracle","schemaVersion":2,'
            '"name":"x","data":{"juice.map.v1":[1,2]}}'),
        throwsFormatException,
      );
    });
  });
}
