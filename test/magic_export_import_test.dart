import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/state/magic_controller.dart';
import 'package:loreseer/state/providers.dart';
import 'package:polarity_grammar/polarity_grammar.dart' as pg;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('loreseer.magic.v1 data survives export then import into a new session',
      () async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
          '{"active":"c1","sessions":[{"id":"c1","name":"Source"}]}',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(sessionsProvider.future);
    await container.read(magicProvider.future);
    await container.read(magicProvider.notifier).upsertCharacter(
          const pg.Character(
              id: 'pg-1', name: 'Ash', baseMana: 4, currentMana: 4),
        );

    expect(sessionScopedKeys.contains('loreseer.magic.v1'), isTrue);

    final exported =
        await container.read(sessionsProvider.notifier).exportActiveFile();
    expect(exported.ext, 'json'); // no blob images referenced, so plain JSON
    final decoded =
        jsonDecode(utf8.decode(exported.bytes)) as Map<String, dynamic>;
    expect((decoded['data'] as Map)['loreseer.magic.v1'], isNotNull);

    await container
        .read(sessionsProvider.notifier)
        .importCampaignData(exported.bytes);
    final sessions = await container.read(sessionsProvider.future);
    expect(sessions.sessions.length,
        2); // original 'c1' + the freshly imported one
    final importedLib = await container.read(magicProvider.future);
    expect(importedLib.characters.single.name, 'Ash');
  });
}
