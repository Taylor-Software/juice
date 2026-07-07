import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/sketch.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JournalEntry threadId', () {
    test('round-trips and defaults to null on old json', () {
      final e = JournalEntry(
        id: '1',
        timestamp: DateTime.utc(2026),
        title: 't',
        body: 'b',
        threadId: 'th1',
      );
      expect(JournalEntry.fromJson(e.toJson()).threadId, 'th1');
      expect(
        JournalEntry.fromJson({
          'id': '1',
          'timestamp': '2026-01-01T00:00:00Z',
          'title': 't',
          'body': 'b'
        }).threadId,
        isNull,
      );
    });

    test('copyWith can set and clear the link', () {
      final e = JournalEntry(
          id: '1', timestamp: DateTime.utc(2026), title: 't', body: 'b');
      final linked = e.copyWith(threadId: 'th1');
      expect(linked.threadId, 'th1');
      expect(linked.copyWith(clearThreadId: true).threadId, isNull);
      expect(linked.copyWith(body: 'edited').threadId, 'th1');
    });
  });

  group('JournalEntry tags', () {
    test('round-trips through JSON', () {
      final e = JournalEntry(
        id: '1',
        timestamp: DateTime.utc(2026),
        title: 't',
        body: 'b',
        tags: const ['omens', 'NPC'],
      );
      expect(JournalEntry.fromJson(e.toJson()).tags, ['omens', 'NPC']);
    });

    test('legacy JSON without tags key parses to empty list', () {
      final e = JournalEntry.fromJson({
        'id': '1',
        'timestamp': '2026-01-01T00:00:00Z',
        'title': 't',
        'body': 'b',
      });
      expect(e.tags, isEmpty);
    });

    test('non-string junk in tags is dropped', () {
      final e = JournalEntry.fromJson({
        'id': '1',
        'timestamp': '2026-01-01T00:00:00Z',
        'title': 't',
        'body': 'b',
        'tags': ['ok', 7, null, 'fine'],
      });
      expect(e.tags, ['ok', 'fine']);
    });

    test('copyWith carries, overrides, and clears tags', () {
      final e = JournalEntry(
        id: '1',
        timestamp: DateTime.utc(2026),
        title: 't',
        body: 'b',
        tags: const ['omens'],
      );
      expect(e.copyWith(body: 'edited').tags, ['omens']);
      expect(e.copyWith(tags: ['mill']).tags, ['mill']);
      expect(e.copyWith(tags: []).tags, isEmpty);
    });
  });

  group('JournalEntry kinds', () {
    test('kind defaults to result when absent in JSON (legacy entries)', () {
      final e = JournalEntry.fromJson({
        'id': '1',
        'timestamp': '2026-06-11T10:00:00.000',
        'title': 'Fate Check',
        'body': 'Yes',
      });
      expect(e.kind, JournalKind.result);
      expect(e.chaosFactor, isNull);
    });

    test('text and scene kinds round-trip with chaos factor', () {
      final scene = JournalEntry(
        id: '2',
        timestamp: DateTime(2026, 6, 11),
        title: 'The gatehouse',
        body: '',
        kind: JournalKind.scene,
        chaosFactor: 6,
      );
      final back = JournalEntry.fromJson(scene.toJson());
      expect(back.kind, JournalKind.scene);
      expect(back.chaosFactor, 6);
      final text = JournalEntry(
        id: '3',
        timestamp: DateTime(2026, 6, 11),
        title: '',
        body: 'We slip inside.',
        kind: JournalKind.text,
      );
      expect(JournalEntry.fromJson(text.toJson()).kind, JournalKind.text);
      final session = JournalEntry(
        id: '4',
        timestamp: DateTime(2026, 6, 11),
        title: 'Session 2',
        body: '',
        kind: JournalKind.session,
      );
      expect(JournalEntry.fromJson(session.toJson()).kind, JournalKind.session);
    });

    test('copyWith preserves kind and chaosFactor', () {
      final e = JournalEntry(
        id: '4',
        timestamp: DateTime(2026, 6, 11),
        title: 'Scene',
        body: '',
        kind: JournalKind.scene,
        chaosFactor: 4,
      );
      final edited = e.copyWith(title: 'Scene 2');
      expect(edited.kind, JournalKind.scene);
      expect(edited.chaosFactor, 4);
    });
  });

  group('JournalNotifier.replace', () {
    test('replaces an entry in place and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      await container.read(journalProvider.future);
      final notifier = container.read(journalProvider.notifier);
      await notifier.add('Roll', 'body');
      final entry = (await container.read(journalProvider.future)).single;
      await notifier.replace(entry.copyWith(threadId: 'th9', body: 'edited'));
      final after = (await container.read(journalProvider.future)).single;
      expect(after.threadId, 'th9');
      expect(after.body, 'edited');
      expect(after.id, entry.id);
    });
  });

  group('JournalNotifier cold-start mutation', () {
    test('add before any read keeps previously persisted entries', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
        'juice.journal.v2.default':
            '[{"id":"old","timestamp":"2026-06-11T09:00:00.000","title":"Old","body":"kept"}]',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // First interaction is add() itself — provider never read or watched.
      await container.read(journalProvider.notifier).add('New', 'fresh');
      final entries = await container.read(journalProvider.future);
      expect(entries.map((e) => e.title), ['New', 'Old']);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('juice.journal.v2.default')!;
      expect(raw, contains('Old')); // not clobbered
      expect(raw, contains('New'));
    });
  });

  group('JournalNotifier typed adds', () {
    test('addText and addScene append typed entries', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(journalProvider.future);
      final n = container.read(journalProvider.notifier);
      await n.addText('We slip inside.');
      await n.addScene('The gatehouse', chaosFactor: 6);
      final entries = await container.read(journalProvider.future);
      expect(entries.first.kind, JournalKind.scene);
      expect(entries.first.chaosFactor, 6);
      expect(entries[1].kind, JournalKind.text);
      expect(entries[1].body, 'We slip inside.');
    });
  });

  test('addResult persists sourceTool and payload', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(journalProvider.notifier);
    await container.read(journalProvider.future);
    await notifier.addResult(
      'Dice Roll',
      '3d6 = 11',
      sourceTool: 'dice',
      payload: {'v': 1, 'summary': '3d6 = 11', 'rolls': const []},
    );
    final entries = await container.read(journalProvider.future);
    expect(entries.first.sourceTool, 'dice');
    expect(entries.first.payload!['summary'], '3d6 = 11');
    expect(entries.first.kind, JournalKind.result);
  });

  group('JournalNotifier auto-stamps the active location', () {
    test('addText/addResult/addScene pick up the spine location', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
        'juice.context.v1.default': '{"activeLocation":{"roomId":"r1"}}',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(journalProvider.future);
      final n = container.read(journalProvider.notifier);
      await n.addText('note');
      await n.addResult('R', 'body');
      await n.addScene('Scene');
      final entries = await container.read(journalProvider.future);
      expect(entries.every((e) => e.location?.roomId == 'r1'), isTrue);
    });

    test('addSessionBreak and addSketch do NOT get stamped', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
        'juice.context.v1.default': '{"activeLocation":{"roomId":"r1"}}',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(journalProvider.future);
      final n = container.read(journalProvider.notifier);
      await n.addSessionBreak('Session 2');
      await n.addSketch(const SketchData(canvasWidth: 10, canvasHeight: 10));
      final entries = await container.read(journalProvider.future);
      expect(entries.every((e) => e.location == null), isTrue);
    });

    test('no active location leaves entries unstamped', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(journalProvider.future);
      await container.read(journalProvider.notifier).addText('note');
      final entries = await container.read(journalProvider.future);
      expect(entries.single.location, isNull);
    });
  });

  test('JournalKind.sketch round-trips', () {
    final e = JournalEntry(
        id: 's1',
        timestamp: DateTime(2026),
        title: 'Sketch',
        body: '',
        kind: JournalKind.sketch,
        payload: const {'v': 1, 'sketch': {}});
    final back = JournalEntry.fromJson(e.toJson());
    expect(back.kind, JournalKind.sketch);
    expect(back.payload?['v'], 1);
  });

  test('copyWith(payload:) replaces, omitted keeps', () {
    final e = JournalEntry(
        id: 's1',
        timestamp: DateTime(2026),
        title: 'S',
        body: '',
        kind: JournalKind.sketch,
        payload: const {'a': 1});
    expect(e.copyWith(payload: const {'b': 2}).payload, const {'b': 2});
    expect(e.copyWith(title: 'X').payload, const {'a': 1});
  });

  group('JournalEntry location', () {
    test('round-trips a room ref through JSON', () {
      final e = JournalEntry(
        id: '1',
        timestamp: DateTime.utc(2026),
        title: 't',
        body: 'b',
        location: const LocationRef(roomId: 'room-1'),
      );
      final back = JournalEntry.fromJson(e.toJson());
      expect(back.location?.roomId, 'room-1');
      expect(e.toJson()['loc'], {'roomId': 'room-1'});
    });

    test('round-trips a hex ref through JSON', () {
      final e = JournalEntry(
        id: '1',
        timestamp: DateTime.utc(2026),
        title: 't',
        body: 'b',
        location: const LocationRef(hexCol: 3, hexRow: 4),
      );
      final back = JournalEntry.fromJson(e.toJson());
      expect(back.location?.hexCol, 3);
      expect(back.location?.hexRow, 4);
    });

    test('missing loc key parses to null (legacy entries)', () {
      final e = JournalEntry.fromJson({
        'id': '1',
        'timestamp': '2026-01-01T00:00:00Z',
        'title': 't',
        'body': 'b',
      });
      expect(e.location, isNull);
    });

    test('garbage loc value is dropped, not thrown', () {
      final e = JournalEntry.fromJson({
        'id': '1',
        'timestamp': '2026-01-01T00:00:00Z',
        'title': 't',
        'body': 'b',
        'loc': 'not a map',
      });
      expect(e.location, isNull);
    });

    test('copyWith can set and clear the location', () {
      final e = JournalEntry(
          id: '1', timestamp: DateTime.utc(2026), title: 't', body: 'b');
      final linked = e.copyWith(location: const LocationRef(roomId: 'r1'));
      expect(linked.location?.roomId, 'r1');
      expect(linked.copyWith(clearLocation: true).location, isNull);
      expect(linked.copyWith(body: 'edited').location?.roomId, 'r1');
    });
  });

  group('entriesAtLocation', () {
    JournalEntry mk(String id, {LocationRef? loc}) => JournalEntry(
        id: id,
        timestamp: DateTime.utc(2026),
        title: id,
        body: 'b',
        location: loc);

    test('matches by room id', () {
      final entries = [
        mk('a', loc: const LocationRef(roomId: 'r1')),
        mk('b', loc: const LocationRef(roomId: 'r2')),
        mk('c'),
      ];
      final hits = entriesAtLocation(entries, const LocationRef(roomId: 'r1'));
      expect(hits.map((e) => e.id), ['a']);
    });

    test('matches by hex col+row', () {
      final entries = [
        mk('a', loc: const LocationRef(hexCol: 1, hexRow: 2)),
        mk('b', loc: const LocationRef(hexCol: 1, hexRow: 3)),
      ];
      final hits =
          entriesAtLocation(entries, const LocationRef(hexCol: 1, hexRow: 2));
      expect(hits.map((e) => e.id), ['a']);
    });

    test('empty query location matches nothing', () {
      final entries = [mk('a', loc: const LocationRef(roomId: 'r1'))];
      expect(entriesAtLocation(entries, const LocationRef()), isEmpty);
    });

    test('no matches returns an empty list', () {
      final entries = [mk('a', loc: const LocationRef(roomId: 'r1'))];
      expect(entriesAtLocation(entries, const LocationRef(roomId: 'other')),
          isEmpty);
    });
  });

  test('addSketch creates a sketch entry with payload', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    await c.read(journalProvider.notifier).addSketch(
            const SketchData(canvasWidth: 300, canvasHeight: 200, strokes: [
          SketchStroke(color: 0xFF000000, width: 3, points: [
            [1, 1],
            [2, 2]
          ])
        ]));
    final e = (await c.read(journalProvider.future)).first;
    expect(e.kind, JournalKind.sketch);
    expect(e.payload?['sketch'], isNotNull);
  });
}
