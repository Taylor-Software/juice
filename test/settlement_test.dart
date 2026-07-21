import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/state/providers.dart';

Oracle _oracle([int seed = 3]) => Oracle(
    OracleData(jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>),
    Dice(Random(seed)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('models', () {
    test('Building round-trips and omits empty fields', () {
      const b = Building(id: 'b1', name: 'The Anchor', type: 'Tavern');
      final back = Building.maybeFromJson(b.toJson());
      expect(back!.name, 'The Anchor');
      expect(back.type, 'Tavern');
      expect(const Building(id: 'b2').toJson().containsKey('name'), isFalse);
    });

    test('SettlementSite round-trips buildings + anchor', () {
      const s = SettlementSite(
        id: 's1',
        name: 'High Brook',
        kind: 'Town',
        buildings: [Building(id: 'b1', name: 'Inn')],
        anchorHexCol: 2,
        anchorHexRow: 3,
      );
      final back = SettlementSite.maybeFromJson(s.toJson())!;
      expect(back.name, 'High Brook');
      expect(back.kind, 'Town');
      expect(back.buildings.single.name, 'Inn');
      expect(back.hasAnchor, isTrue);
      expect((back.anchorHexCol, back.anchorHexRow), (2, 3));
    });

    test('MapState settlements round-trip; omitted when empty', () {
      const m = MapState(settlements: [
        SettlementSite(id: 's1', name: 'A'),
      ], activeSettlementId: 's1');
      final back = MapState.fromJson(m.toJson());
      expect(back.settlements.single.name, 'A');
      expect(back.activeSettlementId, 's1');
      expect(const MapState().toJson().containsKey('settlements'), isFalse);
    });

    test('settlementAnchoredAt finds by hex', () {
      const m = MapState(settlements: [
        SettlementSite(id: 's1', name: 'A', anchorHexCol: 1, anchorHexRow: 1),
      ]);
      expect(m.settlementAnchoredAt(1, 1)?.id, 's1');
      expect(m.settlementAnchoredAt(9, 9), isNull);
    });
  });

  group('MapNotifier settlements', () {
    Future<ProviderContainer> container() async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(sessionsProvider.future);
      await c.read(mapProvider.future);
      return c;
    }

    test('generateSettlement adds a named town with buildings, active',
        () async {
      final c = await container();
      final n = c.read(mapProvider.notifier);
      final id = await n.generateSettlement(_oracle(), buildingCount: 4);
      final s = await c.read(mapProvider.future);
      expect(s.settlements.single.id, id);
      expect(s.activeSettlementId, id);
      expect(s.settlements.single.name, isNotEmpty);
      expect(s.settlements.single.buildings, hasLength(4));
      expect(s.settlements.single.kind, 'Town');
    });

    test('building CRUD', () async {
      final c = await container();
      final n = c.read(mapProvider.notifier);
      final sid = await n.addSettlement(name: 'Hollow');
      final bid = await n.addBuilding(sid, name: 'Smithy');
      var s = await c.read(mapProvider.future);
      expect(s.settlements.single.buildings.single.name, 'Smithy');
      await n.updateBuilding(
          sid, Building(id: bid, name: 'Grand Smithy', type: 'Forge'));
      s = await c.read(mapProvider.future);
      expect(s.settlements.single.buildings.single.name, 'Grand Smithy');
      expect(s.settlements.single.buildings.single.type, 'Forge');
      await n.removeBuilding(sid, bid);
      s = await c.read(mapProvider.future);
      expect(s.settlements.single.buildings, isEmpty);
    });

    test('anchor/unanchor + remove reassigns active', () async {
      final c = await container();
      final n = c.read(mapProvider.notifier);
      final a = await n.addSettlement(name: 'A');
      await n.anchorSettlementHere(_oracle(), 5, 6);
      var s = await c.read(mapProvider.future);
      // First settlement had no anchor -> got anchored (no new one created).
      expect(s.settlements, hasLength(1));
      expect(s.settlementAnchoredAt(5, 6)?.id, a);
      await n.unanchorSettlement(a);
      s = await c.read(mapProvider.future);
      expect(s.settlements.single.hasAnchor, isFalse);

      final b = await n.addSettlement(name: 'B');
      await n.switchSettlement(b);
      await n.removeSettlement(b);
      s = await c.read(mapProvider.future);
      expect(s.settlements.single.id, a);
      expect(s.activeSettlementId, a);
    });
  });
}
