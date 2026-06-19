import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionMeta.mode', () {
    test('absent mode defaults to party', () {
      final m = SessionMeta.fromJson({'id': 'a', 'name': 'A'});
      expect(m.mode, CampaignMode.party);
    });
    test('gm mode round-trips', () {
      const m = SessionMeta(id: 'a', name: 'A', mode: CampaignMode.gm);
      final back = SessionMeta.fromJson(m.toJson());
      expect(back.mode, CampaignMode.gm);
    });
    test('party mode omitted from json (default)', () {
      const m = SessionMeta(id: 'a', name: 'A');
      expect(m.toJson().containsKey('mode'), isFalse);
    });
  });

  group('modeProvider + setMode', () {
    test('reads the active campaign mode (default party)', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(sessionsProvider.future);
      expect(c.read(modeProvider), CampaignMode.party);
    });

    test('rename preserves mode', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(sessionsProvider.future);
      await c
          .read(sessionsProvider.notifier)
          .setMode('default', CampaignMode.gm);
      await c.read(sessionsProvider.notifier).rename('default', 'Renamed');
      final meta = c.read(sessionsProvider).valueOrNull?.activeMeta;
      expect(meta?.mode, CampaignMode.gm);
      expect(meta?.name, 'Renamed');
    });

    test('setMode flips + persists + preserves systems', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1","systems":["ironsworn"]}]}',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(sessionsProvider.future);
      await c
          .read(sessionsProvider.notifier)
          .setMode('default', CampaignMode.gm);
      expect(c.read(modeProvider), CampaignMode.gm);
      // systems untouched:
      expect(
          c
              .read(sessionsProvider)
              .valueOrNull
              ?.activeMeta
              .enabledSystems
              .contains('ironsworn'),
          isTrue);
      // persisted:
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('juice.sessions.v1'), contains('"mode":"gm"'));
    });
  });
}
