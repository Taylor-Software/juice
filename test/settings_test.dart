import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CampaignSettings json round-trip + defaults', () {
    const s = CampaignSettings(genre: 'grimdark', tone: 'tense');
    final back = CampaignSettings.fromJson(s.toJson());
    expect(back.genre, 'grimdark');
    expect(back.tone, 'tense');
    expect(const CampaignSettings().genre, '');
    expect(CampaignSettings.fromJson(const {}).tone, '');
  });

  test('emulatorSystem defaults to both and round-trips; omitted when both',
      () {
    expect(const CampaignSettings().emulatorSystem, 'both');
    expect(const CampaignSettings().toJson().containsKey('emulatorSystem'),
        isFalse);
    const s = CampaignSettings(emulatorSystem: 'pet');
    expect(s.toJson()['emulatorSystem'], 'pet');
    expect(CampaignSettings.fromJson(s.toJson()).emulatorSystem, 'pet');
    expect(CampaignSettings.fromJson(const {}).emulatorSystem, 'both');
  });

  test('settings persist per session and reload', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c1 = ProviderContainer();
    addTearDown(c1.dispose);
    await c1.read(settingsProvider.future);
    await c1
        .read(settingsProvider.notifier)
        .save(const CampaignSettings(genre: 'noir', tone: 'wry'));

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    final loaded = await c2.read(settingsProvider.future);
    expect(loaded.genre, 'noir');
    expect(loaded.tone, 'wry');
  });

  test('settings are isolated per session and survive switching back',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(sessionsProvider.future);

    await container.read(settingsProvider.future);
    await container
        .read(settingsProvider.notifier)
        .save(const CampaignSettings(genre: 'noir', tone: 'wry'));

    await container.read(sessionsProvider.notifier).create('Second');
    final fresh = await container.read(settingsProvider.future);
    expect(fresh.genre, '');
    expect(fresh.tone, '');

    await container.read(sessionsProvider.notifier).switchTo('default');
    final restored = await container.read(settingsProvider.future);
    expect(restored.genre, 'noir');
    expect(restored.tone, 'wry');
  });

  test('save before build completes does not throw', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // No await of the future first: the _ready house rule.
    await c
        .read(settingsProvider.notifier)
        .save(const CampaignSettings(genre: 'g', tone: 't'));
    expect((await c.read(settingsProvider.future)).genre, 'g');
  });
}
