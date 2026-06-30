import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/features/tasks_pane.dart';
import 'package:juice_oracle/state/providers.dart';

void seedThreads(String json) {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.threads.v1.default': json,
  });
}

Future<ProviderContainer> pumpPane(WidgetTester t) async {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await c.read(threadsProvider.future);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: Scaffold(body: TasksPane())),
  ));
  await t.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('only tally threads render as tasks', (t) async {
    seedThreads(
      '[{"id":"tk","title":"Build the bridge","tally":{"start":3,"current":3,"target":6}},'
      '{"id":"plain","title":"Just a storyline"}]',
    );
    await pumpPane(t);
    expect(find.byKey(const Key('task-tk')), findsOneWidget);
    expect(find.byKey(const Key('task-plain')), findsNothing);
    expect(find.text('Build the bridge'), findsOneWidget);
    expect(find.text('Just a storyline'), findsNothing);
  });

  testWidgets('empty state shows when no thread has a tally', (t) async {
    seedThreads('[{"id":"plain","title":"Just a storyline"}]');
    await pumpPane(t);
    expect(find.text('No tasks yet'), findsOneWidget);
    expect(find.byKey(const Key('task-new')), findsNothing);
    expect(find.byKey(const Key('empty-state-primary')), findsOneWidget);
  });

  testWidgets('new task flow creates a task with the preset current(target)',
      (t) async {
    seedThreads('[]');
    final c = await pumpPane(t);
    // Empty state primary launches the flow.
    await t.tap(find.byKey(const Key('empty-state-primary')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('task-name')), 'Slay the dragon');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    // Pick the "Difficult task" preset (4(8)).
    await t.tap(find.byKey(const Key('task-preset-Difficult task')));
    await t.pumpAndSettle();

    final threads = c.read(threadsProvider).value!;
    expect(threads, hasLength(1));
    final task = threads.single;
    expect(task.title, 'Slay the dragon');
    expect(task.tally?.current, 4);
    expect(task.tally?.target, 8);
    expect(find.byKey(Key('task-${task.id}')), findsOneWidget);
    expect(find.text('4(8)'), findsOneWidget);
  });

  testWidgets('reused tally row increments the task', (t) async {
    seedThreads(
      '[{"id":"tk","title":"Build the bridge","tally":{"start":3,"current":3,"target":6}}]',
    );
    final c = await pumpPane(t);
    await t.tap(find.byKey(const Key('thread-tally-inc-tk')));
    await t.pumpAndSettle();
    expect(c.read(threadsProvider).value!.single.tally?.current, 4);
  });
}
