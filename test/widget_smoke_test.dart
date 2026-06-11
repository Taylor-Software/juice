import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/shared/result_card.dart';

void main() {
  testWidgets('ResultCard renders title, summary, and rolls', (tester) async {
    const result = GenResult(
      title: 'New Quest',
      summary: 'Destroy the Hidden Enemy, Near the Dungeon.',
      rolls: [
        Roll(label: 'Objective', value: 'Destroy'),
        Roll(label: 'Focus', value: 'Enemy'),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ResultCard(result: result)),
      ),
    );

    expect(find.text('New Quest'), findsOneWidget);
    expect(find.text('Destroy the Hidden Enemy, Near the Dungeon.'),
        findsOneWidget);
    expect(find.text('Objective'), findsOneWidget);
    expect(find.text('Destroy'), findsOneWidget);
  });
}
