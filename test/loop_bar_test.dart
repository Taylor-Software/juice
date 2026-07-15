import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/loop_bar.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';

import 'fake_interpreter.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester,
      {List<Override> overrides = const []}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: LoopBar()))),
    ));
    await tester.pumpAndSettle();
  }

  /// Expand the collapsible Steps tile so step-card widgets enter the tree.
  Future<void> expandSteps(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('loop-steps')));
    await tester.pumpAndSettle();
  }

  // Regression: the app theme sets FilledButton.minimumSize = Size.fromHeight
  // (width == infinity). Under that theme a FilledButton must not sit in a
  // width-unbounding parent (Row/Wrap), or layout throws "forces an infinite
  // width". This pumps LoopBar under the real AppTheme and exercises the
  // always-visible Next-beat button, the beat menu, the Steps cards, and the
  // inline interpret card's Keep button — all themed-FilledButton hot spots.
  testWidgets('no infinite-width under AppTheme (Next-beat + interpret)',
      (tester) async {
    SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': true});
    final fake = FakeInterpreterService();
    await tester.pumpWidget(ProviderScope(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SingleChildScrollView(child: LoopBar())),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); // Next-beat renders themed
    // Open the beat menu (context actions render as buttons).
    await tester.tap(find.byKey(const Key('loop-next-beat')));
    await tester.pumpAndSettle();
    // Expand the Steps tile (themed FilledButtons in _step Wraps).
    await tester.tap(find.byKey(const Key('loop-steps')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('New-scene dialog seeds a title from the scene generator',
      (tester) async {
    await pump(tester, overrides: [
      // Real oracle from the asset FILE (rootBundle hangs the headless
      // runner) — the seed chip awaits oracleProvider.
      oracleProvider.overrideWith((ref) async => _oracle()),
    ]);
    await expandSteps(tester);
    await tester.tap(find.byKey(const Key('loop-new-scene')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('loop-scene-seed')));
    await tester.pump();
    final seeded = tester
        .widget<TextField>(find.byKey(const Key('loop-scene-name')))
        .controller!
        .text;
    expect(seeded, isNotEmpty);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('loop-next-beat'))));
    final journal = container.read(journalProvider).valueOrNull ?? const [];
    expect(journal.any((e) => e.kind == JournalKind.scene && e.title == seeded),
        isTrue);
  });

  testWidgets('step cards stretch to the full row width', (tester) async {
    await pump(tester);
    await expandSteps(tester);
    // Audit F2 regression: the default (center) ExpansionTile alignment let
    // each step Card shrink to content width and float in dead gutters.
    final cardWidth = tester
        .getSize(find.ancestor(
            of: find.byKey(const Key('loop-new-scene')),
            matching: find.byType(Card)))
        .width;
    final rowWidth = tester.getSize(find.byKey(const Key('loop-steps'))).width;
    expect(cardWidth, greaterThan(rowWidth - 40),
        reason: 'step card ($cardWidth) should fill the row ($rowWidth)');
  });

  testWidgets('renders the five steps', (tester) async {
    await pump(tester);
    await expandSteps(tester);
    expect(find.byKey(const Key('loop-new-scene')), findsOneWidget);
    expect(find.byKey(const Key('loop-ask')), findsOneWidget);
    expect(find.byKey(const Key('loop-inspire')), findsOneWidget);
    // Capture field is further down; scroll to it.
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-capture-field')), findsOneWidget);
  });

  testWidgets('Ask rolls, shows a result, and logs one journal entry',
      (tester) async {
    await pump(tester);
    await expandSteps(tester);
    await tester.tap(find.byKey(const Key('loop-ask')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-ask-result')), findsOneWidget);

    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('loop-ask'))));
    final journal = container.read(journalProvider).valueOrNull ?? const [];
    expect(journal.where((e) => e.sourceTool == 'solo-loop'), hasLength(1));
  });

  testWidgets('no inline interpret card before any ask', (tester) async {
    await pump(tester); // default: aiReady false
    await expandSteps(tester);
    expect(find.byKey(const Key('loop-interpret-card')), findsNothing);
  });

  testWidgets('beat-interpret action appears after ask when AI is ready',
      (tester) async {
    SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': true});
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    await pump(tester, overrides: [
      aiReadyProvider.overrideWithValue(true),
      interpreterServiceProvider.overrideWithValue(fake),
    ]);
    await expandSteps(tester);
    // create a scene so hasScene is true
    await tester.tap(find.byKey(const Key('loop-new-scene')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('loop-scene-name')), 'The crypt');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    // ask the oracle
    await tester.tap(find.byKey(const Key('loop-ask')));
    await tester.pumpAndSettle();
    // open the next-beat panel
    await tester.tap(find.byKey(const Key('loop-next-beat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('beat-interpret')), findsOneWidget);
  });

  testWidgets(
      'interpret renders inline; Keep folds the reading into the '
      'roll\'s own entry', (tester) async {
    SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': true});
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    late ProviderContainer container;
    await pump(tester, overrides: [
      aiReadyProvider.overrideWithValue(true),
      interpreterServiceProvider.overrideWithValue(fake),
    ]);
    await expandSteps(tester);
    // create a scene
    await tester.tap(find.byKey(const Key('loop-new-scene')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('loop-scene-name')), 'The crypt');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    // ask to seed _loopLastProvider
    await tester.tap(find.byKey(const Key('loop-ask')));
    await tester.pumpAndSettle();
    // open next-beat and tap Interpret
    await tester.tap(find.byKey(const Key('loop-next-beat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('beat-interpret')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-interpret-card')), findsOneWidget);
    container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('loop-interpret-card'))));
    // The seed carries the shared grounding — the scene rides through (this
    // seam sent no recall at all before the inspire standardization).
    expect(fake.lastSeed!.sceneContext, contains('The crypt'));

    await tester.tap(find.byKey(const Key('loop-interpret-keep')));
    await tester.pumpAndSettle();
    final journal = container.read(journalProvider).valueOrNull ?? const [];
    // One combined entry: the reading folds into the roll that prompted it,
    // rather than landing as a second free-floating 'interpret' entry.
    expect(journal.where((e) => e.sourceTool == 'interpret'), isEmpty);
    final roll = journal.firstWhere((e) => e.sourceTool == 'solo-loop');
    expect(roll.body, contains('— Oracle reading (literal): fallback'));
    expect(journal.where((e) => e.sourceTool == 'solo-loop').length, 1);
  });

  testWidgets('interpret Discard hides card and logs nothing', (tester) async {
    SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': true});
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    late ProviderContainer container;
    await pump(tester, overrides: [
      aiReadyProvider.overrideWithValue(true),
      interpreterServiceProvider.overrideWithValue(fake),
    ]);
    await expandSteps(tester);
    // create a scene
    await tester.tap(find.byKey(const Key('loop-new-scene')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('loop-scene-name')), 'The crypt');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    // ask to seed _loopLastProvider
    await tester.tap(find.byKey(const Key('loop-ask')));
    await tester.pumpAndSettle();
    // open next-beat and tap Interpret
    await tester.tap(find.byKey(const Key('loop-next-beat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('beat-interpret')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-interpret-card')), findsOneWidget);
    container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('loop-interpret-card'))));
    await tester.tap(find.byKey(const Key('loop-interpret-discard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-interpret-card')), findsNothing);
    final journal = container.read(journalProvider).valueOrNull ?? const [];
    expect(journal.where((e) => e.sourceTool == 'interpret').length, 0);
  });

  testWidgets('Ask again clears a visible interpret card', (tester) async {
    SharedPreferences.setMockInitialValues({'juice.ai_enabled.v1': true});
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    await pump(tester, overrides: [
      aiReadyProvider.overrideWithValue(true),
      interpreterServiceProvider.overrideWithValue(fake),
    ]);
    await expandSteps(tester);
    await tester.tap(find.byKey(const Key('loop-new-scene')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('loop-scene-name')), 'The crypt');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('loop-ask')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('loop-next-beat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('beat-interpret')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-interpret-card')), findsOneWidget);
    // Rolling again must drop the stale card (it read the previous roll).
    await tester.tap(find.byKey(const Key('beat-askAgain')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-interpret-card')), findsNothing);
  });

  testWidgets('new-scene dialog sets a custom title', (tester) async {
    await pump(tester);
    await expandSteps(tester);
    await tester.tap(find.byKey(const Key('loop-new-scene')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-scene-name')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('loop-scene-name')), 'The crypt');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('loop-new-scene'))));
    final journal = container.read(journalProvider).valueOrNull ?? const [];
    expect(
      journal
          .where((e) => e.kind == JournalKind.scene && e.title == 'The crypt'),
      hasLength(1),
    );
  });

  testWidgets('step-4 inline create makes a tallied thread', (tester) async {
    await pump(tester);
    await expandSteps(tester);
    // Scroll the task creator into view.
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('loop-task-name')), 'Escape the dungeon');
    await tester.tap(find.byKey(const Key('loop-task-new')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('loop-task-new'))));
    final threads = container.read(threadsProvider).valueOrNull ?? const [];
    final tallied = threads.where((t) => t.tally != null).toList();
    expect(tallied, hasLength(1));
    expect(tallied.single.title, 'Escape the dungeon');
    // Default preset is Minor challenge 3(6).
    expect(tallied.single.tally!.target, 6);
    expect(tallied.single.tally!.current, 3);
  });

  testWidgets('capture send button logs a journal entry', (tester) async {
    await pump(tester);
    await expandSteps(tester);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -800));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('loop-capture-field')), 'A scrap of lore');
    await tester.tap(find.byKey(const Key('loop-capture-send')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('loop-capture-send'))));
    final journal = container.read(journalProvider).valueOrNull ?? const [];
    expect(journal.where((e) => e.body == 'A scrap of lore'), hasLength(1));
  });

  testWidgets('odds + last survive a State dispose/repump', (tester) async {
    // Use a single shared container so the file-private ephemeral providers
    // persist across a State teardown (simulating a tab switch + return).
    final container = ProviderContainer();
    addTearDown(container.dispose);

    Widget app(Widget child) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: child)),
        );

    await tester.pumpWidget(app(const SingleChildScrollView(child: LoopBar())));
    await tester.pumpAndSettle();

    // Expand the steps tile so step-card widgets are in the tree.
    await tester.tap(find.byKey(const Key('loop-steps')));
    await tester.pumpAndSettle();

    // Pick Likely, then Ask.
    await tester.tap(find.text('Likely'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('loop-ask')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-ask-result')), findsOneWidget);

    // Tear down the bar (dispose the State) then re-pump in the same container.
    await tester.pumpWidget(app(const SizedBox.shrink()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(const SingleChildScrollView(child: LoopBar())));
    await tester.pumpAndSettle();

    // Re-expand the steps tile after the State was recreated.
    await tester.tap(find.byKey(const Key('loop-steps')));
    await tester.pumpAndSettle();

    // The result text persists because _last lives in the ephemeral provider
    // (it would be gone if state were widget-local and reset on dispose).
    expect(find.byKey(const Key('loop-ask-result')), findsOneWidget);
  });

  testWidgets('next-beat shows Name-the-scene when no scene', (tester) async {
    await pump(tester); // no active scene seeded by default
    await tester.tap(find.byKey(const Key('loop-next-beat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('beat-nameScene')), findsOneWidget);
    expect(find.byKey(const Key('beat-ask')), findsNothing);
  });

  testWidgets('next-beat shows Ask when scene exists', (tester) async {
    await pump(tester);
    await expandSteps(tester);
    // Create a scene via the new-scene dialog.
    await tester.tap(find.byKey(const Key('loop-new-scene')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('loop-scene-name')), 'The chapel');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    // Now tap Next beat — hasScene is true.
    await tester.tap(find.byKey(const Key('loop-next-beat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('beat-ask')), findsOneWidget);
    expect(find.byKey(const Key('beat-nameScene')), findsNothing);
  });

  testWidgets('tally roll logs an entry and shows the inline result',
      (tester) async {
    await pump(tester);
    await expandSteps(tester);
    // Create a task first.
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('loop-task-name')), 'Pick the lock');
    await tester.tap(find.byKey(const Key('loop-task-new')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('loop-task-new'))));
    final id = (container.read(threadsProvider).valueOrNull ?? const [])
        .firstWhere((t) => t.tally != null)
        .id;

    await tester.tap(find.byKey(Key('loop-task-roll-$id')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loop-tally-roll-result')), findsOneWidget);
    final journal = container.read(journalProvider).valueOrNull ?? const [];
    expect(
      journal
          .where((e) => e.title == 'Tally roll' && e.sourceTool == 'solo-loop'),
      hasLength(1),
    );
  });
}
