import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> container({String? mapJson}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      if (mapJson != null) 'juice.map.v1.default': mapJson,
    });
    return ProviderContainer();
  }

  test('setHexTerrain + addHexPoi annotate an existing hex', () async {
    final c = await container(
        mapJson: jsonEncode({
      'hexes': [
        {'col': 0, 'row': 0, 'envRow': 3}
      ],
    }));
    await c.read(mapProvider.future);
    await c.read(mapProvider.notifier).setHexTerrain(0, 0, 'forest');
    await c.read(mapProvider.notifier).addHexPoi(0, 0, 7);
    await c.read(mapProvider.notifier).addHexPoi(0, 0, 7); // no duplicate
    final h = c.read(mapProvider).value!.hexes.single;
    expect(h.terrain, 'forest');
    expect(h.pois, [7]);
  });
}
