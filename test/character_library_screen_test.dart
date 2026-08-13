import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/features/character_library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpLibrary(WidgetTester tester) async {
  await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: CharacterLibraryScreen())));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('lists entries; delete has undo', (tester) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.charlibrary.v1': '[{"id":"a","name":"Brakka"}]',
    });
    await pumpLibrary(tester);
    expect(find.text('Brakka'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-delete-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-char-a')), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-char-a')), findsOneWidget);
  });

  testWidgets('copy from campaign imports a copy (magic link dropped)',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
          '{"active":"s1","sessions":[{"id":"s1","name":"Alpha"}]}',
      'loreseer.characters.v1.s1':
          '[{"id":"c1","name":"Yeva","polarityId":"pg-1"}]',
    });
    await pumpLibrary(tester);
    await tester.tap(find.byKey(const Key('library-copy-from-campaign')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-src-s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-src-char-c1')));
    await tester.pumpAndSettle();
    expect(find.text('Yeva'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('loreseer.charlibrary.v1')!;
    expect(raw, contains('"Yeva"'));
    expect(raw, isNot(contains('polarityId')));
    expect(raw, isNot(contains('"id":"c1"'))); // fresh id
  });
}
