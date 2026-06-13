import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('kAllSystems is the four optional systems', () {
    expect(kAllSystems, {'juice', 'mythic', 'ironsworn', 'party'});
  });

  test('legacy meta (no systems) enables all', () {
    final m = SessionMeta.fromJson({'id': 'a', 'name': 'A'});
    expect(m.systems, isNull);
    expect(m.enabledSystems, kAllSystems);
  });

  test('explicit systems round-trip and drive enabledSystems', () {
    const m = SessionMeta(id: 'a', name: 'A', systems: ['juice', 'mythic']);
    final back = SessionMeta.fromJson(m.toJson());
    expect(back.systems, ['juice', 'mythic']);
    expect(back.enabledSystems, {'juice', 'mythic'});
  });

  test('empty systems means only core (no optional systems)', () {
    const m = SessionMeta(id: 'a', name: 'A', systems: []);
    expect(m.enabledSystems, isEmpty);
  });

  test('toJson omits systems when null (byte-stable legacy)', () {
    expect(
        const SessionMeta(id: 'a', name: 'A').toJson().containsKey('systems'),
        isFalse);
  });

  group('SessionsNotifier.create with systems', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('create with explicit systems stores that set', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);

      await container
          .read(sessionsProvider.notifier)
          .create('X', systems: {'juice'});
      final s = await container.read(sessionsProvider.future);
      expect(s.activeMeta.name, 'X');
      expect(s.activeMeta.enabledSystems, {'juice'});
    });

    test('create with no systems arg stores null (all enabled)', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);

      await container.read(sessionsProvider.notifier).create('Y');
      final s = await container.read(sessionsProvider.future);
      expect(s.activeMeta.name, 'Y');
      expect(s.activeMeta.systems, isNull);
      expect(s.activeMeta.enabledSystems, kAllSystems);
    });
  });
}
