import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
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
        JournalEntry.fromJson(
            {'id': '1', 'timestamp': '2026-01-01T00:00:00Z', 'title': 't', 'body': 'b'}).threadId,
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

  group('JournalNotifier migration and typed adds', () {
    test('migrates juice.log.v1 data into juice.journal.v2 once', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
        'juice.log.v1.default':
            '[{"id":"a","timestamp":"2026-06-11T09:00:00.000","title":"Old","body":"Yes"}]',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final entries = await container.read(journalProvider.future);
      expect(entries.single.title, 'Old');
      expect(entries.single.kind, JournalKind.result);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('juice.journal.v2.default'), isNotNull);
      expect(prefs.getString('juice.log.v1.default'), isNotNull);
    });

    test('migration never clobbers existing journal data', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
        'juice.journal.v2.default':
            '[{"id":"new","timestamp":"2026-06-11T10:00:00.000","title":"Kept","body":"x","kind":"text"}]',
        'juice.log.v1.default':
            '[{"id":"old","timestamp":"2026-06-11T09:00:00.000","title":"Legacy","body":"y"}]',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final entries = await container.read(journalProvider.future);
      expect(entries.single.title, 'Kept');
    });

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

    test('importing a v1 campaign file surfaces its log in the journal',
        () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      const v1File = '''
      {"app":"juice-oracle","schemaVersion":1,
       "savedAt":"2026-06-11T00:00:00.000","name":"Old campaign",
       "data":{"juice.log.v1":[{"id":"a",
         "timestamp":"2026-06-11T09:00:00.000","title":"Legacy roll",
         "body":"Yes"}]}}''';
      await container.read(sessionsProvider.notifier).importCampaign(v1File);
      // Import switches to the new session; the journal migrates its log.
      final entries = await container.read(journalProvider.future);
      expect(entries.single.title, 'Legacy roll');
      expect(entries.single.kind, JournalKind.result);
    });
  });
}
