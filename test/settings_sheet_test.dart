import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/settings_sheet.dart';
import 'package:juice_oracle/state/auto_backup.dart';
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

  // The settings sheet owns the AI gate, the one billable secret, and the
  // reading-size control — it was the largest genuinely-testable coverage gap.

  testWidgets('a blank key is not written', (tester) async {
    final cloudStore = FakeCloudKeyStore();
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.needsDownload),
        cloudStore: cloudStore);
    await tester.enterText(
        find.byKey(const Key('settings-cloud-key-field')), '   ');
    await tester.tap(find.byKey(const Key('settings-cloud-key-save')));
    await tester.pumpAndSettle();
    expect(cloudStore.writeCalls, 0);
  });

  testWidgets('the key field is obscured', (tester) async {
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.needsDownload));
    final field = tester
        .widget<TextField>(find.byKey(const Key('settings-cloud-key-field')));
    expect(field.obscureText, isTrue,
        reason: 'an API key must not be shoulder-readable');
  });

  testWidgets('no Clear button until a key exists', (tester) async {
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.needsDownload));
    expect(find.byKey(const Key('settings-cloud-key-clear')), findsNothing);
  });

  testWidgets('clearing a key wipes it and disables cloud interpretation',
      (tester) async {
    final cloudStore = FakeCloudKeyStore();
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.needsDownload),
        cloudStore: cloudStore);
    await tester.enterText(
        find.byKey(const Key('settings-cloud-key-field')), 'sk-ant-test');
    await tester.tap(find.byKey(const Key('settings-cloud-key-save')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-cloud-key-clear')));
    await tester.pumpAndSettle();

    expect(cloudStore.clearCalls, 1);
    final toggle = tester
        .widget<SwitchListTile>(find.byKey(const Key('settings-cloud-toggle')));
    expect(toggle.onChanged, isNull, reason: 'no key, no cloud');
    expect(toggle.value, isFalse);
  });

  testWidgets('the key field is emptied after a successful save',
      (tester) async {
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.needsDownload));
    await tester.enterText(
        find.byKey(const Key('settings-cloud-key-field')), 'sk-ant-test');
    await tester.tap(find.byKey(const Key('settings-cloud-key-save')));
    await tester.pumpAndSettle();
    final field = tester
        .widget<TextField>(find.byKey(const Key('settings-cloud-key-field')));
    expect(field.controller!.text, isEmpty,
        reason: 'the secret should not linger in the visible field');
  });

  testWidgets('reading size starts at 100% with no reset offered',
      (tester) async {
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.needsDownload));
    final slider =
        tester.widget<Slider>(find.byKey(const Key('settings-text-scale')));
    expect(slider.value, 1.0);
    expect(find.byKey(const Key('settings-text-scale-reset')), findsNothing);
  });

  testWidgets('changing reading size offers a reset that restores 100%',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'juice.ai_enabled.v1': false, 'juice.text_scale.v1': 1.3});
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.needsDownload));
    late ProviderContainer container;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        interpreterServiceProvider.overrideWithValue(fake),
        cloudKeyStoreProvider.overrideWithValue(FakeCloudKeyStore()),
      ],
      child: MaterialApp(
        home: Scaffold(body: Builder(builder: (context) {
          container = ProviderScope.containerOf(context);
          return TextButton(
              onPressed: () => showSettingsSheet(context),
              child: const Text('open'));
        })),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-text-scale-reset')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-text-scale-reset')));
    await tester.pumpAndSettle();
    expect(container.read(textScaleProvider).valueOrNull, 1.0);
  });

  testWidgets('sources and bestiary entry points are present', (tester) async {
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.needsDownload));
    expect(find.byKey(const Key('settings-sources')), findsOneWidget);
    expect(find.byKey(const Key('bestiary-manage-open')), findsOneWidget);
  });

  testWidgets('the sources dialog opens with attribution text', (tester) async {
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.needsDownload));
    // Scroll it in: the row sits below the fold, and a tap that misses would
    // otherwise "pass" against the sheet's own identically-titled ListTile.
    await tester.scrollUntilVisible(
        find.byKey(const Key('settings-sources')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('settings-sources')));
    await tester.pumpAndSettle();
    // Assert on something ONLY the dialog renders.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  // Backup health (M5): the warning only appears when backups are actually
  // broken, and platform-unavailability must not trip it.
  testWidgets('no backup warning while backups are healthy', (tester) async {
    await pump(tester,
        status: const InterpreterStatus(InterpreterPhase.needsDownload));
    expect(find.byKey(const Key('settings-backup-error')), findsNothing);
  });

  testWidgets('a backup failure surfaces as a warning card', (tester) async {
    SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': false});
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.needsDownload));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        interpreterServiceProvider.overrideWithValue(fake),
        cloudKeyStoreProvider.overrideWithValue(FakeCloudKeyStore()),
        autoBackupErrorProvider
            .overrideWith((ref) => 'FileSystemException: disk full'),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
                onPressed: () => showSettingsSheet(context),
                child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-backup-error')), findsOneWidget);
    expect(find.text('Automatic backups are failing'), findsOneWidget);
    expect(find.textContaining('disk full'), findsOneWidget);
  });
}
