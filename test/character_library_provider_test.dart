import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('add/remove/rename round-trip and persist app-globally', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(characterLibraryProvider.notifier);

    await notifier.add(const Character(id: 'a', name: 'Brakka'));
    await notifier.add(const Character(id: 'b', name: 'Yeva'));
    expect((await container.read(characterLibraryProvider.future)).length, 2);

    await notifier.rename('a', 'Brakka the Bold');
    var list = await container.read(characterLibraryProvider.future);
    expect(list.firstWhere((c) => c.id == 'a').name, 'Brakka the Bold');

    await notifier.remove('b');
    list = await container.read(characterLibraryProvider.future);
    expect(list.single.id, 'a');

    // Key is app-global: NOT suffixed with a session id.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('loreseer.charlibrary.v1'), isNotNull);
  });

  test('corrupt storage degrades to empty, corrupt row skipped', () async {
    SharedPreferences.setMockInitialValues(
        {'loreseer.charlibrary.v1': '[{"id":"ok","name":"Ok"},{"bad":1}]'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final list = await container.read(characterLibraryProvider.future);
    expect(list.single.id, 'ok');
  });

  test('insertAt restores a deleted row for undo', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(characterLibraryProvider.notifier);
    await notifier.add(const Character(id: 'a', name: 'A'));
    await notifier.add(const Character(id: 'b', name: 'B'));
    await notifier.remove('a');
    await notifier.insertAt(0, const Character(id: 'a', name: 'A'));
    final list = await container.read(characterLibraryProvider.future);
    expect(list.map((c) => c.id).toList(), ['a', 'b']);
  });
}
