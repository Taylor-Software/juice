import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/state/providers.dart';

// Simple int provider to stand in for "how many sessions exist".
final _sessionCountProvider = StateProvider<int>((ref) => 1);

/// Minimal host that mirrors the launcher's welcome-gate condition.
Widget _testHost({required bool welcomeSeen, required int sessionCount}) =>
    ProviderScope(
      overrides: [
        welcomeSeenProvider.overrideWith(() => _FakeWelcomeSeen(welcomeSeen)),
        _sessionCountProvider.overrideWith((ref) => sessionCount),
      ],
      child: const MaterialApp(home: _WelcomeSandbox()),
    );

/// Mirrors the launcher gate: show when !seen && count == 1.
class _WelcomeSandbox extends ConsumerWidget {
  const _WelcomeSandbox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(welcomeSeenProvider).valueOrNull ?? false;
    final count = ref.watch(_sessionCountProvider);
    final show = !seen && count == 1;
    return Scaffold(
      body: Column(
        children: [
          if (show)
            Card(
              key: const Key('welcome-card'),
              child: Column(
                children: [
                  const Text('Welcome'),
                  TextButton(
                    key: const Key('welcome-dismiss'),
                    onPressed: () =>
                        ref.read(welcomeSeenProvider.notifier).markSeen(),
                    child: const Text('Got it'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FakeWelcomeSeen extends WelcomeSeenNotifier {
  _FakeWelcomeSeen(this._initial);
  final bool _initial;

  @override
  Future<bool> build() async => _initial;

  @override
  Future<void> markSeen() async => state = const AsyncData(true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('welcome card shown on first run (1 campaign, not seen)',
      (tester) async {
    await tester.pumpWidget(_testHost(welcomeSeen: false, sessionCount: 1));
    await tester.pump();
    expect(find.byKey(const Key('welcome-card')), findsOneWidget);
  });

  testWidgets('welcome card hidden after dismiss', (tester) async {
    await tester.pumpWidget(_testHost(welcomeSeen: false, sessionCount: 1));
    await tester.pump();
    await tester.tap(find.byKey(const Key('welcome-dismiss')));
    await tester.pump();
    expect(find.byKey(const Key('welcome-card')), findsNothing);
  });

  testWidgets('welcome card hidden when already seen', (tester) async {
    await tester.pumpWidget(_testHost(welcomeSeen: true, sessionCount: 1));
    await tester.pump();
    expect(find.byKey(const Key('welcome-card')), findsNothing);
  });

  testWidgets('welcome card hidden when multiple campaigns exist',
      (tester) async {
    await tester.pumpWidget(_testHost(welcomeSeen: false, sessionCount: 2));
    await tester.pump();
    expect(find.byKey(const Key('welcome-card')), findsNothing);
  });
}
