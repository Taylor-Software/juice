import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/help_data.dart';
import 'package:juice_oracle/features/help_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/shared/tool_registry.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  final data = HelpData(
      jsonDecode(File('assets/help_data.json').readAsStringSync())
          as Map<String, dynamic>);

  Future<ProviderContainer> pump(WidgetTester tester, {String? topic}) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        helpDataProvider.overrideWith((ref) async => data),
        if (topic != null) helpTopicProvider.overrideWith((ref) => topic),
      ],
      // Mount exactly as the app does: a bare pushed route with no ambient
      // Scaffold/Material (openHelp -> MaterialPageRoute(builder: HelpScreen)).
      // HelpScreen must supply its own Material via a Scaffold.
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const HelpScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(HelpScreen)));
  }

  testWidgets('index renders the three section titles and a tile per page',
      (tester) async {
    await pump(tester);
    for (final section in data.sections) {
      expect(find.text(section.title), findsOneWidget);
      for (final page in section.pages) {
        expect(find.byKey(Key('help-page-${page.id}')), findsOneWidget,
            reason: 'tile for ${page.id}');
      }
    }
  });

  testWidgets(
      'pushed as a route, the index AppBar back pops Help (no Material '
      'crash, route is dismissable)', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [helpDataProvider.overrideWith((ref) async => data)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
                ),
                child: const Text('open help'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open help'));
    await tester.pumpAndSettle();
    // Index renders (regression: previously crashed with "No Material found").
    expect(find.byKey(const Key('help-page-getting-started')), findsOneWidget);
    // The AppBar's automatic back button (the route can pop) closes Help.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('help-page-getting-started')), findsNothing);
    expect(find.text('open help'), findsOneWidget);
  });

  testWidgets('a page renders its blocks; back returns to the index',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('help-page-triple-o')));
    await tester.pumpAndSettle();
    final page = data.page('triple-o');
    expect(find.text(page.title), findsOneWidget);
    for (final block in page.blocks) {
      if (block.kind == HelpBlockKind.steps) {
        for (final item in block.items) {
          expect(find.text(item), findsOneWidget);
        }
      } else {
        expect(find.text(block.text), findsOneWidget);
      }
    }
    // Steps carry leading numbers.
    expect(find.text('1. '), findsOneWidget);
    expect(find.text('2. '), findsOneWidget);
    await tester.tap(find.byKey(const Key('help-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('help-page-triple-o')), findsOneWidget);
  });

  testWidgets('tip blocks render inside a Card', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('help-page-getting-started')));
    await tester.pumpAndSettle();
    final tip = data
        .page('getting-started')
        .blocks
        .firstWhere((b) => b.kind == HelpBlockKind.tip);
    expect(find.ancestor(of: find.text(tip.text), matching: find.byType(Card)),
        findsOneWidget);
  });

  testWidgets('deep link opens directly on the topic page and clears it',
      (tester) async {
    final container = await pump(tester, topic: 'party-emulator');
    expect(find.text('Party Emulator'), findsOneWidget);
    expect(find.byKey(const Key('help-page-getting-started')), findsNothing);
    expect(container.read(helpTopicProvider), isNull);
  });

  testWidgets('credits page lists licenses and opens the package LicensePage',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('help-page-credits')));
    await tester.pumpAndSettle();
    for (final needle in [
      'jrruethe',
      'Word Mill Games',
      'Shawn Tomkin',
      'Cezar Capacle',
      'Tam H',
      'thunder9861',
      'Gemma',
    ]) {
      expect(find.textContaining(needle), findsOneWidget, reason: needle);
    }
    final button = find.byKey(const Key('help-licenses'));
    expect(tester.widget(button), isA<FilledButton>());
    expect(
        find.descendant(of: button, matching: find.text('Software licenses')),
        findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  test('toolHelpPage maps every non-help tool id to a real help page', () {
    final ids = buildToolRegistry(family: ['classic']).map((t) => t.id).toSet();
    expect(toolHelpPage.keys.toSet(), ids.difference({'help'}));
    for (final pageId in toolHelpPage.values) {
      expect(() => data.page(pageId), returnsNormally, reason: pageId);
    }
  });
}
