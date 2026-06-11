import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LogEntry threadId', () {
    test('round-trips and defaults to null on old json', () {
      final e = LogEntry(
        id: '1',
        timestamp: DateTime.utc(2026),
        title: 't',
        body: 'b',
        threadId: 'th1',
      );
      expect(LogEntry.fromJson(e.toJson()).threadId, 'th1');
      expect(
        LogEntry.fromJson(
            {'id': '1', 'timestamp': '2026-01-01T00:00:00Z', 'title': 't', 'body': 'b'}).threadId,
        isNull,
      );
    });

    test('copyWith can set and clear the link', () {
      final e = LogEntry(
          id: '1', timestamp: DateTime.utc(2026), title: 't', body: 'b');
      final linked = e.copyWith(threadId: 'th1');
      expect(linked.threadId, 'th1');
      expect(linked.copyWith(clearThreadId: true).threadId, isNull);
      expect(linked.copyWith(body: 'edited').threadId, 'th1');
    });
  });

  group('LogNotifier.replace', () {
    test('replaces an entry in place and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      await container.read(logProvider.future);
      final notifier = container.read(logProvider.notifier);
      await notifier.add('Roll', 'body');
      final entry = (await container.read(logProvider.future)).single;
      await notifier.replace(entry.copyWith(threadId: 'th9', body: 'edited'));
      final after = (await container.read(logProvider.future)).single;
      expect(after.threadId, 'th9');
      expect(after.body, 'edited');
      expect(after.id, entry.id);
    });
  });
}
