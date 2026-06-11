import 'package:flutter_test/flutter_test.dart';

import 'package:juice_oracle/engine/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Session models', () {
    test('SessionMeta json round-trip', () {
      const m = SessionMeta(id: 'abc', name: 'West Marches');
      final back = SessionMeta.fromJson(m.toJson());
      expect(back.id, 'abc');
      expect(back.name, 'West Marches');
    });

    test('SessionsState json round-trip and activeMeta lookup', () {
      const s = SessionsState(active: 'b', sessions: [
        SessionMeta(id: 'a', name: 'One'),
        SessionMeta(id: 'b', name: 'Two'),
      ]);
      final back = SessionsState.fromJson(s.toJson());
      expect(back.active, 'b');
      expect(back.sessions.length, 2);
      expect(back.activeMeta.name, 'Two');
    });

    test('activeMeta falls back to first session when active id is stale', () {
      const s = SessionsState(active: 'gone', sessions: [
        SessionMeta(id: 'a', name: 'One'),
      ]);
      expect(s.activeMeta.name, 'One');
    });
  });
}
