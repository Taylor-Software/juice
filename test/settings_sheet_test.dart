import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/settings_sheet.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_cloud_key_store.dart';
import 'fake_interpreter.dart';

Future<FakeInterpreterService> pump(WidgetTester tester,
    {required InterpreterStatus status,
    bool enabled = false,
    FakeCloudKeyStore? cloudStore}) async {
  SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': enabled});
  final fake = FakeInterpreterService(initial: status);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      interpreterServiceProvider.overrideWithValue(fake),
      cloudKeyStoreProvider
          .overrideWithValue(cloudStore ?? FakeCloudKeyStore()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSettingsSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('unsupported: shows not-available, no toggle', (tester) async {
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.unsupported));
    expect(find.textContaining("isn't available"), findsOneWidget);
    expect(find.byKey(const Key('settings-ai-toggle')), findsNothing);
  });

  testWidgets('supported + off: toggle present, no status block',
      (tester) async {
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.needsDownload));
    expect(find.byKey(const Key('settings-ai-toggle')), findsOneWidget);
    expect(find.byKey(const Key('settings-ai-download')), findsNothing);
  });

  testWidgets('enabling the toggle calls setEnabled(true)', (tester) async {
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.needsDownload));
    await tester.tap(find.byKey(const Key('settings-ai-toggle')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('juice.ai_enabled.v1'), isTrue);
  });

  testWidgets('enabled + needsDownload shows Download -> warmUp',
      (tester) async {
    final fake = await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.needsDownload),
        enabled: true);
    await tester.tap(find.byKey(const Key('settings-ai-download')));
    await tester.pumpAndSettle();
    expect(fake.warmUpCalls, 1);
  });

  testWidgets('enabled + installing shows progress', (tester) async {
    await pump(tester,
        status:
            const InterpreterStatus(InterpreterPhase.installing, progress: 42),
        enabled: true);
    expect(find.textContaining('42%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('enabled + ready shows Ready', (tester) async {
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.ready), enabled: true);
    expect(find.textContaining('Ready'), findsOneWidget);
  });

  testWidgets(
      'cloud interpretation block shows even when on-device is unsupported',
      (tester) async {
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.unsupported));
    expect(find.textContaining("isn't available"), findsOneWidget);
    expect(find.text('Cloud interpretation'), findsOneWidget);
    expect(find.byKey(const Key('settings-cloud-key-field')), findsOneWidget);
  });

  testWidgets('saving a key enables the cloud toggle', (tester) async {
    final cloudStore = FakeCloudKeyStore();
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.needsDownload),
        cloudStore: cloudStore);
    final toggleBefore = tester
        .widget<SwitchListTile>(find.byKey(const Key('settings-cloud-toggle')));
    expect(toggleBefore.onChanged, isNull);

    await tester.enterText(
        find.byKey(const Key('settings-cloud-key-field')), 'sk-ant-test');
    await tester.tap(find.byKey(const Key('settings-cloud-key-save')));
    await tester.pumpAndSettle();

    expect(cloudStore.writeCalls, 1);
    final toggleAfter = tester
        .widget<SwitchListTile>(find.byKey(const Key('settings-cloud-toggle')));
    expect(toggleAfter.onChanged, isNotNull);
  });
}
