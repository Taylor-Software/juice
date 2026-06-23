import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/fate_screen.dart';
import 'package:juice_oracle/features/tarot_reference.dart';
import 'package:juice_oracle/shared/card_image.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> pumpFate(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1",'
            '"systems":["cards"]}]}',
  });
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final data = OracleData(
      jsonDecode(File('assets/oracle_data.json').readAsStringSync())
          as Map<String, dynamic>);
  await tester.pumpWidget(ProviderScope(
      child:
          MaterialApp(home: Scaffold(body: FateScreen(oracle: Oracle(data))))));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(FateScreen)));
}

void main() {
  testWidgets('drawing a tarot card shows its authored meaning',
      (tester) async {
    await pumpFate(tester);
    await tester.tap(find.byKey(const Key('cards-draw-tarot')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card-meaning')), findsOneWidget);
    expect(find.byType(CardImage), findsOneWidget); // bundled art renders
  });

  testWidgets('logging a tarot card writes the meaning into the entry',
      (tester) async {
    final container = await pumpFate(tester);
    await tester.tap(find.byKey(const Key('cards-draw-tarot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add to journal'));
    await tester.pumpAndSettle();
    final entries = container.read(journalProvider).valueOrNull ?? const [];
    expect(entries, hasLength(1));
    expect(entries.single.sourceTool, 'cards');
    expect(entries.single.body,
        anyOf(contains('Upright —'), contains('Reversed —')));
  });

  testWidgets('drawing a standard card shows its image but no meaning',
      (tester) async {
    await pumpFate(tester);
    await tester.tap(find.byKey(const Key('cards-draw')));
    await tester.pumpAndSettle();
    expect(find.byType(CardImage), findsOneWidget); // bundled SVG renders
    expect(find.byKey(const Key('card-meaning')), findsNothing); // no meaning
  });

  testWidgets('Card meanings button opens the reference', (tester) async {
    await pumpFate(tester);
    await tester.tap(find.byKey(const Key('cards-reference')));
    await tester.pumpAndSettle();
    expect(find.byType(TarotReference), findsOneWidget);
  });

  testWidgets('drawing a spread renders a card per position and logs one entry',
      (tester) async {
    final container = await pumpFate(tester);
    // Default spread is the three-card; draw it.
    await tester.tap(find.byKey(const Key('cards-draw-spread')));
    await tester.pumpAndSettle();
    // Three positions → three card images.
    expect(find.byType(CardImage), findsNWidgets(3));
    // Log the whole spread as one entry.
    await tester.tap(find.byKey(const Key('spread-log')));
    await tester.pumpAndSettle();
    final entries = container.read(journalProvider).valueOrNull ?? const [];
    expect(entries, hasLength(1));
    expect(entries.single.sourceTool, 'cards');
    expect(entries.single.body, contains('Past'));
    expect(entries.single.body, contains('Present'));
    expect(entries.single.body, contains('Future'));
  });
}
