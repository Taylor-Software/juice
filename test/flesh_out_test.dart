import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/hexcrawl_data.dart';
import 'package:juice_oracle/engine/map_builder.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/map_screen.dart';
import 'package:juice_oracle/features/tracker_screen.dart';
import 'package:juice_oracle/shared/ai_badge.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));
HexcrawlData _hexData() => HexcrawlData(
    jsonDecode(File('assets/hexcrawl_data.json').readAsStringSync())
        as Map<String, dynamic>);

class _FixedSessions extends SessionsNotifier {
  _FixedSessions(this.systems);
  final List<String> systems;
  @override
  Future<SessionsState> build() async => SessionsState(
        active: 'default',
        sessions: [SessionMeta(id: 'default', name: 'M', systems: systems)],
      );
}

FakeInterpreterService _fake() => FakeInterpreterService(
    initial: const InterpreterStatus(InterpreterPhase.ready));

Future<ProviderContainer> _pumpCharacters(
    WidgetTester tester, FakeInterpreterService fake,
    {bool aiEnabled = true}) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default':
        '[{"id":"c1","name":"Ash","note":"A scout.","stats":[],"tracks":[],"tags":[],"role":"npc"}]',
    if (aiEnabled) 'juice.ai_enabled.v1': true,
  });
  await tester.pumpWidget(ProviderScope(
    overrides: [interpreterServiceProvider.overrideWithValue(fake)],
    child: MaterialApp(
        theme: AppTheme.light(), home: const Scaffold(body: CharactersPane())),
  ));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(CharactersPane)));
}

void main() {
  testWidgets('character flesh-out appends detail to the note', (tester) async {
    final c = await _pumpCharacters(tester, _fake());
    await tester.tap(find.text('Ash')); // open the sheet
    await tester.pumpAndSettle();
    // The ✦ AI badge marks the trigger.
    expect(
        find.descendant(
            of: find.byKey(const Key('flesh-out-character')),
            matching: find.byType(AiBadge)),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('flesh-out-character')));
    await tester.pumpAndSettle(); // fleshOut() + the _EditDialog
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final chars = c.read(charactersProvider).valueOrNull!;
    expect(chars.single.note, contains('A scout.')); // preserved
    expect(chars.single.note, contains('Fleshed-out detail.')); // appended
  });

  testWidgets('flesh-out button is hidden when AI is not ready',
      (tester) async {
    await _pumpCharacters(tester, _fake(), aiEnabled: false);
    await tester.tap(find.text('Ash')); // open the sheet
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('flesh-out-character')), findsNothing);
  });

  testWidgets('thread flesh-out appends detail to the note', (tester) async {
    final fake = _fake();
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.threads.v1.default':
          '[{"id":"t1","title":"Find the Relic","note":"Rumored lost.","open":true}]',
      'juice.ai_enabled.v1': true,
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
          theme: AppTheme.light(), home: const Scaffold(body: ThreadsPane())),
    ));
    await tester.pumpAndSettle();
    final c =
        ProviderScope.containerOf(tester.element(find.byType(ThreadsPane)));
    expect(
        find.descendant(
            of: find.byKey(const Key('flesh-out-thread-t1')),
            matching: find.byType(AiBadge)),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('flesh-out-thread-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final threads = c.read(threadsProvider).valueOrNull!;
    expect(threads.single.note, contains('Rumored lost.'));
    expect(threads.single.note, contains('Fleshed-out detail.'));
  });

  testWidgets('room flesh-out appends to room.detail after Append',
      (tester) async {
    final fake = _fake();
    const seeded = MapState(
      dungeons: [
        DungeonSite(id: 'd1', levels: [
          DungeonLevel(
            depth: 1,
            rooms: [
              DungeonRoom(id: 'r1', x: 0, y: 0, title: 'Crypt', detail: 'Dim.')
            ],
            currentRoomId: 'r1',
          ),
        ]),
      ],
      activeDungeonId: 'd1',
    );
    SharedPreferences.setMockInitialValues({
      'flutter.juice.map.v1.default': jsonEncode(seeded.toJson()),
      'juice.ai_enabled.v1': true,
    });
    final c = ProviderContainer(overrides: [
      hexcrawlDataProvider.overrideWith((ref) async => _hexData()),
      sessionsProvider
          .overrideWith(() => _FixedSessions(['juice', 'hexcrawl'])),
      interpreterServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child:
          MaterialApp(home: Scaffold(body: DungeonMapPane(oracle: _oracle()))),
    ));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const Key('flesh-out-room')),
            matching: find.byType(AiBadge)),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('flesh-out-room')));
    await tester.pumpAndSettle(); // fleshOut() + review dialog
    await tester.tap(find.byKey(const Key('flesh-out-append')));
    await tester.pumpAndSettle();
    final s = await c.read(mapProvider.future);
    expect(s.rooms.single.detail, contains('Dim.'));
    expect(s.rooms.single.detail, contains('Fleshed-out detail.'));
  });

  testWidgets('hex-site flesh-out appends a siteLine after Append',
      (tester) async {
    final fake = _fake();
    const seeded = MapState(
      hexes: [
        HexCell(col: 0, row: 0, envRow: 1, terrain: 'hills', site: 'Cave')
      ],
      currentHexCol: 0,
      currentHexRow: 0,
    );
    SharedPreferences.setMockInitialValues({
      'flutter.juice.map.v1.default': jsonEncode(seeded.toJson()),
      'juice.ai_enabled.v1': true,
    });
    final c = ProviderContainer(overrides: [
      hexcrawlDataProvider.overrideWith((ref) async => _hexData()),
      sessionsProvider
          .overrideWith(() => _FixedSessions(['juice', 'hexcrawl'])),
      interpreterServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: Scaffold(body: HexMapPane(oracle: _oracle()))),
    ));
    await tester.pumpAndSettle();
    // Tap the origin hex on the canvas to select it (mirrors hexCenterFor geometry).
    final cells = [(col: 0, row: 0), ...hexNeighbors(0, 0)];
    final minCol = cells.map((c) => c.col).reduce(min);
    final minRow = cells.map((c) => c.row).reduce(min);
    final local = hexCenterFor(0, 0, minCol, minRow, 34.0);
    final tl = tester.getTopLeft(find.byKey(const Key('hex-canvas')));
    await tester.tapAt(tl + local);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const Key('flesh-out-site')),
            matching: find.byType(AiBadge)),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('flesh-out-site')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('flesh-out-append')));
    await tester.pumpAndSettle();
    final s = await c.read(mapProvider.future);
    expect(s.hexes.single.siteLines, contains('Fleshed-out detail.'));
  });
}
