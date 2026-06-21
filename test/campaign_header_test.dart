import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/shared/play_context_hud.dart';
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
  String? contextJson,
}) {
  return {
    ..._sessionPrefs,
    if (journalJson != null) 'juice.journal.v2.$_sid': journalJson,
    if (threadsJson != null) 'juice.threads.v1.$_sid': threadsJson,
    if (charsJson != null) 'juice.characters.v1.$_sid': charsJson,
    if (crawlJson != null) 'juice.crawl.v1.$_sid': crawlJson,
    if (settingsJson != null) 'juice.settings.v1.$_sid': settingsJson,
    if (contextJson != null) 'juice.context.v1.$_sid': contextJson,
  };
}

// A scene entry with chaosFactor 6.
const _sceneJson =
    '{"id":"e1","timestamp":"2026-01-01T10:00:00.000Z","title":"The Gatehouse","body":"","kind":"scene","chaosFactor":6,"tags":[]}';

// A newer scene entry (storage is newest-first, so this sorts ahead of e1).
const _scene2Json =
    '{"id":"e2","timestamp":"2026-01-01T11:00:00.000Z","title":"The Vault","body":"","kind":"scene","chaosFactor":6,"tags":[]}';

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
      home: const Scaffold(body: CampaignHeader()),
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

  testWidgets('header shows Chaos chip when the profile enables Mythic',
      (tester) async {
    // Default session prefs omit `systems` → all enabled → Mythic on.
    await _pump(
      tester,
      data,
      _prefs(journalJson: '[$_sceneJson]', crawlJson: _crawlJson),
    );
    expect(find.textContaining('Chaos 6'), findsWidgets);
  });

  testWidgets('no chaos chip when the profile excludes Mythic', (tester) async {
    // A Juice-only campaign: chaos is a Mythic concept, so the dial hides
    // even though crawl state carries a chaosFactor.
    await _pump(tester, data, {
      'juice.sessions.v1':
          '{"active":"$_sid","sessions":[{"id":"$_sid","name":"C1","systems":["juice"]}]}',
      'juice.crawl.v1.$_sid': _crawlJson,
    });
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
        ProviderScope.containerOf(tester.element(find.byType(CampaignHeader)));

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
        ProviderScope.containerOf(tester.element(find.byType(CampaignHeader)));
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

  testWidgets('header renders even when the journal is empty', (tester) async {
    // The HUD now lives at the shell level, so it must show on a fresh
    // campaign (no entries) — previously it was gated on journal entries.
    await _pump(tester, data, _prefs(crawlJson: _crawlJson));
    expect(find.byKey(const Key('campaign-header')), findsOneWidget);
    expect(find.text('No scene yet'), findsOneWidget);
  });

  testWidgets('scene line follows the active scene pointer', (tester) async {
    // Two scenes; the spine points at the older one (e1). Without the pointer
    // the newest entry (e2 "The Vault") would show.
    await _pump(
      tester,
      data,
      _prefs(
        journalJson: '[$_scene2Json,$_sceneJson]',
        crawlJson: _crawlJson,
        contextJson: '{"activeSceneId":"e1"}',
      ),
    );
    expect(find.text('The Gatehouse'), findsWidgets);
    expect(find.text('The Vault'), findsNothing);
  });

  testWidgets('quick-roll button rolls the default oracle and logs it',
      (tester) async {
    await _pump(tester, data,
        _prefs(journalJson: '[$_sceneJson]', crawlJson: _crawlJson));
    // Reachable in the always-visible row (even no need to expand).
    expect(find.byKey(const Key('hdr-quick-roll')), findsOneWidget);
    await tester.tap(find.byKey(const Key('hdr-quick-roll')));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(CampaignHeader)));
    final entries = await container.read(journalProvider.future);
    // Default oracle is Juice → a Fate Check entry was logged.
    expect(entries.where((e) => e.sourceTool == 'fate-check'), hasLength(1));
  });
}
