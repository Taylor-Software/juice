import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/tracker_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

FakeInterpreterService _fake() => FakeInterpreterService(
    initial: const InterpreterStatus(InterpreterPhase.ready));

Future<ProviderContainer> _pumpCharacters(
    WidgetTester tester, FakeInterpreterService fake) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default':
        '[{"id":"c1","name":"Ash","note":"A scout.","stats":[],"tracks":[],"tags":[],"role":"npc"}]',
    'juice.ai_enabled.v1': true,
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
    await tester.tap(find.byKey(const Key('flesh-out-character')));
    await tester.pumpAndSettle(); // fleshOut() + the _EditDialog
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final chars = c.read(charactersProvider).valueOrNull!;
    expect(chars.single.note, contains('A scout.')); // preserved
    expect(chars.single.note, contains('Fleshed-out detail.')); // appended
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
    await tester.tap(find.byKey(const Key('flesh-out-thread-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final threads = c.read(threadsProvider).valueOrNull!;
    expect(threads.single.note, contains('Rumored lost.'));
    expect(threads.single.note, contains('Fleshed-out detail.'));
  });
}
