import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juice_oracle/state/interpreter.dart';

import 'fake_interpreter.dart';

void main() {
  test('InterpreterStatus equality + progress default', () {
    const a = InterpreterStatus(InterpreterPhase.installing, progress: 40);
    expect(a.phase, InterpreterPhase.installing);
    expect(a.progress, 40);
    expect(const InterpreterStatus(InterpreterPhase.ready).progress, 0);
    expect(const InterpreterStatus(InterpreterPhase.error, message: 'x').message,
        'x');
  });

  test('interpreterServiceProvider is overridable with the fake', () {
    final fake = FakeInterpreterService();
    final c = ProviderContainer(overrides: [
      interpreterServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    expect(c.read(interpreterServiceProvider), same(fake));
  });
}
