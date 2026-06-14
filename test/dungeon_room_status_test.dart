import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DungeonRoom status round-trips and defaults to empty', () {
    const r =
        DungeonRoom(id: 'r1', x: 0, y: 0, title: 'Vault', status: 'looted');
    final back = DungeonRoom.maybeFromJson(r.toJson())!;
    expect(back.status, 'looted');
    // Absent status -> empty (and not written to JSON).
    const bare = DungeonRoom(id: 'r2', x: 1, y: 1, title: 'Hall');
    expect(bare.toJson().containsKey('status'), isFalse);
    expect(DungeonRoom.maybeFromJson(bare.toJson())!.status, '');
  });

  test('kDungeonRoomStatuses covers the addon palette', () {
    expect(kDungeonRoomStatuses, contains('cleared'));
    expect(kDungeonRoomStatuses, contains('trapped'));
    expect(kDungeonRoomStatuses.toSet().length, kDungeonRoomStatuses.length);
  });

  test('setRoomStatus updates a room and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(sessionsProvider.future);
    final notifier = container.read(mapProvider.notifier);
    await container.read(mapProvider.future);

    final room = await notifier.addRoom(
        title: 'Crypt', detail: 'dusty', dice: Dice(Random(1)));
    await notifier.setRoomStatus(room.id, 'cleared');
    final s = await container.read(mapProvider.future);
    expect(s.rooms.firstWhere((r) => r.id == room.id).status, 'cleared');

    // Clearing with '' resets it.
    await notifier.setRoomStatus(room.id, '');
    final s2 = await container.read(mapProvider.future);
    expect(s2.rooms.firstWhere((r) => r.id == room.id).status, '');
  });
}
