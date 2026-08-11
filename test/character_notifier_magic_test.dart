import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/state/magic_controller.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
      'enableMagic creates a pg.Character and links polarityId, disableMagic undoes it',
      () async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
          '{"active":"c1","sessions":[{"id":"c1","name":"Test"}]}',
      'loreseer.characters.v1.c1':
          '[{"id":"ch1","name":"Ash","stats":[],"tracks":[],"tags":[]}]',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(charactersProvider.future);
    final ctrl = container.read(charactersProvider.notifier);

    await ctrl.enableMagic('ch1');
    var chars = await container.read(charactersProvider.future);
    final linked = chars.single.polarityId;
    expect(linked, isNotNull);
    var lib = await container.read(magicProvider.future);
    expect(lib.characters.single.id, linked);
    expect(lib.characters.single.name, 'Ash');

    await ctrl.disableMagic('ch1');
    chars = await container.read(charactersProvider.future);
    expect(chars.single.polarityId, isNull);
    lib = await container.read(magicProvider.future);
    expect(lib.characters, isEmpty);
  });
}
