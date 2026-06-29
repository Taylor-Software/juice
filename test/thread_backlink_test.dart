import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sessions =
      '{"active":"s1","sessions":[{"id":"s1","name":"Campaign"}]}';

  test('journal entries with threadId are found for that thread', () async {
    // Seed a thread and two journal entries — one linked, one not.
    const threadId = 'thread-001';
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1': sessions,
      'juice.threads.v1.s1':
          jsonEncode([Thread(id: threadId, title: 'The Quest').toJson()]),
      'juice.journal.v2.s1': jsonEncode([
        JournalEntry(
                id: 'j1',
                timestamp: DateTime(2026),
                title: 'Accepted the vow',
                body: '',
                threadId: threadId)
            .toJson(),
        JournalEntry(
                id: 'j2',
                timestamp: DateTime(2026),
                title: 'Unrelated entry',
                body: '')
            .toJson(),
      ]),
    });

    final c = ProviderContainer();
    addTearDown(c.dispose);

    final journal = await c.read(journalProvider.future);
    final linked = journal.where((e) => e.threadId == threadId).toList();
    expect(linked, hasLength(1));
    expect(linked.first.id, 'j1');
    expect(linked.first.title, 'Accepted the vow');
  });

  test('thread with no linked entries returns empty list', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1': sessions,
      'juice.threads.v1.s1': jsonEncode(
          [Thread(id: 'thread-002', title: 'Lonely Thread').toJson()]),
      'juice.journal.v2.s1': jsonEncode([]),
    });

    final c = ProviderContainer();
    addTearDown(c.dispose);

    final journal = await c.read(journalProvider.future);
    final linked =
        journal.where((e) => e.threadId == 'thread-002').toList();
    expect(linked, isEmpty);
  });
}
