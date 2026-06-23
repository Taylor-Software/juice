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

  testWidgets('jokers toggle switches the standard deck readout to /54',
      (tester) async {
    await pumpFate(tester);
    expect(find.textContaining('/52'), findsOneWidget); // default 52
    await tester.tap(find.byKey(const Key('cards-jokers-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('/54'), findsOneWidget); // jokers on
    expect(find.textContaining('/52'), findsNothing);
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

  testWidgets('logged spread keeps the drawn spread name after dropdown change',
      (tester) async {
    final container = await pumpFate(tester);
    // Draw the default three-card spread.
    await tester.tap(find.byKey(const Key('cards-draw-spread')));
    await tester.pumpAndSettle();
    // Change the picker to Celtic Cross WITHOUT redrawing.
    await tester.tap(find.byKey(const Key('spread-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Celtic Cross  (10)').last);
    await tester.pumpAndSettle();
    // Log: the entry must reflect the spread that was actually drawn (3-card),
    // not the picker's current value (Celtic Cross).
    await tester.tap(find.byKey(const Key('spread-log')));
    await tester.pumpAndSettle();
    final entries = container.read(journalProvider).valueOrNull ?? const [];
    expect(entries.single.body, startsWith('Past · Present · Future'));
    expect(entries.single.body, isNot(contains('Celtic Cross')));
  });
}
