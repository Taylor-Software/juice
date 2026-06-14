import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  test('launcher gate defaults shown, dismiss hides it', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(launcherGateProvider), isTrue);
    c.read(launcherGateProvider.notifier).dismiss();
    expect(c.read(launcherGateProvider), isFalse);
  });
}
