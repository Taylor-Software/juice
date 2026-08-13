import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('partyTool round-trips through JSON, omitted at default', () {
    const m = SessionMeta(id: 's1', name: 'A');
    expect(m.toJson().containsKey('partyTool'), isFalse);
    expect(m.enabledPartyTool, 'emulator');
    final m2 = SessionMeta.fromJson(
        {'id': 's1', 'name': 'A', 'partyTool': 'sidekick'});
    expect(m2.enabledPartyTool, 'sidekick');
    expect(m2.toJson()['partyTool'], 'sidekick');
  });

  test('setPartyTool persists and partyToolProvider reflects it', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sessions = await container.read(sessionsProvider.future);
    expect(container.read(partyToolProvider), 'emulator');
    await container
        .read(sessionsProvider.notifier)
        .setPartyTool(sessions.active, 'behavior');
    expect(container.read(partyToolProvider), 'behavior');
  });
}
