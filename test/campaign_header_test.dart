import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

OracleData _loadData() {
  final raw = File('assets/oracle_data.json').readAsStringSync();
  return OracleData(jsonDecode(raw) as Map<String, dynamic>);
}

const _sid = 'default';
const _sessionPrefs = {
  'juice.sessions.v1':
      '{"active":"$_sid","sessions":[{"id":"$_sid","name":"C1"}]}',
};

/// Seed prefs with optional journal, threads, characters, and crawl data.
Map<String, Object> _prefs({
  String? journalJson,
  String? threadsJson,
  String? charsJson,
  String? crawlJson,
  String? settingsJson,
}) {
  return {
    ..._sessionPrefs,
    if (journalJson != null) 'juice.journal.v2.$_sid': journalJson,
    if (threadsJson != null) 'juice.threads.v1.$_sid': threadsJson,
    if (charsJson != null) 'juice.characters.v1.$_sid': charsJson,
    if (crawlJson != null) 'juice.crawl.v1.$_sid': crawlJson,
    if (settingsJson != null) 'juice.settings.v1.$_sid': settingsJson,
  };
}

// A scene entry with chaosFactor 6.
const _sceneJson =
    '{"id":"e1","timestamp":"2026-01-01T10:00:00.000Z","title":"The Gatehouse","body":"","kind":"scene","chaosFactor":6,"tags":[]}';

// A plain text entry (no chaosFactor — no Mythic usage).
const _textJson =
    '{"id":"e2","timestamp":"2026-01-01T10:01:00.000Z","title":"","body":"Hello world","kind":"text","tags":[]}';

// A pinned open thread.
const _threadJson =
    '[{"id":"t1","title":"Find the Relic","open":true,"pinned":true}]';

// A starred character.
const _charJson =
    '[{"id":"c1","name":"Ash","note":"","stats":[],"tracks":[],"tags":[],"starred":true}]';

// Crawl state: chaosFactor 6.
const _crawlJson = '{"chaosFactor":6,"dialogRow":2,"dialogCol":2,"lost":false}';

Future<void> _pump(
  WidgetTester tester,
  OracleData data,
  Map<String, Object> prefs,
) async {
  SharedPreferences.setMockInitialValues(prefs);
  final fake = FakeInterpreterService();
  final oracle = Oracle(data, Dice(Random(1)));
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
      interpreterServiceProvider.overrideWithValue(fake),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: JournalScreen()),
    ),
  ));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late OracleData data;
  setUpAll(() => data = _loadData());

  testWidgets('header is present when journal has entries', (tester) async {
    await _pump(
      tester,
      data,
      _prefs(
        journalJson: '[$_sceneJson]',
        threadsJson: _threadJson,
        charsJson: _charJson,
        crawlJson: _crawlJson,
      ),
    );
    expect(find.byKey(const Key('campaign-header')), findsOneWidget);
  });

  testWidgets('header shows current scene title', (tester) async {
    await _pump(
      tester,
      data,
      _prefs(journalJson: '[$_sceneJson]', crawlJson: _crawlJson),
    );
    expect(find.text('The Gatehouse'), findsWidgets);
  });

  testWidgets('header shows Chaos chip when journal has a scene with chaos',
      (tester) async {
    await _pump(
      tester,
      data,
      _prefs(journalJson: '[$_sceneJson]', crawlJson: _crawlJson),
    );
    expect(find.textContaining('Chaos 6'), findsWidgets);
  });

  testWidgets('no chaos chip when journal has only text entries',
      (tester) async {
    await _pump(
      tester,
      data,
      _prefs(journalJson: '[$_textJson]'),
    );
    expect(find.textContaining('Chaos'), findsNothing);
  });

  testWidgets('pinned thread chip appears with key hdr-thread-<id>',
      (tester) async {
    await _pump(
      tester,
      data,
      _prefs(
        journalJson: '[$_sceneJson]',
        threadsJson: _threadJson,
        crawlJson: _crawlJson,
      ),
    );
    expect(find.byKey(const Key('hdr-thread-t1')), findsOneWidget);
    // Title appears in both the header chip and the journal filter bar.
    expect(find.text('Find the Relic'), findsWidgets);
  });

  testWidgets('starred character chip appears with key hdr-char-<id>',
      (tester) async {
    await _pump(
      tester,
      data,
      _prefs(
        journalJson: '[$_sceneJson]',
        charsJson: _charJson,
        crawlJson: _crawlJson,
      ),
    );
    expect(find.byKey(const Key('hdr-char-c1')), findsOneWidget);
    expect(find.text('Ash'), findsOneWidget);
  });

  testWidgets('chaos inc/dec buttons change value and persist', (tester) async {
    await _pump(
      tester,
      data,
      _prefs(journalJson: '[$_sceneJson]', crawlJson: _crawlJson),
    );
    // Initial chaos = 6 shown in the InputChip.
    expect(find.textContaining('Chaos 6'), findsWidgets);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));

    // Increment.
    await tester.tap(find.byKey(const Key('hdr-chaos-inc')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chaos 7'), findsWidgets);
    expect((await container.read(crawlProvider.future)).chaosFactor, 7);

    // Decrement twice.
    await tester.tap(find.byKey(const Key('hdr-chaos-dec')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hdr-chaos-dec')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chaos 5'), findsWidgets);
    expect((await container.read(crawlProvider.future)).chaosFactor, 5);
  });

  testWidgets('collapse toggle hides detail row and persists', (tester) async {
    await _pump(
      tester,
      data,
      _prefs(
        journalJson: '[$_sceneJson]',
        crawlJson: _crawlJson,
      ),
    );
    // Detail row is visible (chaos chip present).
    expect(find.textContaining('Chaos 6'), findsWidgets);

    // Tap collapse.
    await tester.tap(find.byKey(const Key('hdr-collapse')));
    await tester.pumpAndSettle();

    // Chaos chip gone from header (still in journal scene divider is OK).
    // The header oracle chip and chaos buttons should be gone.
    expect(find.byKey(const Key('hdr-chaos-inc')), findsNothing);
    expect(find.byKey(const Key('hdr-oracle')), findsNothing);

    // Persisted: re-pump reads collapsed state.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    expect((await container.read(settingsProvider.future)).headerCollapsed,
        isTrue);
  });

  testWidgets('oracle chip shows Juice label and default oracle is juice',
      (tester) async {
    await _pump(
      tester,
      data,
      _prefs(journalJson: '[$_sceneJson]', crawlJson: _crawlJson),
    );
    expect(find.byKey(const Key('hdr-oracle')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('hdr-oracle')),
            matching: find.text('Juice')),
        findsOneWidget);
  });
}
