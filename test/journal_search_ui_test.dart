import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';

import 'fake_interpreter.dart';

void main() {
  // Newest-first storage: an omens-tagged result, a text note, a result.
  const journalJson =
      '[{"id":"3","timestamp":"2026-06-11T12:00:00.000","title":"Omen draw","body":"A black feather.","kind":"result","tags":["omens"]},'
      '{"id":"2","timestamp":"2026-06-11T11:00:00.000","title":"","body":"The burned mill looms.","kind":"text"},'
      '{"id":"1","timestamp":"2026-06-11T10:00:00.000","title":"Fate Check","body":"Yes, and…","kind":"result"}]';

  Future<ProviderContainer> pump(WidgetTester tester,
      {bool emptyJournal = false}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      // Suppress the contextual AI-enable nudge — it would occupy the top of
      // the entry area and push the oldest entry offscreen in this short list.
      'juice.ai_nudge_seen.v1': true,
      if (!emptyJournal) 'juice.journal.v2.default': journalJson,
    });
    final fake = FakeInterpreterService();
    await tester.pumpWidget(ProviderScope(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: JournalScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(JournalScreen)));
  }

  Future<void> openTagsDialog(WidgetTester tester, String entryText) async {
    final entry =
        find.ancestor(of: find.text(entryText), matching: find.byType(Card));
    await tester.tap(find.descendant(
        of: entry, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tags…'));
    await tester.pumpAndSettle();
  }

  Future<void> startSearch(WidgetTester tester, String query) async {
    await tester.tap(find.byKey(const Key('journal-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('journal-search-field')), query);
    // Let the search-input debounce fire before asserting on results.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  testWidgets('search icon toggles the field', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('journal-search-field')), findsNothing);
    await tester.tap(find.byKey(const Key('journal-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('journal-search-field')), findsOneWidget);
  });

  testWidgets('search icon absent when the journal is empty', (tester) async {
    await pump(tester, emptyJournal: true);
    expect(find.byKey(const Key('journal-search')), findsNothing);
  });

  testWidgets('typing filters the list; clearing restores it', (tester) async {
    await pump(tester);
    await startSearch(tester, 'mill');
    expect(find.text('The burned mill looms.'), findsOneWidget);
    expect(find.text('Omen draw'), findsNothing);
    expect(find.text('Fate Check'), findsNothing);
    // The clear/close affordance empties the query and hides the field.
    // Scope to the search field's own close icon (other close icons —
    // e.g. the recap banner's dismiss — may also be present).
    await tester.tap(find.descendant(
        of: find.byKey(const Key('journal-search-field')),
        matching: find.byIcon(Icons.close)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('journal-search-field')), findsNothing);
    expect(find.text('The burned mill looms.'), findsOneWidget);
    expect(find.text('Omen draw'), findsOneWidget);
    expect(find.text('Fate Check'), findsOneWidget);
  });

  testWidgets('search matches tags', (tester) async {
    await pump(tester);
    await startSearch(tester, 'omens');
    expect(find.text('Omen draw'), findsOneWidget);
    expect(find.text('The burned mill looms.'), findsNothing);
    expect(find.text('Fate Check'), findsNothing);
  });

  testWidgets('tag chip filters to tagged entries; tap again clears',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('tag-chip-omens')));
    await tester.pumpAndSettle();
    expect(find.text('Omen draw'), findsOneWidget);
    expect(find.text('The burned mill looms.'), findsNothing);
    expect(find.text('Fate Check'), findsNothing);
    await tester.tap(find.byKey(const Key('tag-chip-omens')));
    await tester.pumpAndSettle();
    expect(find.text('The burned mill looms.'), findsOneWidget);
    expect(find.text('Fate Check'), findsOneWidget);
  });

  testWidgets('Tags… dialog adds a tag: provider updates, chip row grows',
      (tester) async {
    final container = await pump(tester);
    await openTagsDialog(tester, 'Fate Check');
    await tester.tap(find.byKey(const Key('add-tag')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tag-input')), 'heir');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final entry = container
        .read(journalProvider)
        .valueOrNull!
        .firstWhere((e) => e.id == '1');
    expect(entry.tags, ['heir']);
    expect(find.byKey(const Key('tag-chip-heir')), findsOneWidget);
    // The entry card shows its tags as a suffix line.
    expect(find.textContaining('Yes, and…\n#heir'), findsOneWidget);
  });

  testWidgets('Tags… dialog removes a tag via the chip delete', (tester) async {
    final container = await pump(tester);
    await openTagsDialog(tester, 'Omen draw');
    await tester.tap(find.byTooltip('Delete')); // InputChip delete (×)
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final entry = container
        .read(journalProvider)
        .valueOrNull!
        .firstWhere((e) => e.id == '3');
    expect(entry.tags, isEmpty);
    expect(find.byKey(const Key('tag-chip-omens')), findsNothing);
  });
}
