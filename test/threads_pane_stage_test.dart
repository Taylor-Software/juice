import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';
import 'package:loreseer/features/tracker_screen.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ThreadsPane()))));
    await tester.pumpAndSettle();
  }

  void seed(List<Thread> threads) {
    SharedPreferences.setMockInitialValues({
      'loreseer.threads.v1.default':
          jsonEncode(threads.map((t) => t.toJson()).toList()),
      'loreseer.sessions.v1': jsonEncode({
        'active': 'default',
        'sessions': [
          {'id': 'default', 'name': 'Campaign 1'}
        ],
      }),
    });
  }

  testWidgets('stage filter chips narrow the list', (tester) async {
    seed([
      Thread(id: 'r1', title: 'Whispered lead', stage: ThreadStage.rumor),
      Thread(id: 'a1', title: 'Main quest'),
      Thread(id: 'd1', title: 'Old business', stage: ThreadStage.done),
    ]);
    await pump(tester);

    expect(find.text('Whispered lead'), findsOneWidget);
    expect(find.text('Main quest'), findsOneWidget);

    await tester.tap(find.byKey(const Key('thread-stage-rumor')));
    await tester.pumpAndSettle();
    expect(find.text('Whispered lead'), findsOneWidget);
    expect(find.text('Main quest'), findsNothing);
    expect(find.text('Old business'), findsNothing);
  });

  testWidgets('confirm promotes a rumor to active', (tester) async {
    seed([Thread(id: 'r1', title: 'Whispered lead', stage: ThreadStage.rumor)]);
    await pump(tester);

    await tester.tap(find.byKey(const Key('thread-confirm-r1')));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(ThreadsPane)));
    final threads = await container.read(threadsProvider.future);
    expect(threads.single.stage, ThreadStage.active);
    expect(find.byKey(const Key('thread-confirm-r1')), findsNothing);
  });

  testWidgets('New rumor button creates a rumor-stage thread', (tester) async {
    seed([]);
    await pump(tester);

    await tester.tap(find.byKey(const Key('rumor-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Heard in the tavern');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(ThreadsPane)));
    final threads = await container.read(threadsProvider.future);
    expect(threads.single.stage, ThreadStage.rumor);
    expect(threads.single.title, 'Heard in the tavern');
  });
}
