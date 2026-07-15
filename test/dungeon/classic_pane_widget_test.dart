import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dungeon/faction.dart';
import 'package:juice_oracle/engine/dungeon/footprint.dart';
import 'package:juice_oracle/engine/dungeon/tables.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/map_screen.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final data = OracleData(
      jsonDecode(File('assets/oracle_data.json').readAsStringSync())
          as Map<String, dynamic>);
  // File-fixture override: rootBundle loads hang widget tests (repo recipe).
  final dungeonTables = DungeonTables.fromJson(
      jsonDecode(File('assets/dungeon_data.json').readAsStringSync())
          as Map<String, dynamic>);

  Future<ProviderContainer> pump(WidgetTester tester,
      {bool classic = true}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1': jsonEncode({
        'active': 'default',
        'sessions': [
          {
            'id': 'default',
            'name': 'C1',
            if (classic) 'systems': ['juice', 'classic-dungeon'],
          }
        ],
      }),
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [
          dungeonDataProvider.overrideWith((ref) async => dungeonTables),
        ],
        child: MaterialApp(
            home: Scaffold(body: DungeonMapPane(oracle: Oracle(data))))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(DungeonMapPane)));
  }

  testWidgets('classic mode shows Enter button instead of New room',
      (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('classic-enter')), findsOneWidget);
    expect(find.byKey(const Key('new-room')), findsNothing);
  });

  testWidgets('base mode unchanged: New room, no Enter', (tester) async {
    await pump(tester, classic: false);
    expect(find.byKey(const Key('new-room')), findsOneWidget);
    expect(find.byKey(const Key('classic-enter')), findsNothing);
    expect(find.byKey(const Key('classic-enter-cave')), findsNothing);
  });

  testWidgets(
      'enter cave: classic-enter-cave creates a cave level with an '
      'entrance room', (tester) async {
    final container = await pump(tester);
    expect(find.byKey(const Key('classic-enter')), findsOneWidget);
    expect(find.byKey(const Key('classic-enter-cave')), findsOneWidget);
    await tester.tap(find.byKey(const Key('classic-enter-cave')));
    await tester.pumpAndSettle();
    final map = container.read(mapProvider).requireValue;
    expect(map.levels.single.branch, 'cave');
    expect(map.rooms, hasLength(1));
    expect(map.rooms.single.roomType, anyOf('tunnel', 'cave'));
    expect(find.byKey(const Key('classic-level-header')), findsOneWidget);
    expect(find.textContaining('Depth 1'), findsOneWidget);
  });

  testWidgets('descend button creates and switches to depth 2', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.byKey(const Key('classic-enter')));
    await tester.pumpAndSettle();
    final notifier = container.read(mapProvider.notifier);
    final s = container.read(mapProvider).requireValue;
    await notifier.save(s.copyWith(rooms: [
      ...s.rooms,
      const DungeonRoom(id: 'st', x: 7, y: 7, title: 'Stairs', levelDelta: -1),
    ], currentRoomId: 'st'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('classic-descend')), findsOneWidget);
    expect(find.text('Descend'), findsOneWidget);
    await tester.tap(find.byKey(const Key('classic-descend')));
    await tester.pumpAndSettle();
    var map = container.read(mapProvider).requireValue;
    expect(map.levels, hasLength(2));
    expect(map.levels[map.activeLevel].depth, 2);
    expect(find.byKey(const Key('classic-level-chip-1')), findsOneWidget);
    expect(find.byKey(const Key('classic-level-chip-2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('classic-level-chip-1')));
    await tester.pumpAndSettle();
    map = container.read(mapProvider).requireValue;
    expect(map.levels[map.activeLevel].depth, 1);
  });

  testWidgets('crossover caption shows', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.byKey(const Key('classic-enter')));
    await tester.pumpAndSettle();
    final notifier = container.read(mapProvider.notifier);
    final s = container.read(mapProvider).requireValue;
    await notifier.save(s.copyWith(rooms: [
      ...s.rooms,
      const DungeonRoom(
          id: 'xr', x: 7, y: 7, title: 'Sinkhole', crossTo: 'cave'),
    ], currentRoomId: 'xr'));
    await tester.pumpAndSettle();
    expect(find.textContaining('lead to the caves'), findsOneWidget);
  });

  testWidgets('Enter creates an entrance room with open doors', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.byKey(const Key('classic-enter')));
    await tester.pumpAndSettle();
    final map = container.read(mapProvider).requireValue;
    expect(map.rooms, hasLength(1));
    expect(map.rooms.single.roomType, isNotNull);
    expect(map.rooms.single.doors,
        everyElement(predicate<DoorEdge>((d) => d.kind == DoorKind.open)));
    // Enter button gone once the dungeon exists
    expect(find.byKey(const Key('classic-enter')), findsNothing);
  });

  testWidgets('door-tap explores a new mated room', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.byKey(const Key('classic-enter')));
    await tester.pumpAndSettle();
    var map = container.read(mapProvider).requireValue;
    final r0 = map.rooms.single;
    final d0 = r0.doors.first;

    // tap the door marker on the canvas
    final canvas = find.byKey(const Key('dungeon-canvas'));
    final topLeft = tester.getTopLeft(canvas);
    final rooms = map.rooms;
    final p =
        doorMarkerCenter(r0, d0, roomsMinX(rooms), roomsMinY(rooms), 56.0);
    await tester.tapAt(topLeft + p);
    await tester.pumpAndSettle();

    map = container.read(mapProvider).requireValue;
    expect(map.rooms, hasLength(2));
    expect(map.corridors, hasLength(1));
  });

  testWidgets('dungeon reset clears the faction registry', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.byKey(const Key('classic-enter')));
    await tester.pumpAndSettle();
    // seed a fake faction directly, then reset the dungeon via the UI
    await container.read(dungeonFactionsProvider.future);
    await container
        .read(dungeonFactionsProvider.notifier)
        .save(const FactionRegistry(factions: [
          DungeonFaction(
              id: 'f1', name: 'X', monsterType: 'Goblins', roomIds: ['r'])
        ]));
    // Reset is a secondary control, folded behind the chrome's Tools toggle.
    await tester.tap(find.byKey(const Key('map-tools-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dungeon-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    final reg = container.read(dungeonFactionsProvider).requireValue;
    expect(reg.factions, isEmpty);
    expect(container.read(mapProvider).requireValue.rooms, isEmpty);
  });
}
