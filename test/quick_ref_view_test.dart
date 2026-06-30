// test/quick_ref_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/quick_ref.dart';
import 'package:juice_oracle/features/quick_ref_view.dart';

void main() {
  testWidgets('renders a card title, section titles and lines', (tester) async {
    const card = QuickRefCard(system: 'x', title: 'X — Quick Reference', sections: [
      QuickRefSection('Resolution', ['roll a die']),
      QuickRefSection('Combat', ['hit it']),
    ]);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: QuickRefView(card: card))));
    expect(find.text('Resolution'), findsOneWidget);
    expect(find.text('roll a die'), findsOneWidget);
    expect(find.text('Combat'), findsOneWidget);
  });

  testWidgets('shows the empty state when card is null', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: QuickRefView(card: null))));
    expect(find.byKey(const Key('quickref-empty')), findsOneWidget);
  });
}
