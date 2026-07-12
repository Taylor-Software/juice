import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/state/providers.dart';

void main() {
  test('duplicateSetup copies systems/genre/edition/settings, not play state',
      () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1': '{"active":"src","sessions":[{"id":"src",'
          '"name":"Ironlands","systems":["ironsworn","juice"],'
          '"genre":"grim fantasy","dndEdition":"5.1"}]}',
      'juice.settings.v1.src':
          '{"genre":"grim fantasy","tone":"bleak","defaultOracle":"mythic"}',
      'juice.journal.v2.src': '[{"id":"e1","timestamp":'
          '"2026-07-11T10:00:00.000","title":"","body":"old story",'
          '"kind":"text"}]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);

    await c.read(sessionsProvider.notifier).duplicateSetup('src');

    final s = c.read(sessionsProvider).value!;
    expect(s.sessions, hasLength(2));
    final dup = s.sessions.last;
    expect(s.active, dup.id); // switched to the new campaign
    expect(dup.id, isNot('src'));
    expect(dup.name, 'Ironlands — new story');
    expect(dup.systems, ['ironsworn', 'juice']);
    expect(dup.genre, 'grim fantasy');
    expect(dup.dndEdition, '5.1');

    final prefs = await SharedPreferences.getInstance();
    // Settings blob copied…
    expect(prefs.getString('juice.settings.v1.${dup.id}'),
        prefs.getString('juice.settings.v1.src'));
    // …but play state is fresh (no journal key for the new id).
    expect(prefs.getString('juice.journal.v2.${dup.id}'), isNull);
  });

  test('duplicateSetup no-ops on an unknown id', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"a","sessions":[{"id":"a","name":"One"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    await c.read(sessionsProvider.notifier).duplicateSetup('nope');
    expect(c.read(sessionsProvider).value!.sessions, hasLength(1));
  });
}
