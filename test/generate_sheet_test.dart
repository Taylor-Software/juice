import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/custom_table.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/generate_sheet.dart';
import 'package:juice_oracle/shared/result_card.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

const _basePrefs = {
  'juice.sessions.v1':
      '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
  'juice.journal.v2.default': '[]',
};

Future<ProviderContainer> _makeContainer() async {
  SharedPreferences.setMockInitialValues({..._basePrefs});
  final c = ProviderContainer(overrides: [
    oracleProvider.overrideWith((ref) async => _oracle()),
  ]);
  addTearDown(c.dispose);
  await c.read(oracleProvider.future);
  // Ensure sessionsProvider (and therefore crawlProvider) has built.
  await c.read(sessionsProvider.future);
  return c;
}

Future<void> _pumpSheet(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: GenerateSheet()))));
  await tester.pumpAndSettle();
}

/// Pumps a HOST that opens the sheet via the real [showGenerateSheet] entry
/// point. The host — not the sheet — owns the context/ref the Inspire SnackBar
/// closes over, which is the whole point: a flavor chip pops the sheet, so a
/// snackbar wired from inside it would fire on a dead ref.
Future<void> _pumpHost(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            key: const Key('open-gen'),
            onPressed: () => showGenerateSheet(context, ref),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a flavor chip logs, pops the sheet, and offers Inspire on the '
      'entry it just wrote', (tester) async {
    SharedPreferences.setMockInitialValues({..._basePrefs});
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => _oracle()),
      interpretReadyProvider.overrideWithValue(true),
      interpreterServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await c.read(sessionsProvider.future);
    await c.read(journalProvider.future);

    await _pumpHost(tester, c);
    await tester.tap(find.byKey(const Key('open-gen')));
    await tester.pumpAndSettle();

    // One tap on a flavor chip: logs AND closes (the fast path is preserved).
    await tester.tap(find.byKey(const Key('gen-New Quest')));
    await tester.pumpAndSettle();
    expect(find.byType(GenerateSheet), findsNothing, reason: 'sheet popped');
    expect((c.read(journalProvider).valueOrNull ?? const []), hasLength(1));

    // The snackbar's Inspire action runs against the HOST's ref, which
    // outlived the popped sheet — a dead ref would throw here.
    final inspire = find.text('Inspire');
    expect(inspire, findsOneWidget);
    await tester.tap(inspire);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('interp-accept-0')));
    await tester.pumpAndSettle();

    // Still ONE entry — the reading folded into the roll it came from.
    final journal = c.read(journalProvider).valueOrNull ?? const [];
    expect(journal, hasLength(1));
    expect(journal.single.body, contains('— Oracle reading (literal): fallback'));
  });

  testWidgets('no Inspire action on the snackbar when interpret is not ready',
      (tester) async {
    SharedPreferences.setMockInitialValues({..._basePrefs});
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => _oracle()),
      interpretReadyProvider.overrideWithValue(false),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await c.read(sessionsProvider.future);
    await c.read(journalProvider.future);

    await _pumpHost(tester, c);
    await tester.tap(find.byKey(const Key('open-gen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gen-New Quest')));
    await tester.pumpAndSettle();

    expect((c.read(journalProvider).valueOrNull ?? const []), hasLength(1));
    expect(find.text('Inspire'), findsNothing);
    expect(find.text('Added to journal'), findsOneWidget);
  });

  testWidgets('lists flavor generators (not the entity ones)', (tester) async {
    final c = await _makeContainer();
    await _pumpSheet(tester, c);
    expect(find.text('Pay the Price'), findsOneWidget);
    expect(find.text('Random Event'), findsOneWidget);
    // entity generators are NOT in the flavor sheet:
    expect(find.text('New Scene'), findsNothing);
    expect(find.text('Monster Encounter'), findsNothing);
  });

  testWidgets('tapping a generator adds a journal entry', (tester) async {
    final c = await _makeContainer();
    await _pumpSheet(tester, c);
    await tester.tap(find.text('Pay the Price'));
    await tester.pumpAndSettle();
    final entries = await c.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.sourceTool, 'gen-story');
  });

  // --- Visual & Stateful generators -----------------------------------------

  testWidgets(
      'gen-location chip renders location card; log button adds gen-exploration entry',
      (tester) async {
    final c = await _makeContainer();
    await _pumpSheet(tester, c);

    // Tap the Location chip: no journal entry yet (card is shown inline).
    await tester.tap(find.byKey(const Key('gen-location')));
    await tester.pumpAndSettle();

    // The location card appears — it always shows compass labels.
    expect(find.text('North'), findsOneWidget);
    expect(find.text('South'), findsOneWidget);
    // The location-grid key is present.
    expect(find.byKey(const Key('location-grid')), findsOneWidget);

    // No journal entry yet — chip tap is display-only.
    var entries = await c.read(journalProvider.future);
    expect(entries, isEmpty);

    // Tap the bookmark button on the location card to add to journal.
    await tester.tap(find.byKey(const Key('location-log')));
    await tester.pumpAndSettle();

    entries = await c.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.sourceTool, 'gen-exploration');
  });

  testWidgets(
      'gen-npc-dialog chip renders ResultCard; log button adds gen-npcs entry; '
      'no LateInitializationError', (tester) async {
    final c = await _makeContainer();
    await _pumpSheet(tester, c);

    // Tap the NPC Dialog chip.
    await tester.tap(find.byKey(const Key('gen-npc-dialog')));
    await tester.pumpAndSettle();

    // A ResultCard for "NPC Dialog" should appear.
    expect(find.byType(ResultCard), findsOneWidget);
    // "NPC Dialog" appears both in the chip label and the ResultCard title.
    expect(find.text('NPC Dialog'), findsAtLeast(1));

    // No journal entry yet — chip tap is display-only.
    var entries = await c.read(journalProvider.future);
    expect(entries, isEmpty);

    // Tap the bookmark button inside ResultCard to log.
    await tester.tap(find.byTooltip('Add to journal'));
    await tester.pumpAndSettle();

    entries = await c.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.sourceTool, 'gen-npcs');
  });

  testWidgets(
      'gen-abstract-icon chip renders a settled icon die and adds NO journal '
      'entry until logged', (tester) async {
    final c = await _makeContainer();
    await _pumpSheet(tester, c);

    // Tap the Story Dice chip (default count 1).
    await tester.tap(find.byKey(const Key('gen-abstract-icon')));
    await tester.pumpAndSettle(); // past the tumble

    // The single-die card shows the Abstract Icon title + settled die + pairs.
    expect(find.text('Abstract Icon'), findsOneWidget);
    expect(find.byKey(const Key('icon-die-0')), findsOneWidget);
    expect(find.textContaining('d10 '), findsOneWidget);

    // Roll itself is display-only — journal stays empty.
    final entries = await c.read(journalProvider.future);
    expect(entries, isEmpty);
  });

  testWidgets(
      'story dice: count picker rolls N icons; log writes one entry with the '
      'icon paths in the payload', (tester) async {
    final c = await _makeContainer();
    await _pumpSheet(tester, c);

    await tester.tap(find.byKey(const Key('icon-dice-count-3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('gen-abstract-icon')));
    await tester.pumpAndSettle(); // past the tumble

    expect(find.text('Story Dice'), findsAtLeast(1));
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(Key('icon-die-$i')), findsOneWidget);
    }
    expect(find.byKey(const Key('icon-die-3')), findsNothing);

    await tester.tap(find.byKey(const Key('icon-dice-log')));
    await tester.pumpAndSettle();

    final entries = await c.read(journalProvider.future);
    expect(entries.length, 1);
    final e = entries.first;
    expect(e.title, 'Story Dice (3)');
    expect(e.sourceTool, 'gen-story');
    final icons = (e.payload?['icons'] as List).cast<String>();
    expect(icons.length, 3);
    for (final a in icons) {
      expect(a, startsWith('assets/abstract_icons/'));
    }
  });

  // --- My Tables (user-authored custom tables) ------------------------------

  testWidgets('rolling a custom table logs a custom-table journal entry',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ..._basePrefs,
      'juice.custom_tables.v1':
          '[{"id":"t1","name":"Weather","rows":["Rain","Sun"]}]',
    });
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => _oracle()),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await c.read(sessionsProvider.future);
    await c.read(customTablesProvider.future);
    await _pumpSheet(tester, c);

    await tester.tap(find.byKey(const Key('table-roll-t1')));
    await tester.pumpAndSettle();

    final entries = await c.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.sourceTool, 'custom-table');
    expect(entries.first.title, 'Weather');
  });

  testWidgets('New table dialog creates a table chip', (tester) async {
    final c = await _makeContainer();
    await c.read(customTablesProvider.future);
    await _pumpSheet(tester, c);

    await tester.tap(find.byKey(const Key('table-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('table-name')), 'Loot');
    await tester.enterText(
        find.byKey(const Key('table-rows')), 'Gold\nGem\nScroll');
    await tester.tap(find.byKey(const Key('table-save')));
    await tester.pumpAndSettle();

    final tables = await c.read(customTablesProvider.future);
    expect(tables.single.name, 'Loot');
    expect(tables.single.rows.map((r) => r.text).toList(),
        ['Gold', 'Gem', 'Scroll']);
    expect(find.widgetWithText(InputChip, 'Loot'), findsOneWidget);
  });

  testWidgets('creates a ranges table and rolls it to a journal entry',
      (tester) async {
    final c = await _makeContainer();
    await _pumpSheet(tester, c);

    // Open the new-table dialog.
    await tester.tap(find.byKey(const Key('table-new')));
    await tester.pumpAndSettle();

    // Name it.
    await tester.enterText(find.byKey(const Key('table-name')), 'Loot');

    // Switch to Ranges mode -> dice field appears.
    await tester.tap(find.text('Ranges'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('table-dice')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('table-dice')), 'd100');
    await tester.enterText(
        find.byKey(const Key('table-rows')), '1-50 Copper\n51-100 Gold');
    await tester.tap(find.byKey(const Key('table-save')));
    await tester.pumpAndSettle();

    // The table persisted with ranges mode.
    final tables = await c.read(customTablesProvider.future);
    expect(tables.single.name, 'Loot');
    expect(tables.single.mode, TableRoll.ranges);
    expect(tables.single.dice, 'd100');
    expect(tables.single.rows, hasLength(2));

    // Roll it -> a journal entry with the custom-table source tool.
    await tester.tap(find.byKey(Key('table-roll-${tables.single.id}')));
    await tester.pumpAndSettle();
    final entries = await c.read(journalProvider.future);
    expect(entries.single.sourceTool, 'custom-table');
  });
}
