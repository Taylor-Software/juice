import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/tarot_reference.dart';

Future<void> pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester
      .pumpWidget(const MaterialApp(home: Scaffold(body: TarotReference())));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the Major Arcana section header', (tester) async {
    await pump(tester);
    expect(find.text('Major Arcana'), findsOneWidget);
  });

  testWidgets('search filters to matching cards and hides other groups',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('tarot-ref-search')), 'tower');
    await tester.pumpAndSettle();
    expect(find.text('The Tower'), findsOneWidget); // matching card row
    expect(find.text('Wands'), findsNothing); // non-matching suit hidden
  });

  testWidgets('a card row shows upright and reversed text', (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byKey(const Key('tarot-ref-search')), 'the fool');
    await tester.pumpAndSettle();
    expect(find.textContaining('Upright —'), findsWidgets);
    expect(find.textContaining('Reversed —'), findsWidgets);
  });
}
