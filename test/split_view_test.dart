import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('split view defaults false, toggles and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(splitViewProvider.future), isFalse);
    await c.read(splitViewProvider.notifier).toggle();
    expect(c.read(splitViewProvider).value, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('juice.splitview.v1'), isTrue);
  });
}
