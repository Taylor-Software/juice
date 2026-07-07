/// Tracked monster factions for a classic dungeon. Pure model + assignment.
/// The zine: on re-encountering an already-seen organized type there is a 5/6
/// chance they belong to an existing faction of that type, else a new one.
library;

import '../dice.dart';

class DungeonFaction {
  const DungeonFaction(
      {required this.id,
      required this.name,
      required this.monsterType,
      required this.roomIds});
  final String id;
  final String name;
  final String monsterType;
  final List<String> roomIds;

  DungeonFaction addRoom(String roomId) => DungeonFaction(
      id: id,
      name: name,
      monsterType: monsterType,
      roomIds: [...roomIds, roomId]);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'type': monsterType, 'rooms': roomIds};
  factory DungeonFaction.fromJson(Map<String, dynamic> j) => DungeonFaction(
        id: j['id'] as String,
        name: j['name'] as String,
        monsterType: j['type'] as String,
        roomIds: [
          for (final r in (j['rooms'] as List? ?? const [])) r as String
        ],
      );
}

class FactionRegistry {
  const FactionRegistry({this.factions = const []});
  final List<DungeonFaction> factions;

  List<DungeonFaction> forType(String type) =>
      factions.where((f) => f.monsterType == type).toList();

  Map<String, dynamic> toJson() => {
        'factions': [for (final f in factions) f.toJson()]
      };
  factory FactionRegistry.fromJson(dynamic j) {
    if (j is! Map) return const FactionRegistry();
    return FactionRegistry(factions: [
      for (final f in (j['factions'] as List? ?? const []))
        DungeonFaction.fromJson((f as Map).cast<String, dynamic>())
    ]);
  }
}

/// Resolve the faction for an organized [monsterType] appearing in [roomId].
/// Returns the extended registry and the assigned faction. Names are drawn from
/// [namePool]; when exhausted, a numbered fallback keeps them unique.
(FactionRegistry, DungeonFaction?) assignFaction(FactionRegistry reg,
    String monsterType, String roomId, List<String> namePool, Dice dice) {
  final existing = reg.forType(monsterType);
  DungeonFaction faction;
  List<DungeonFaction> next;
  if (existing.isNotEmpty && dice.dN(6) <= 5) {
    final chosen = existing[dice.dN(existing.length) - 1];
    faction = chosen.addRoom(roomId);
    next = [for (final f in reg.factions) f.id == chosen.id ? faction : f];
  } else {
    final used = reg.factions.map((f) => f.name).toSet();
    final free = namePool.where((n) => !used.contains(n)).toList();
    final name = free.isNotEmpty
        ? free[dice.dN(free.length) - 1]
        : '$monsterType Band ${reg.factions.length + 1}';
    faction = DungeonFaction(
        id: 'fac${reg.factions.length + 1}',
        name: name,
        monsterType: monsterType,
        roomIds: [roomId]);
    next = [...reg.factions, faction];
  }
  return (FactionRegistry(factions: next), faction);
}
