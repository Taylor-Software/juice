import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/session_resume_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

// ---------------------------------------------------------------------------
// Pure-helper unit tests
// ---------------------------------------------------------------------------

void main() {
  group('formatLastPlayed', () {
    final now = DateTime(2026, 1, 10, 12, 0, 0);

    test('just now under a minute', () {
      expect(
          formatLastPlayed(now.subtract(const Duration(seconds: 30)), now: now),
          'just now');
    });

    test('minutes ago', () {
      expect(
          formatLastPlayed(now.subtract(const Duration(minutes: 1)), now: now),
          '1 minute ago');
      expect(
          formatLastPlayed(now.subtract(const Duration(minutes: 5)), now: now),
          '5 minutes ago');
    });

    test('hours ago', () {
      expect(formatLastPlayed(now.subtract(const Duration(hours: 1)), now: now),
          '1 hour ago');
      expect(formatLastPlayed(now.subtract(const Duration(hours: 3)), now: now),
          '3 hours ago');
    });

    test('days ago', () {
      expect(formatLastPlayed(now.subtract(const Duration(days: 1)), now: now),
          '1 day ago');
      expect(formatLastPlayed(now.subtract(const Duration(days: 2)), now: now),
          '2 days ago');
    });
  });

  group('buildStaticRecap', () {
    JournalEntry entry(String id, String title, String body,
            {JournalKind kind = JournalKind.text}) =>
        JournalEntry(
          id: id,
          timestamp: DateTime(2026, 1, 1),
          title: title,
          body: body,
          kind: kind,
        );

    test('folds scene + open threads + last entries (newest-first input)', () {
      final scene = entry('s1', 'The Vault', '', kind: JournalKind.scene);
      final threads = [
        Thread(id: 't1', title: 'Find the Relic'),
        Thread(id: 't2', title: 'Escape the keep', open: false),
      ];
      // Storage is newest-first; recap should read most-recent few.
      final entries = [
        entry('e3', '', 'I draw my sword.'),
        entry('e2', 'Trap', 'A pit yawns open.'),
        entry('e1', '', 'We enter the hall.'),
        scene,
      ];
      final out =
          buildStaticRecap(scene: scene, threads: threads, entries: entries);
      expect(out, contains('Scene: The Vault'));
      // Only the OPEN thread is listed.
      expect(out, contains('Find the Relic'));
      expect(out, isNot(contains('Escape the keep')));
      expect(out, contains('I draw my sword.'));
    });

    test('empty session falls back to a placeholder', () {
      final out = buildStaticRecap(scene: null, threads: [], entries: []);
      expect(out, 'No session activity yet.');
    });
  });

  // -------------------------------------------------------------------------
  // Widget test
  // -------------------------------------------------------------------------

  group('SessionResumeScreen', () {
    late OracleData data;
    setUpAll(() {
      final raw = File('assets/oracle_data.json').readAsStringSync();
      data = OracleData(jsonDecode(raw) as Map<String, dynamic>);
    });

    const sid = 'default';
    const sceneJson =
        '{"id":"e1","timestamp":"2026-01-01T10:00:00.000Z","title":"Scene 3","body":"","kind":"scene","chaosFactor":6,"tags":[]}';
    // A newer prose entry (newest-first → sorts ahead of the scene).
    const lastEntryJson =
        '{"id":"e2","timestamp":"2026-01-01T11:00:00.000Z","title":"","body":"I draw my sword and step through the broken gate.","kind":"text","tags":[]}';
    const threadJson =
        '[{"id":"t1","title":"Find the Tower\'s Secret","open":true,"pinned":true,"progress":3}]';
    const crawlJson =
        '{"chaosFactor":6,"dialogRow":2,"dialogCol":2,"lost":false}';

    Future<ProviderContainer> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"$sid","sessions":[{"id":"$sid","name":"Campaign 1"}]}',
        'juice.journal.v2.$sid': '[$lastEntryJson,$sceneJson]',
        'juice.threads.v1.$sid': threadJson,
        'juice.crawl.v1.$sid': crawlJson,
        'juice.context.v1.$sid': '{"activeSceneId":"e1"}',
      });
      final oracle = Oracle(data, Dice(Random(1)));
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late ProviderContainer container;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          oracleProvider.overrideWith((ref) async => oracle),
          interpreterServiceProvider
              .overrideWithValue(FakeInterpreterService()),
        ],
        child: Consumer(builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return MaterialApp(
            theme: AppTheme.light(),
            home: const SessionResumeScreen(),
          );
        }),
      ));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('renders scene, stat tiles, thread, last entry, CTA',
        (tester) async {
      await pump(tester);

      // Active scene title (header + Scene stat tile).
      expect(find.text('Scene 3'), findsWidgets);

      // The three stat-tile labels.
      expect(find.text('Scene'), findsOneWidget);
      expect(find.text('Chaos'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      // Chaos value (Mythic enabled by default) + Light "out" (no light set).
      expect(find.text('6'), findsOneWidget);
      expect(find.text('out'), findsOneWidget);

      // Open-thread row: progress bar + n/max readout (replaces Open/Pinned pill).
      expect(find.byKey(const Key('resume-thread-t1')), findsOneWidget);
      expect(find.text("Find the Tower's Secret"), findsOneWidget);
      expect(
          find.descendant(
            of: find.byKey(const Key('resume-thread-t1')),
            matching: find.byType(LinearProgressIndicator),
          ),
          findsOneWidget);
      expect(find.text('3/10'), findsOneWidget);
      expect(find.text('Pinned'), findsNothing);
      expect(find.text('Open'), findsNothing);

      // Last entry line (italic, quoted).
      expect(find.text('"I draw my sword and step through the broken gate."'),
          findsOneWidget);

      // Primary + secondary CTAs.
      expect(find.byKey(const Key('resume-continue')), findsOneWidget);
      expect(find.byKey(const Key('resume-recap')), findsOneWidget);
      expect(find.byKey(const Key('resume-new-scene')), findsOneWidget);
    });

    testWidgets('Continue pops the resume screen and lands', (tester) async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"$sid","sessions":[{"id":"$sid","name":"Campaign 1"}]}',
        'juice.journal.v2.$sid': '[$lastEntryJson,$sceneJson]',
        'juice.crawl.v1.$sid': crawlJson,
      });
      final oracle = Oracle(data, Dice(Random(1)));
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Mount the resume screen as a pushed route so Continue can pop it.
      await tester.pumpWidget(ProviderScope(
        overrides: [
          oracleProvider.overrideWith((ref) async => oracle),
          interpreterServiceProvider
              .overrideWithValue(FakeInterpreterService()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SessionResumeScreen(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('resume-continue')), findsOneWidget);

      await tester.tap(find.byKey(const Key('resume-continue')));
      await tester.pumpAndSettle();

      // Popped back to the launching screen.
      expect(find.byKey(const Key('resume-continue')), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('Recap (AI off) shows the static summary dialog',
        (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('resume-recap')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('resume-recap-dialog')), findsOneWidget);
      expect(find.text('Previously…'), findsOneWidget);
      // Static recap folds in the scene title.
      expect(find.textContaining('Scene 3'), findsWidgets);
    });
  });
}
