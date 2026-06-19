import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rename changes the target name only', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(sessionsProvider.notifier);
    await c.read(sessionsProvider.future);
    await n.create('Beta');
    final id = c.read(sessionsProvider).value!.active;
    await n.rename(id, 'Renamed');
    var s = c.read(sessionsProvider).value!;
    expect(s.sessions.firstWhere((m) => m.id == id).name, 'Renamed');
    // no-op on blank / unknown
    await n.rename(id, '   ');
    await n.rename('nope', 'X');
    s = c.read(sessionsProvider).value!;
    expect(s.sessions.firstWhere((m) => m.id == id).name, 'Renamed');
  });

  test('create seeds genre/tone into the new session settings', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(sessionsProvider.notifier);
    await c.read(sessionsProvider.future);
    await n.create('Grim', genre: 'grimdark', tone: 'tense');
    final id = c.read(sessionsProvider).value!.active;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('juice.settings.v1.$id');
    expect(raw, isNotNull);
    final cs =
        CampaignSettings.fromJson(jsonDecode(raw!) as Map<String, dynamic>);
    expect(cs.genre, 'grimdark');
    expect(cs.tone, 'tense');

    await n.create('Plain');
    final id2 = c.read(sessionsProvider).value!.active;
    expect(prefs.getString('juice.settings.v1.$id2'), isNull);
  });

  test('create persists the chosen mode (default party)', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(sessionsProvider.notifier);
    await c.read(sessionsProvider.future);

    await n.create('GM game', mode: CampaignMode.gm);
    expect(c.read(sessionsProvider).value!.activeMeta.mode, CampaignMode.gm);

    await n.create('Default game');
    expect(c.read(sessionsProvider).value!.activeMeta.mode, CampaignMode.party);
  });
}
