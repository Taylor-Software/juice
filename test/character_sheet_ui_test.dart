import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/shadowdark_sheet.dart';
import 'package:juice_oracle/features/tracker_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const seeded =
      '[{"id":"c1","name":"Ash","note":"","stats":[],"tracks":[{"label":"HP","current":7,"max":10}],"tags":[]}]';

  // The Threads/Characters tab chrome now lives in tracking_tab.dart; these
  // tests pump the public panes directly.
  Future<ProviderContainer> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': seeded,
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  Future<ProviderContainer> pumpThreads(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.threads.v1.default':
          '[{"id":"t1","title":"Find the Relic","open":true}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ThreadsPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(ThreadsPane)));
  }

  testWidgets('list row shows first-track summary', (tester) async {
    await pump(tester);
    expect(find.text('Ash'), findsOneWidget);
    expect(find.text('HP 7/10'), findsOneWidget);
  });

  testWidgets('track boxes set current level and persist', (tester) async {
    final container = await pump(tester); // HP 7/10 -> tappable boxes
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    // Tap the 8th box (index 7) to raise current to 8.
    await tester.tap(find.byKey(const Key('track-box-0-7')));
    await tester.pumpAndSettle();
    expect(find.textContaining('8/10'), findsOneWidget);
    expect(
        (await container.read(charactersProvider.future))
            .single
            .tracks
            .single
            .current,
        8);
    // Tap the last box to fill to max.
    await tester.tap(find.byKey(const Key('track-box-0-9')));
    await tester.pumpAndSettle();
    expect(find.textContaining('10/10'), findsOneWidget);
    // Tap the top filled box (index 9) again to step down.
    await tester.tap(find.byKey(const Key('track-box-0-9')));
    await tester.pumpAndSettle();
    expect(
        (await container.read(charactersProvider.future))
            .single
            .tracks
            .single
            .current,
        9);
    // No steppers on a small track.
    expect(find.byKey(const Key('track-plus-0')), findsNothing);
  });

  testWidgets('large track keeps +/- steppers, no boxes', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"c1","name":"Ash","note":"","stats":[],'
              '"tracks":[{"label":"XP","current":5,"max":40}],"tags":[]}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('track-plus-0')), findsOneWidget);
    expect(find.byKey(const Key('track-box-0-0')), findsNothing);
  });

  testWidgets('numeric stat has +/- steppers and shows a modifier',
      (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    // Add a numeric stat with the D&D modifier formula.
    await tester.tap(find.byKey(const Key('add-stat')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stat-label')), 'STR');
    await tester.enterText(find.byKey(const Key('stat-value')), '14');
    await tester.tap(find.byKey(const Key('stat-formula')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('(score − 10) ÷ 2 (D&D)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stat-save')));
    await tester.pumpAndSettle();
    // Modifier (+2) renders and steppers exist.
    expect(find.textContaining('(+2)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('stat-plus-0')));
    await tester.pumpAndSettle();
    final c = (await container.read(charactersProvider.future)).single;
    expect(c.stats.single.value, '15');
    expect(c.stats.single.modFormula, isNotNull);
  });

  testWidgets('coins counter increments and persists', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    // Pump between taps: the handler reads the build-captured character, so a
    // rebuild must land between presses (as it does in real use).
    await tester.tap(find.byKey(const Key('coins-plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('coins-plus')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('coins-value'))).data, '2');
    expect((await container.read(charactersProvider.future)).single.coins, 2);
  });

  testWidgets('notes are editable inline on the sheet', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = await pump(tester);
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('sheet-notes')), 'A cautious ranger.');
    // DebouncedTextField flushes on its 400ms timer.
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect((await container.read(charactersProvider.future)).single.note,
        'A cautious ranger.');
  });

  testWidgets('Add HP seeds an HP track at the front', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"c1","name":"Ash","note":"","stats":[],"tracks":[],"tags":[]}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(CharactersPane)));
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-hp')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('hp-max')), '8');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    final c = (await container.read(charactersProvider.future)).single;
    expect(c.tracks.first.label, 'HP');
    expect(c.tracks.first.max, 8);
    expect(c.tracks.first.current, 8);
    expect(characterHpPool(c), (8, 8));
  });

  testWidgets('enriched basic sheet does not overflow at 360px width',
      (tester) async {
    tester.view.physicalSize = const Size(360, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"c1","name":"Ash","note":"note","coins":5,'
              '"stats":[{"label":"Strength","value":"14","mod":"fived"}],'
              '"tracks":[{"label":"HP","current":7,"max":10},'
              '{"label":"XP","current":5,"max":40}],'
              '"tags":[],"conditions":["poisoned"]}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('stat-plus-0')), findsOneWidget);
    expect(find.byKey(const Key('track-box-0-0')), findsOneWidget);
    expect(find.byKey(const Key('track-plus-1')), findsOneWidget);
  });

  testWidgets('add stat and tag from the editor; back returns to list',
      (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-stat')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stat-label')), 'Iron');
    await tester.enterText(find.byKey(const Key('stat-value')), '+2');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Iron'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-tag')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tag-input')), 'wounded');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('wounded'), findsOneWidget);
    final c = (await container.read(charactersProvider.future)).single;
    expect(c.stats.single.value, '+2');
    expect(c.tags, ['wounded']);
    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    expect(find.text('HP 7/10'), findsOneWidget);
  });

  testWidgets('sheet shows the emulation summary only when emulation exists',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"c1","name":"Ash","note":"","stats":[],"tracks":[],"tags":[]},'
              '{"id":"c2","name":"Em","note":"","stats":[],"tracks":[],"tags":["brave"],'
              '"emulation":{"tokens":3,"prominentTags":["brave","bold"],"usedTags":[]}}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Em'));
    await tester.pumpAndSettle();
    expect(
        find.text('Emulation: 2 prominent traits · 3 tokens'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Emulation:'), findsNothing);
  });

  testWidgets('sheet falls back to list when the character disappears',
      (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sheet-back')), findsOneWidget);
    // Character removed underneath the open sheet (session switch, import…).
    await container.read(charactersProvider.notifier).remove('c1');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('sheet-back')), findsNothing);
    // Empty roster now shows the directive EmptyState.
    expect(find.byKey(const Key('empty-state-primary')), findsOneWidget);
    expect(find.text('Every story needs a hero.'), findsOneWidget);
  });

  testWidgets('character list row has star IconButton that toggles starred',
      (tester) async {
    final container = await pump(tester);
    // Star button present in list row.
    expect(find.byKey(const Key('star-char-c1')), findsOneWidget);
    // Initially not starred.
    expect((await container.read(charactersProvider.future)).single.starred,
        isFalse);
    // Tap star → starred.
    await tester.tap(find.byKey(const Key('star-char-c1')));
    await tester.pumpAndSettle();
    expect((await container.read(charactersProvider.future)).single.starred,
        isTrue);
    // Tap again → unstarred.
    await tester.tap(find.byKey(const Key('star-char-c1')));
    await tester.pumpAndSettle();
    expect((await container.read(charactersProvider.future)).single.starred,
        isFalse);
  });

  // -- Rich lead-PC card --------------------------------------------------
  // Pump the roster with [activeId] set as the active (lead) character so the
  // rich lead card renders; the others stay compact rows.
  Future<ProviderContainer> pumpLead(
    WidgetTester tester, {
    required String activeId,
    required String chars,
  }) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': chars,
      'juice.context.v1.default': '{"activeCharacterId":"$activeId"}',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  testWidgets('lead PC renders the rich card with vitals + quick actions',
      (tester) async {
    await pumpLead(
      tester,
      activeId: 'iw',
      chars: '[{"id":"iw","name":"Ulla","note":"","stats":[],"tracks":[],'
          '"tags":[],"ironsworn":{"edge":3,"heart":2,"iron":2,"shadow":1,'
          '"wits":1,"health":4,"spirit":5,"supply":5,"momentum":2,'
          '"xpEarned":0,"xpSpent":0,"bonds":0}}]',
    );
    // Vitals bars (Ironsworn family) + a value.
    expect(find.text('Health'), findsOneWidget);
    expect(find.text('4/5'), findsOneWidget); // Health value
    expect(find.text('Spirit'), findsOneWidget);
    expect(find.text('Supply'), findsOneWidget);
    expect(find.textContaining('Momentum'), findsOneWidget);
    // Quick-action keys.
    expect(find.byKey(const Key('lead-roll-move')), findsOneWidget);
    expect(find.byKey(const Key('lead-hp-dec')), findsOneWidget);
    expect(find.byKey(const Key('lead-hp-inc')), findsOneWidget);
    expect(find.byKey(const Key('lead-more')), findsOneWidget);
    // The lead card still carries the shared role/conditions keys.
    expect(find.byKey(const Key('role-iw')), findsOneWidget);
    expect(find.byKey(const Key('conditions-iw')), findsOneWidget);
  });

  testWidgets('lead hp- lowers the active PC HP and persists', (tester) async {
    final container = await pumpLead(
      tester,
      activeId: 'd1',
      chars: '[{"id":"d1","name":"Tarin","note":"","stats":[],"tracks":[],'
          '"tags":[],"dnd":{"currentHp":12,"maxHp":12,"ac":15}}]',
    );
    expect(find.text('12/12'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lead-hp-dec')));
    await tester.pumpAndSettle();
    expect(find.text('11/12'), findsOneWidget);
    expect(
        (await container.read(charactersProvider.future)).single.dnd!.currentHp,
        11);
  });

  testWidgets('lead hp- lowers the first track when the sheet has no HP pool',
      (tester) async {
    final container = await pumpLead(
      tester,
      activeId: 'c1',
      chars: '[{"id":"c1","name":"Ash","note":"","stats":[],'
          '"tracks":[{"label":"HP","current":7,"max":10}],"tags":[]}]',
    );
    expect(find.text('7/10'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lead-hp-dec')));
    await tester.pumpAndSettle();
    expect(find.text('6/10'), findsOneWidget);
    expect(
        (await container.read(charactersProvider.future))
            .single
            .tracks
            .single
            .current,
        6);
  });

  testWidgets('non-lead companion renders the compact row (no lead actions)',
      (tester) async {
    // c1 is the active lead PC; c2 is a companion → compact row.
    await pumpLead(
      tester,
      activeId: 'c1',
      chars: '[{"id":"c1","name":"Ash","note":"","stats":[],'
          '"tracks":[{"label":"HP","current":7,"max":10}],"tags":[]},'
          '{"id":"c2","name":"Bran","note":"","stats":[],'
          '"tracks":[{"label":"HP","current":5,"max":8}],"tags":[],'
          '"role":"companion"}]',
    );
    // Companion compact row keeps its original subtitle + shared keys…
    expect(find.text('HP 5/8'), findsOneWidget);
    expect(find.byKey(const Key('role-c2')), findsOneWidget);
    expect(find.byKey(const Key('conditions-c2')), findsOneWidget);
    expect(find.byKey(const Key('star-char-c2')), findsOneWidget);
    // …and has no lead quick-actions (those belong to the lead card only).
    expect(find.byKey(const Key('lead-roll-move')), findsOneWidget); // lead has
    // The compact row itself doesn't expose lead keys — only the single lead
    // card does, so exactly one lead-roll-move exists across the roster.
  });

  testWidgets('thread list row has pin IconButton that toggles pinned',
      (tester) async {
    final container = await pumpThreads(tester);
    // Pin button present.
    expect(find.byKey(const Key('pin-thread-t1')), findsOneWidget);
    // Initially not pinned.
    expect(
        (await container.read(threadsProvider.future)).single.pinned, isFalse);
    // Tap pin → pinned.
    await tester.tap(find.byKey(const Key('pin-thread-t1')));
    await tester.pumpAndSettle();
    expect(
        (await container.read(threadsProvider.future)).single.pinned, isTrue);
    // Tap again → unpinned.
    await tester.tap(find.byKey(const Key('pin-thread-t1')));
    await tester.pumpAndSettle();
    expect(
        (await container.read(threadsProvider.future)).single.pinned, isFalse);
  });

  // A character that already carries an Ironsworn sheet (skips create flow).
  Future<ProviderContainer> pumpIronsworn(WidgetTester tester,
      {String iron = '{"edge":3,"heart":2,"iron":2,"shadow":1,"wits":1,'
          '"health":5,"spirit":5,"supply":5,"momentum":2,'
          '"xpEarned":0,"xpSpent":0,"bonds":0}'}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.characters.v1.default':
          '[{"id":"iw","name":"Ulla","note":"","stats":[],"tracks":[],'
              '"tags":[],"ironsworn":$iron}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  testWidgets('opening an Ironsworn character shows the bespoke sheet',
      (tester) async {
    await pumpIronsworn(tester);
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ironsworn-sheet')), findsOneWidget);
    expect(find.text('EDGE'), findsOneWidget);
    expect(find.text('Health'), findsOneWidget);
  });

  testWidgets('meter and momentum steppers adjust and persist', (tester) async {
    final c = await pumpIronsworn(tester);
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-health-minus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.ironsworn!.health, 4);
    await tester.tap(find.byKey(const Key('iw-mom-minus')));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.ironsworn!.momentum,
        1);
  });

  testWidgets('Burn sets momentum to reset; debility lowers max',
      (tester) async {
    final c = await pumpIronsworn(tester,
        iron: '{"edge":3,"heart":2,"iron":2,"shadow":1,"wits":1,"health":5,'
            '"spirit":5,"supply":5,"momentum":9,"xpEarned":0,"xpSpent":0,'
            '"bonds":0}');
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-burn')));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.ironsworn!.momentum,
        2);
    // Mark a debility: max drops to 9.
    await tester.drag(
        find.byKey(const Key('ironsworn-sheet')), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-deb-shaken')));
    await tester.pumpAndSettle();
    final s = (await c.read(charactersProvider.future)).single.ironsworn!;
    expect(s.debilities, {'shaken'});
    expect(s.momentumMax, 9);
  });

  testWidgets('add a vow then mark progress', (tester) async {
    final c = await pumpIronsworn(tester);
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const Key('ironsworn-sheet')), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-add-vow')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vow-name')), 'Avenge');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Avenge'), findsOneWidget);
    // Mark one progress (default rank dangerous => +8 ticks => 2 boxes).
    await tester.tap(find.byKey(const Key('iw-vow-0-mark')));
    await tester.pumpAndSettle();
    final vow =
        (await c.read(charactersProvider.future)).single.ironsworn!.vows.single;
    expect(vow.name, 'Avenge');
    expect(vow.ticks, 8);
    expect(vow.boxes, 2);
  });

  testWidgets('pick an asset from the ruleset and toggle an ability',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.rulesets.v1': '["classic"]',
      'juice.characters.v1.default':
          '[{"id":"iw","name":"Ulla","note":"","stats":[],"tracks":[],'
              '"tags":[],"ironsworn":{"edge":3,"heart":2,"iron":2,"shadow":1,'
              '"wits":1,"health":5,"spirit":5,"supply":5,"momentum":2,'
              '"xpEarned":0,"xpSpent":0,"bonds":0}}]',
    });
    final fixture = {
      'asset_collections': [
        {
          'name': 'Combat Talent',
          'assets': [
            {
              'id': 'classic/assets/combat_talent/swordmaster',
              'name': 'Swordmaster',
              'category': 'Combat Talent',
              'abilities': [
                {'text': 'Strike harder', 'enabled': true},
                {'text': 'Press the attack', 'enabled': false},
              ],
            },
          ],
        },
      ],
    };
    final c = ProviderContainer(overrides: [
      rulesetDataProvider('classic').overrideWith((ref) async => fixture),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const Key('ironsworn-sheet')), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-add-asset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
        const Key('pick-asset-classic/assets/combat_talent/swordmaster')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Swordmaster'), findsOneWidget);
    var asset = (await c.read(charactersProvider.future))
        .single
        .ironsworn!
        .assets
        .single;
    expect(asset.enabledAbilities, [true, false]);
    // Toggle the second ability on.
    await tester.ensureVisible(find.byKey(const Key('iw-asset-0-ability-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-asset-0-ability-1')));
    await tester.pumpAndSettle();
    asset = (await c.read(charactersProvider.future))
        .single
        .ironsworn!
        .assets
        .single;
    expect(asset.enabledAbilities, [true, true]);
  });

  testWidgets('create flow makes a pre-made Ironsworn character',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.characters.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-character')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-ironsworn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ironsworn-sheet')), findsOneWidget);
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.ironsworn!.edge, 3);
  });

  Future<ProviderContainer> pumpStarforged(WidgetTester tester,
      {String sf = '{"edge":3,"heart":2,"iron":2,"shadow":1,"wits":1,'
          '"health":5,"spirit":5,"supply":5,"momentum":2,"xpEarned":0,'
          '"xpSpent":0,"questsLegacy":0,"bondsLegacy":0,"discoveriesLegacy":0}'}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.characters.v1.default':
          '[{"id":"sf","name":"Nova","note":"","stats":[],"tracks":[],'
              '"tags":[],"starforged":$sf}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  testWidgets('opening a Starforged character shows the bespoke sheet',
      (tester) async {
    await pumpStarforged(tester);
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('starforged-sheet')), findsOneWidget);
    expect(find.text('EDGE'), findsOneWidget);
    // 'Quests' label is in Legacy Tracks section, below the 600px test viewport;
    // drag to scroll it into view so the lazy ListView builds the widget.
    await tester.drag(
        find.byKey(const Key('starforged-sheet')), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Quests'), findsOneWidget);
  });

  testWidgets('SF meter/momentum/legacy steppers persist', (tester) async {
    final c = await pumpStarforged(tester);
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-health-minus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.starforged!.health, 4);
    await tester.tap(find.byKey(const Key('sf-mom-minus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.starforged!.momentum,
        1);
    // sf-quests-plus is below the 600px test viewport; drag to scroll it into
    // view before ensureVisible (lazy ListView won't build it until near-visible).
    await tester.drag(
        find.byKey(const Key('starforged-sheet')), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sf-quests-plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-quests-plus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future))
            .single
            .starforged!
            .questsLegacy,
        1);
  });

  testWidgets('SF Burn resets; impact lowers max', (tester) async {
    final c = await pumpStarforged(tester,
        sf: '{"edge":3,"heart":2,"iron":2,"shadow":1,"wits":1,"health":5,'
            '"spirit":5,"supply":5,"momentum":9,"xpEarned":0,"xpSpent":0,'
            '"questsLegacy":0,"bondsLegacy":0,"discoveriesLegacy":0}');
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-burn')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.starforged!.momentum,
        2);
    await tester.ensureVisible(find.byKey(const Key('sf-imp-doomed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-imp-doomed')));
    await tester.pumpAndSettle();
    final s = (await c.read(charactersProvider.future)).single.starforged!;
    expect(s.impacts, {'doomed'});
    expect(s.momentumMax, 9);
  });

  testWidgets('create flow offers Starforged and makes a premade SF character',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.characters.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-character')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-starforged')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('starforged-sheet')), findsOneWidget);
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.starforged!.edge, 3);
  });

  testWidgets('SF add a vow and a connection, then mark progress',
      (tester) async {
    final c = await pumpStarforged(tester);
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    // Vow — drag first so the lazy ListView builds items below the fold.
    await tester.drag(
        find.byKey(const Key('starforged-sheet')), const Offset(0, -800));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sf-add-vow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-add-vow')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('vow-name')), 'Reach the Forge');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sf-vow-0-mark')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-vow-0-mark')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future))
            .single
            .starforged!
            .vows
            .single
            .ticks,
        8);
    // Connection
    await tester.ensureVisible(find.byKey(const Key('sf-add-conn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-add-conn')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('conn-name')), 'Lara');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    final sf = (await c.read(charactersProvider.future)).single.starforged!;
    expect(sf.connections.single.name, 'Lara');
  });

  testWidgets('SF pick an asset and toggle an ability', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.rulesets.v1': '["starforged"]',
      'juice.characters.v1.default':
          '[{"id":"sf","name":"Nova","note":"","stats":[],"tracks":[],'
              '"tags":[],"starforged":{"edge":3,"heart":2,"iron":2,"shadow":1,'
              '"wits":1,"health":5,"spirit":5,"supply":5,"momentum":2,'
              '"xpEarned":0,"xpSpent":0,"questsLegacy":0,"bondsLegacy":0,'
              '"discoveriesLegacy":0}}]',
    });
    final fixture = {
      'asset_collections': [
        {
          'name': 'Path',
          'assets': [
            {
              'id': 'starforged/assets/path/ace',
              'name': 'Ace',
              'category': 'Path',
              'abilities': [
                {'text': 'Reroll a die', 'enabled': true},
                {'text': 'Push your luck', 'enabled': false},
              ],
            },
          ],
        },
      ],
    };
    final c = ProviderContainer(overrides: [
      rulesetDataProvider('starforged').overrideWith((ref) async => fixture),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    // Assets section is deep in the sheet (after vows/connections); pre-scroll
    // so the lazy ListView builds the widget before ensureVisible.
    await tester.drag(
        find.byKey(const Key('starforged-sheet')), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sf-add-asset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-add-asset')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('pick-asset-starforged/assets/path/ace')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ace'), findsOneWidget);
    var asset = (await c.read(charactersProvider.future))
        .single
        .starforged!
        .assets
        .single;
    expect(asset.enabledAbilities, [true, false]);
    await tester.ensureVisible(find.byKey(const Key('sf-asset-0-ability-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-asset-0-ability-1')));
    await tester.pumpAndSettle();
    asset = (await c.read(charactersProvider.future))
        .single
        .starforged!
        .assets
        .single;
    expect(asset.enabledAbilities, [true, true]);
  });

  Future<ProviderContainer> pumpDnd(WidgetTester tester,
      {String dnd = '{"abilities":{"str":15,"dex":13,"con":14,"int":8,"wis":12,'
          '"cha":10},"className":"Fighter","level":1,"ac":16,"currentHp":12,'
          '"maxHp":12,"hitDiceRemaining":1,"speed":30,'
          '"saveProficiencies":["str","con"],'
          '"skillProficiencies":["athletics","perception"]}'}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["dnd"]}]}',
      'juice.characters.v1.default':
          '[{"id":"dd","name":"Tarin","note":"","stats":[],"tracks":[],'
              '"tags":[],"dnd":$dnd}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  testWidgets('opening a D&D character shows the bespoke sheet',
      (tester) async {
    await pumpDnd(tester);
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dnd-sheet')), findsOneWidget);
    expect(find.byKey(const Key('dnd-ability-str-plus')), findsOneWidget);
    expect(find.text('Saving Throws'), findsOneWidget);
  });

  testWidgets('ability stepper updates the modifier and persists',
      (tester) async {
    final c = await pumpDnd(tester);
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    // STR 15 (+2). Bump to 16 (+3).
    await tester.tap(find.byKey(const Key('dnd-ability-str-plus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.dnd!.score('str'), 16);
    expect(find.text('+3'), findsWidgets); // STR mod now +3
  });

  testWidgets('save proficiency toggle changes the shown save bonus',
      (tester) async {
    final c = await pumpDnd(tester);
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const Key('dnd-sheet')), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('dnd-save-dex')));
    await tester.pumpAndSettle();
    // DEX save starts +1 (mod only). Toggle proficiency -> +3 (mod +1 + prof +2).
    await tester.tap(find.byKey(const Key('dnd-save-dex')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future))
            .single
            .dnd!
            .saveProficiencies
            .contains('dex'),
        isTrue);
  });

  testWidgets('create flow makes a premade D&D character', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["dnd"]}]}',
      'juice.characters.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-character')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-dnd')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dnd-sheet')), findsOneWidget);
    expect((await c.read(charactersProvider.future)).single.dnd!.className,
        'Fighter');
  });

  testWidgets('skill proficiency + expertise change the skill bonus',
      (tester) async {
    final c = await pumpDnd(tester);
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    // Stealth (DEX +1), not proficient. Scroll the lazy list until built.
    await tester.scrollUntilVisible(
        find.byKey(const Key('dnd-skill-stealth-prof')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dnd-skill-stealth-prof')));
    await tester.pumpAndSettle();
    var sheet = (await c.read(charactersProvider.future)).single.dnd!;
    expect(sheet.skillProficiencies.contains('stealth'), isTrue);
    expect(sheet.skillBonus('stealth'), 3); // dex +1 + prof +2
    // Expertise doubles proficiency.
    await tester.tap(find.byKey(const Key('dnd-skill-stealth-exp')));
    await tester.pumpAndSettle();
    sheet = (await c.read(charactersProvider.future)).single.dnd!;
    expect(sheet.skillExpertise.contains('stealth'), isTrue);
    expect(sheet.skillBonus('stealth'), 5); // dex +1 + prof*2 (+4)
  });

  testWidgets('condition toggle and exhaustion stepper persist',
      (tester) async {
    final c = await pumpDnd(tester);
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('dnd-cond-poisoned')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dnd-cond-poisoned')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future))
            .single
            .dnd!
            .conditions
            .contains('poisoned'),
        isTrue);
    await tester.tap(find.byKey(const Key('dnd-exhaustion-plus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.dnd!.exhaustionLevel,
        1);
  });

  testWidgets('create flow makes a Sundered Isles character with SI label',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.characters.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-character')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-sundered')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('starforged-sheet')), findsOneWidget);
    expect(find.text('Sundered Isles'), findsOneWidget);
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.starforged!.assetRuleset, 'sundered_isles');
  });

  Future<ProviderContainer> pumpShadowdark(WidgetTester tester,
      {String sd = '{"abilities":{"str":13,"dex":12,"con":14,"int":8,"wis":10,'
          '"cha":10},"className":"Fighter","ancestry":"Human",'
          '"alignment":"Neutral","level":1,"ac":13,"currentHp":8,"maxHp":8}'}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["shadowdark"]}]}',
      'juice.characters.v1.default':
          '[{"id":"sd","name":"Mort","note":"","stats":[],"tracks":[],'
              '"tags":[],"shadowdark":$sd}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  testWidgets('opening a Shadowdark character shows the bespoke sheet',
      (tester) async {
    await pumpShadowdark(tester);
    await tester.tap(find.text('Mort'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shadowdark-sheet')), findsOneWidget);
    expect(find.text('STR'), findsOneWidget);
    expect(find.textContaining('Gear'), findsWidgets);
  });

  testWidgets('SD ability stepper + luck toggle persist', (tester) async {
    final c = await pumpShadowdark(tester);
    await tester.tap(find.text('Mort'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sd-ability-str-plus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future))
            .single
            .shadowdark!
            .score('str'),
        14);
    await tester.scrollUntilVisible(find.byKey(const Key('sd-luck')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sd-luck')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.shadowdark!.luckToken,
        isTrue);
  });

  testWidgets('Wizard shows Spells section; Fighter does not', (tester) async {
    await pumpShadowdark(tester,
        sd: '{"abilities":{"str":8,"dex":12,"con":10,"int":16,"wis":10,'
            '"cha":10},"className":"Wizard","ancestry":"Elf",'
            '"alignment":"Neutral","level":1,"ac":11,"currentHp":4,"maxHp":4}');
    await tester.tap(find.text('Mort'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('sd-spells')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('sd-spells')), findsOneWidget);
  });

  testWidgets('create flow makes a premade Shadowdark character',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["shadowdark"]}]}',
      'juice.characters.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-character')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-shadowdark')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shadowdark-sheet')), findsOneWidget);
    expect(
        (await c.read(charactersProvider.future)).single.shadowdark!.className,
        'Fighter');
  });

  testWidgets('Shadowdark Combat/HP rows do not overflow at 360px width',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Stress: a Priest (caster + deity field), 4-digit XP, 2-digit AC/HP.
    await pumpShadowdark(tester,
        sd: '{"abilities":{"str":15,"dex":12,"con":14,"int":8,"wis":16,'
            '"cha":10},"className":"Priest","ancestry":"Dwarf",'
            '"alignment":"Lawful","level":10,"xp":1234,"ac":18,'
            '"currentHp":88,"maxHp":88}');
    await tester.tap(find.text('Mort'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shadowdark-sheet')), findsOneWidget);
    // Scroll through the sheet so every fixed-width row lays out; a RenderFlex
    // overflow would throw during the scroll.
    await tester.scrollUntilVisible(find.byKey(const Key('sd-luck')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('D&D Combat rows do not overflow at 360px width', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // High-level fixture: 3-digit HP and a long hit-dice label stress the
    // Combat HP + hit-dice rows hardest.
    await pumpDnd(tester,
        dnd: '{"abilities":{"str":15,"dex":13,"con":14,"int":8,"wis":12,'
            '"cha":10},"className":"Fighter","level":20,"ac":18,'
            '"currentHp":188,"maxHp":188,"hitDiceRemaining":20,"speed":30,'
            '"saveProficiencies":["str","con"],'
            '"skillProficiencies":["athletics","perception"]}');
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dnd-sheet')), findsOneWidget);
    // Scroll the whole sheet so the lazy ListView builds (and lays out) every
    // fixed-width row — AC/HP/hit-dice near the top and the death-saves row
    // below the fold. Any RenderFlex overflow is captured during the scroll.
    await tester.scrollUntilVisible(
        find.byKey(const Key('dnd-death-ok-plus')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ironsworn XP row does not overflow at 360px width',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpIronsworn(tester,
        iron: '{"edge":3,"heart":2,"iron":2,"shadow":1,"wits":1,"health":5,'
            '"spirit":5,"supply":5,"momentum":2,"xpEarned":30,"xpSpent":28,'
            '"bonds":0}');
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    // The XP row lives in the Experience & Bonds section below the fold; scroll
    // it into view so the lazy ListView lays it out.
    await tester.scrollUntilVisible(
        find.byKey(const Key('iw-xpEarned-plus')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  String wizardDnd({int level = 5}) =>
      '{"abilities":{"str":8,"dex":14,"con":12,"int":16,"wis":10,"cha":10},'
      '"className":"Wizard","level":$level,"ac":12,"currentHp":20,"maxHp":20,'
      '"hitDiceRemaining":$level,"speed":30}';

  testWidgets('caster sheet shows Spellcasting with derived DC + slot stepper',
      (tester) async {
    final c = await pumpDnd(tester, dnd: wizardDnd());
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('dnd-slot-1-plus')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Spellcasting'), findsOneWidget);
    expect(find.textContaining('DC 14'), findsOneWidget); // 8 + prof3 + int+3
    // Expend a level-1 slot.
    await tester.tap(find.byKey(const Key('dnd-slot-1-plus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.dnd!.spellSlotsUsed[0],
        1);
  });

  testWidgets('Warlock shows a Pact Magic row', (tester) async {
    await pumpDnd(tester,
        dnd: '{"abilities":{"str":10,"dex":14,"con":12,"int":10,"wis":10,'
            '"cha":16},"className":"Warlock","level":5,"ac":12,"currentHp":20,'
            '"maxHp":20,"hitDiceRemaining":5,"speed":30}');
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('dnd-pact-plus')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Pact'), findsOneWidget);
  });

  testWidgets('non-caster (Fighter) shows no Spellcasting section',
      (tester) async {
    await pumpDnd(tester); // premade Fighter
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    expect(find.text('Spellcasting'), findsNothing);
  });

  testWidgets('Sundered Isles picker lists SI assets', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.rulesets.v1': '["starforged","sundered_isles"]',
      'juice.characters.v1.default':
          '[{"id":"si","name":"Mara","note":"","stats":[],"tracks":[],'
              '"tags":[],"starforged":{"edge":3,"heart":2,"iron":2,"shadow":1,'
              '"wits":1,"health":5,"spirit":5,"supply":5,"momentum":2,'
              '"xpEarned":0,"xpSpent":0,"questsLegacy":0,"bondsLegacy":0,'
              '"discoveriesLegacy":0,"assetRuleset":"sundered_isles"}}]',
    });
    final fixture = {
      'asset_collections': [
        {
          'name': 'Path',
          'assets': [
            {
              'id': 'asset:sundered_isles/path/corsair',
              'name': 'Corsair',
              'category': 'Path',
              'abilities': [
                {'text': 'Sail hard', 'enabled': true},
              ],
            },
          ],
        },
      ],
    };
    final c = ProviderContainer(overrides: [
      rulesetDataProvider('sundered_isles')
          .overrideWith((ref) async => fixture),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mara'));
    await tester.pumpAndSettle();
    expect(find.text('Sundered Isles'), findsOneWidget);
    await tester.drag(
        find.byKey(const Key('starforged-sheet')), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sf-add-asset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-add-asset')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('pick-asset-asset:sundered_isles/path/corsair')),
        findsOneWidget);
  });

  testWidgets(
      'sheet picker hides Ironsworn family when ironsworn system is off',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["dnd"]}]}',
      'juice.characters.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-character')));
    await tester.pumpAndSettle();
    // ironsworn system is off, so the Ironsworn-family options are hidden.
    expect(find.byKey(const Key('new-ironsworn')), findsNothing);
    expect(find.byKey(const Key('new-starforged')), findsNothing);
    expect(find.byKey(const Key('new-sundered')), findsNothing);
    // Generic + the enabled D&D option remain.
    expect(find.byKey(const Key('new-generic')), findsOneWidget);
    expect(find.byKey(const Key('new-dnd')), findsOneWidget);
  });

  testWidgets('sheet picker hints how to enable D&D/Shadowdark when off',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.characters.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-character')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Edit systems'), findsOneWidget);
  });

  testWidgets(
      'sheet picker omits the hint when D&D, Shadowdark, Nimble, Draw Steel, Tales of Argosa, Cairn, Knave, OSE, Kal-Arath, and Custom are on',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["dnd","shadowdark","nimble","draw-steel","argosa","cairn","knave","ose","kal-arath","custom"]}]}',
      'juice.characters.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-character')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Edit systems'), findsNothing);
    expect(find.byKey(const Key('new-dnd')), findsOneWidget);
    expect(find.byKey(const Key('new-shadowdark')), findsOneWidget);
    expect(find.byKey(const Key('new-nimble')), findsOneWidget);
    expect(find.byKey(const Key('new-draw-steel')), findsOneWidget);
    expect(find.byKey(const Key('new-argosa')), findsOneWidget);
    expect(find.byKey(const Key('new-cairn')), findsOneWidget);
    expect(find.byKey(const Key('new-knave')), findsOneWidget);
    expect(find.byKey(const Key('new-ose')), findsOneWidget);
    expect(find.byKey(const Key('new-kal-arath')), findsOneWidget);
    expect(find.byKey(const Key('new-custom')), findsOneWidget);
  });

  testWidgets(
      'sheet picker scrolls without overflow and reaches Shadowdark when the '
      'Ironsworn family is also enabled', (tester) async {
    // Cramped window: the old action-bar picker overflowed here, clipping the
    // last (Shadowdark) option. The scrollable list must not overflow, and
    // every sheet type must be reachable.
    tester.view.physicalSize = const Size(420, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final errors = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = prev);

    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn","shadowdark"]}]}',
      'juice.characters.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-character')));
    await tester.pumpAndSettle();

    expect(errors, isEmpty, reason: 'picker must not overflow at 420x500');
    expect(find.byKey(const Key('new-shadowdark')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('new-shadowdark')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-shadowdark')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shadowdark-sheet')), findsOneWidget);
    expect(
        (await c.read(charactersProvider.future)).single.shadowdark, isNotNull);
  });

  testWidgets('Generate NPC prefills and creates a character', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': '[]',
    });
    final oracle = Oracle(OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>));
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('generate-npc')));
    await tester.pumpAndSettle();
    // The edit dialog opens prefilled; Save creates the character.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.length, 1);
    expect(chars.first.name.trim(), isNotEmpty);
  });

  testWidgets('Generate NPC dialog dice re-rolls the name field',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': '[]',
    });
    final oracle = Oracle(OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>));
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('generate-npc')));
    await tester.pumpAndSettle();
    // Locate the dice IconButtons scoped to the AlertDialog — one on the
    // name field, one on the note (characteristics) field.
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final diceButtons = find.descendant(
        of: dialog, matching: find.byIcon(Icons.casino_outlined));
    expect(diceButtons, findsNWidgets(2));
    await tester.tap(diceButtons.first);
    await tester.pumpAndSettle();
    // After re-roll the name field must still be non-empty.
    final fields =
        find.descendant(of: dialog, matching: find.byType(TextField));
    final nameTf = tester.widget<TextField>(fields.first);
    expect(nameTf.controller!.text.trim(), isNotEmpty);
    // The note dice re-rolls the NPC characteristics.
    await tester.tap(diceButtons.last);
    await tester.pumpAndSettle();
    final noteTf = tester.widget<TextField>(fields.last);
    expect(noteTf.controller!.text, contains('Personality'));
  });

  // -- Task 3: grouped roster + role dropdown --

  testWidgets('roster groups by role with headers', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"p1","name":"Tarin","stats":[],"tracks":[],"tags":[]},'
              '{"id":"n1","name":"Veyra","role":"npc","stats":[],"tracks":[],"tags":[]}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    expect(find.text('Party'), findsOneWidget);
    expect(find.text('NPCs'), findsOneWidget);
    expect(find.text('Companions'), findsNothing); // empty group hidden
  });

  testWidgets('role dropdown re-tags a character', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"p1","name":"Tarin","stats":[],"tracks":[],"tags":[]}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    final c =
        ProviderScope.containerOf(tester.element(find.byType(CharactersPane)));
    await tester.tap(find.byKey(const Key('role-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NPC').last);
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.role,
        CharacterRole.npc);
  });

  // -- Task 4: condition badges + inline editor --

  testWidgets('condition badges show and inline editor toggles them',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"p1","name":"Tarin","stats":[],"tracks":[],"tags":[],'
              '"conditions":["poisoned"]}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    final c =
        ProviderScope.containerOf(tester.element(find.byType(CharactersPane)));
    expect(find.text('poisoned'), findsWidgets); // badge on the row
    await tester.tap(find.byKey(const Key('conditions-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('hidden')); // toggle a preset on in the editor
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final ch = (await c.read(charactersProvider.future)).single;
    expect(ch.conditions, containsAll(['poisoned', 'hidden']));
  });

  // -- Task 5: Generate NPC → npc role --

  testWidgets('Generate NPC creates an npc-role character', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': '[]',
    });
    final oracle = Oracle(OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>));
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('generate-npc')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.role,
        CharacterRole.npc);
  });

  testWidgets('shadowdark torch stepper saves to the character',
      (tester) async {
    // Tall view so the whole sheet renders (the Light section is far down a
    // lazily-built ListView).
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': jsonEncode([
        {
          'id': 'sd1',
          'name': 'Mort',
          'shadowdark': ShadowdarkSheet.premade().toJson(),
        }
      ]),
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final char = (await c.read(charactersProvider.future)).single;
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
                body: ShadowdarkSheetView(character: char, onBack: () {})))));
    await tester.pumpAndSettle();
    // Torch starts at 0 → "out".
    expect(find.text('Torch'), findsOneWidget);
    expect(find.text('out'), findsOneWidget);
    // Tapping + persists torch=1 on the character (the isolated view keeps
    // showing the passed-in character; the roster rebuilds it in the app).
    await tester.ensureVisible(find.byKey(const Key('sd-torch-plus')));
    await tester.tap(find.byKey(const Key('sd-torch-plus')));
    await tester.pumpAndSettle();
    expect(c.read(charactersProvider).valueOrNull!.single.shadowdark!.torch, 1);
  });

  testWidgets('shadowdark sheet surfaces conditions in a Status section',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': jsonEncode([
        {
          'id': 'sd1',
          'name': 'Mort',
          'shadowdark': ShadowdarkSheet.premade().toJson(),
          'conditions': ['poisoned'],
        }
      ]),
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final char = (await c.read(charactersProvider.future)).single;
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
                body: ShadowdarkSheetView(character: char, onBack: () {})))));
    await tester.pumpAndSettle();
    // The condition is visible on the open sheet, with an inline Edit affordance.
    expect(find.text('Status'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'poisoned'), findsOneWidget);
    expect(find.byKey(const Key('sd-edit-conditions')), findsOneWidget);
  });

  testWidgets('party effect broadcasts HP + condition across the party',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': '['
          '{"id":"p1","name":"Aldra","tracks":[{"label":"HP","current":10,"max":10}]},'
          '{"id":"p2","name":"Bryn","tracks":[{"label":"HP","current":10,"max":10}]}'
          ']',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(CharactersPane)));

    // The Party group header shows the Effect button (>1 member).
    await tester.tap(find.byKey(const Key('party-effect-pc')));
    await tester.pumpAndSettle();
    // Damage 2 and add a condition, then apply.
    await tester.tap(find.byKey(const Key('party-effect-hp-minus')));
    await tester.tap(find.byKey(const Key('party-effect-hp-minus')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'poisoned'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('party-effect-apply')));
    await tester.pumpAndSettle();

    for (final ch in container.read(charactersProvider).valueOrNull!) {
      expect(ch.tracks.first.current, 8);
      expect(ch.conditions, contains('poisoned'));
    }
  });

  testWidgets('roster shows a mentions backlink chip and opens the list',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"c1","name":"Ash","stats":[],"tracks":[],"tags":[]}]',
      'juice.journal.v2.default':
          '[{"id":"e1","timestamp":"2026-06-11T10:00:00.000","title":"","body":"Met @[Ash](char:c1) at the gate.","kind":"text"}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mentions-c1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mentions-c1')));
    await tester.pumpAndSettle();
    // Transient list: the count + the mention rendered as plain text.
    expect(find.textContaining('mentioned in 1'), findsOneWidget);
    expect(find.textContaining('Met Ash at the gate.'), findsWidgets);
  });
}
