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

OracleData _loadData() {
  final raw = File('assets/oracle_data.json').readAsStringSync();
  return OracleData(jsonDecode(raw) as Map<String, dynamic>);
}

const _sid = 'default';
const _sessionsJson =
    '{"active":"$_sid","sessions":[{"id":"$_sid","name":"C1"}]}';

Map<String, Object> _prefsWithNpcEntry(String entryJson) => {
      'juice.sessions.v1': _sessionsJson,
      'juice.journal.v2.$_sid': entryJson,
    };

Future<ProviderContainer> pumpScreen(
    WidgetTester tester, OracleData data, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final fake = FakeInterpreterService();
  final oracle = Oracle(data, Dice(Random(1)));
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final scope = ProviderScope(
    overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
      interpreterServiceProvider.overrideWithValue(fake),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: JournalScreen()),
    ),
  );
  await tester.pumpWidget(scope);
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
}

// A gen-npcs result entry with a payload summary.
final _npcEntry = jsonEncode([
  {
    'id': 'e1',
    'timestamp': '2026-06-12T10:00:00.000',
    'title': 'NPC Generator',
    'body': 'Name: Kestrel\nRole: Scout',
    'kind': 'result',
    'sourceTool': 'gen-npcs',
    'payload': {
      'v': 1,
      'summary': 'Kestrel',
      'rolls': [
        {'label': 'Name', 'display': 'Kestrel'},
        {'label': 'Role', 'display': 'Scout'},
      ],
    },
  },
]);

// A gen-exploration result entry.
final _explorationEntry = jsonEncode([
  {
    'id': 'e2',
    'timestamp': '2026-06-12T10:00:00.000',
    'title': 'Exploration Generator',
    'body': 'Area: Dark Cave',
    'kind': 'result',
    'sourceTool': 'gen-exploration',
    'payload': {
      'v': 1,
      'summary': 'Dark Cave',
      'rolls': [
        {'label': 'Area', 'display': 'Dark Cave'},
      ],
    },
  },
]);

// A fate-juice result entry (not save-able).
final _fateEntry = jsonEncode([
  {
    'id': 'e3',
    'timestamp': '2026-06-12T10:00:00.000',
    'title': 'Fate Check',
    'body': 'Yes.',
    'kind': 'result',
    'sourceTool': 'fate-juice',
    'payload': {
      'v': 1,
      'rolls': [
        {'label': 'Result', 'display': 'Yes.'},
      ],
    },
  },
]);

void main() {
  late OracleData data;
  setUpAll(() => data = _loadData());

  group('save-as-entity menu item', () {
    testWidgets('gen-npcs entry shows "Save as character" in popup menu',
        (tester) async {
      await pumpScreen(tester, data, _prefsWithNpcEntry(_npcEntry));

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();

      expect(find.text('Save as character'), findsOneWidget);
    });

    testWidgets('gen-exploration entry shows "Save as thread" in popup menu',
        (tester) async {
      await pumpScreen(tester, data, _prefsWithNpcEntry(_explorationEntry));

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();

      expect(find.text('Save as thread'), findsOneWidget);
    });

    testWidgets('fate-juice entry does NOT show a save-entity item',
        (tester) async {
      await pumpScreen(tester, data, _prefsWithNpcEntry(_fateEntry));

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();

      expect(find.text('Save as character'), findsNothing);
      expect(find.text('Save as thread'), findsNothing);
    });
  });

  group('save-as-character action', () {
    testWidgets(
        'creates a character with the NPC summary name and backfills a mention',
        (tester) async {
      final container =
          await pumpScreen(tester, data, _prefsWithNpcEntry(_npcEntry));

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as character'));
      await tester.pumpAndSettle();

      // Character created with the summary name.
      final chars = container.read(charactersProvider).valueOrNull ?? [];
      expect(chars.any((c) => c.name == 'Kestrel'), isTrue);
      final newId = chars.firstWhere((c) => c.name == 'Kestrel').id;

      // Journal entry body now contains the mention token.
      final entries = container.read(journalProvider).valueOrNull ?? [];
      final body = entries.first.body;
      expect(body, contains('@[Kestrel](char:$newId)'));
    });
  });

  group('save-as-thread action', () {
    testWidgets(
        'creates a thread with the exploration summary name and backfills a mention',
        (tester) async {
      final container =
          await pumpScreen(tester, data, _prefsWithNpcEntry(_explorationEntry));

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as thread'));
      await tester.pumpAndSettle();

      // Thread created with the summary name.
      final threads = container.read(threadsProvider).valueOrNull ?? [];
      expect(threads.any((t) => t.title == 'Dark Cave'), isTrue);
      final newId = threads.firstWhere((t) => t.title == 'Dark Cave').id;

      // Journal entry body now contains the mention token.
      final entries = container.read(journalProvider).valueOrNull ?? [];
      final body = entries.first.body;
      expect(body, contains('@[Dark Cave](thread:$newId)'));
    });
  });

  group('character filter chip', () {
    testWidgets('filter chip for a mentioned character filters the journal',
        (tester) async {
      // Two entries: one with a Mara mention, one without.
      final twoEntries = jsonEncode([
        {
          'id': 'e_mara',
          'timestamp': '2026-06-12T10:01:00.000',
          'title': '',
          'body': 'Met @[Mara](char:c1) in the square.',
          'kind': 'text',
        },
        {
          'id': 'e_other',
          'timestamp': '2026-06-12T10:00:00.000',
          'title': '',
          'body': 'Quiet day.',
          'kind': 'text',
        },
      ]);
      final prefs = {
        'juice.sessions.v1': _sessionsJson,
        'juice.journal.v2.$_sid': twoEntries,
        'juice.characters.v1.$_sid':
            '[{"id":"c1","name":"Mara","note":"","stats":[],"tracks":[],"tags":[]}]',
      };
      await pumpScreen(tester, data, prefs);

      // Chip for Mara should be present (keyed char-filter-c1).
      expect(find.byKey(const Key('char-filter-c1')), findsOneWidget);

      // Before filtering, both entries visible.
      expect(find.text('Quiet day.'), findsOneWidget);

      // Tap the char filter chip.
      await tester.tap(find.byKey(const Key('char-filter-c1')));
      await tester.pumpAndSettle();

      // Only the entry mentioning Mara remains visible.
      expect(find.text('Quiet day.'), findsNothing);
    });
  });
}
