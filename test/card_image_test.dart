import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/card_image.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('tarot card shows its name label when showLabel is set',
      (tester) async {
    await tester.pumpWidget(
        _host(const CardImage('The Tower', showLabel: true, height: 100)));
    await tester.pumpAndSettle();
    expect(find.text('The Tower'), findsOneWidget);
  });

  testWidgets('tarot card tap opens a meaning popup', (tester) async {
    // showLabel gives the tappable content a non-zero size in tests, where the
    // tarot JPG can't decode (in the app the image itself provides the size).
    await tester.pumpWidget(
        _host(const CardImage('The Tower', height: 100, showLabel: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card-info-The Tower')));
    await tester.pumpAndSettle();
    // Popup shows the card name (title) + the upright/reversed labels.
    expect(find.byKey(const Key('card-info-dialog-The Tower')), findsOneWidget);
    expect(find.text('Upright'), findsOneWidget);
    expect(find.text('Reversed'), findsOneWidget);
  });

  testWidgets('reversed tarot card popup leads with the reversed meaning',
      (tester) async {
    await tester.pumpWidget(_host(const CardImage('The Tower',
        reversed: true, height: 100, showLabel: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card-info-The Tower')));
    await tester.pumpAndSettle();
    expect(find.text('The Tower (reversed)'), findsOneWidget);
  });

  testWidgets('non-tarot card has no info tap target', (tester) async {
    // A standard-deck card has no bundled meaning → no InkWell popup wrapper.
    await tester
        .pumpWidget(_host(const CardImage('Ace of Spades', height: 100)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card-info-Ace of Spades')), findsNothing);
  });
}
