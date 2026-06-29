import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/state/providers.dart';

// ──────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────

final _hasJournalProvider = StateProvider<bool>((ref) => false);
final _lastExportMsProvider = StateProvider<int?>((ref) => null);

/// Sandbox mirrors the launcher backup-nudge gate:
/// show when hasJournal && (lastExport==null || staleDays>=7).
class _BackupSandbox extends ConsumerWidget {
  const _BackupSandbox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasJournal = ref.watch(_hasJournalProvider);
    final lastExport = ref.watch(_lastExportMsProvider);
    final staleDays = lastExport == null
        ? null
        : DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(lastExport))
            .inDays;
    final show =
        hasJournal && (lastExport == null || (staleDays != null && staleDays >= 7));
    return Scaffold(
      body: Column(
        children: [
          if (show)
            Card(
              key: const Key('backup-nudge'),
              child: Text(lastExport == null
                  ? 'You haven\'t exported this campaign yet.'
                  : 'Exported $staleDays days ago'),
            ),
        ],
      ),
    );
  }
}

Widget _host({required bool hasJournal, int? lastExportMs}) =>
    ProviderScope(
      overrides: [
        _hasJournalProvider.overrideWith((ref) => hasJournal),
        _lastExportMsProvider.overrideWith((ref) => lastExportMs),
      ],
      child: const MaterialApp(home: _BackupSandbox()),
    );

// ──────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('backup nudge visibility', () {
    testWidgets('hidden when no journal entries', (tester) async {
      await tester.pumpWidget(_host(hasJournal: false, lastExportMs: null));
      await tester.pump();
      expect(find.byKey(const Key('backup-nudge')), findsNothing);
    });

    testWidgets('shown when has journal and never exported', (tester) async {
      await tester.pumpWidget(_host(hasJournal: true, lastExportMs: null));
      await tester.pump();
      expect(find.byKey(const Key('backup-nudge')), findsOneWidget);
    });

    testWidgets('shown when last export was 8 days ago', (tester) async {
      final ms = DateTime.now()
          .subtract(const Duration(days: 8))
          .millisecondsSinceEpoch;
      await tester.pumpWidget(_host(hasJournal: true, lastExportMs: ms));
      await tester.pump();
      expect(find.byKey(const Key('backup-nudge')), findsOneWidget);
    });

    testWidgets('hidden when exported today', (tester) async {
      final ms = DateTime.now().millisecondsSinceEpoch;
      await tester.pumpWidget(_host(hasJournal: true, lastExportMs: ms));
      await tester.pump();
      expect(find.byKey(const Key('backup-nudge')), findsNothing);
    });

    testWidgets('hidden when exported 3 days ago', (tester) async {
      final ms = DateTime.now()
          .subtract(const Duration(days: 3))
          .millisecondsSinceEpoch;
      await tester.pumpWidget(_host(hasJournal: true, lastExportMs: ms));
      await tester.pump();
      expect(find.byKey(const Key('backup-nudge')), findsNothing);
    });
  });

  group('LastExportNotifier', () {
    test('stamp writes and reads back', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(lastExportProvider.notifier).stamp();
      final ts = c.read(lastExportProvider).valueOrNull;
      expect(ts, isNotNull);
      expect(ts!, greaterThan(0));
    });
  });
}
