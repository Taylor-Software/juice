import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('add with stage, setStage promotes a rumor', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(threadsProvider.notifier);

    final id = await notifier.addReturningId('Strange lights',
        stage: ThreadStage.rumor);
    var threads = await container.read(threadsProvider.future);
    expect(threads.single.stage, ThreadStage.rumor);

    await notifier.setStage(id, ThreadStage.active);
    threads = await container.read(threadsProvider.future);
    expect(threads.single.stage, ThreadStage.active);
  });

  test('toggleOpen flips active<->done and closes a rumor', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(threadsProvider.notifier);

    final id = await notifier.addReturningId('Lead', stage: ThreadStage.rumor);
    await notifier.toggleOpen(id);
    var threads = await container.read(threadsProvider.future);
    expect(threads.single.stage, ThreadStage.done);

    await notifier.toggleOpen(id);
    threads = await container.read(threadsProvider.future);
    expect(threads.single.stage, ThreadStage.active);
  });
}
