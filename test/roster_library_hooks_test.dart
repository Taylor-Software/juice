import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';
import 'package:loreseer/features/tracker_screen.dart';
import 'package:loreseer/shared/theme.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const libOne = '[{"id":"L1","name":"Brakka"}]';

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    String library = '{}',
    String chars = '[]',
    String? activeCharacterId,
  }) async {
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'loreseer.characters.v1.default': chars,
      'loreseer.charlibrary.v1': library,
      if (activeCharacterId != null)
        'loreseer.context.v1.default':
            '{"activeCharacterId":"$activeCharacterId"}',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  testWidgets(
      'From library appears when library is non-empty; picking adds a fresh-id pc',
      (tester) async {
    final container = await pump(tester, library: libOne);
    await tester.tap(find.byKey(const Key('add-character')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-from-library')), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-from-library')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-pick-L1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('library-pick-L1')));
    await tester.pumpAndSettle();
    final chars = await container.read(charactersProvider.future);
    expect(chars, hasLength(1));
    final added = chars.single;
    expect(added.name, 'Brakka');
    expect(added.id, isNot('L1'));
    expect(added.role, CharacterRole.pc);
    expect(added.starred, isFalse);
  });

  testWidgets('From library is absent when the library is empty',
      (tester) async {
    await pump(tester, library: '{}');
    await tester.tap(find.byKey(const Key('add-character')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-from-library')), findsNothing);
  });

  testWidgets(
      'lead-more Save to library adds a fresh-id library entry (roster id not reused)',
      (tester) async {
    await pump(tester,
        activeCharacterId: 'c1',
        chars: '[{"id":"c1","name":"Ash","note":"","stats":[],"tracks":[],'
            '"tags":[]}]');
    // c1 is set as the active PC, so it renders the lead card.
    expect(find.byKey(const Key('lead-more')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lead-more')));
    await tester.pumpAndSettle();
    expect(find.text('Save to library'), findsOneWidget);
    await tester.tap(find.text('Save to library'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('loreseer.charlibrary.v1')!;
    final list = jsonDecode(raw) as List;
    expect(list, hasLength(1));
    final saved = list.single as Map<String, dynamic>;
    expect(saved['name'], 'Ash');
    expect(saved['id'], isNot('c1'));
  });

  testWidgets(
      'compact-more menu: Save to library works, Delete removes with Undo restore',
      (tester) async {
    // Two companions so both render as compact rows (no lead PC context set).
    final container = await pump(tester,
        chars: '[{"id":"c1","name":"Ash","note":"","stats":[],"tracks":[],'
            '"tags":[],"role":"companion"},'
            '{"id":"c2","name":"Bran","note":"","stats":[],"tracks":[],'
            '"tags":[],"role":"companion"}]');
    expect(find.byKey(const Key('compact-more-c1')), findsOneWidget);

    // Save to library.
    await tester.tap(find.byKey(const Key('compact-more-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to library'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('loreseer.charlibrary.v1')!;
    final list = jsonDecode(raw) as List;
    expect(list, hasLength(1));
    expect((list.single as Map<String, dynamic>)['name'], 'Ash');

    // Delete with undo.
    await tester.tap(find.byKey(const Key('compact-more-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    var chars = await container.read(charactersProvider.future);
    expect(chars.map((c) => c.id), isNot(contains('c1')));
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    chars = await container.read(charactersProvider.future);
    expect(chars.map((c) => c.id), contains('c1'));
  });
}
