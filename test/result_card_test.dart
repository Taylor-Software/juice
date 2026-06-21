import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/shared/result_card.dart';

const _result = GenResult(
  title: 'Mythic Fate Chart',
  rolls: [Roll(label: 'Answer', value: 'Yes')],
);

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('no action row when actions is null', (tester) async {
    await _pump(tester, const ResultCard(result: _result));
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('renders action chips and taps fire their callback',
      (tester) async {
    var taps = 0;
    await _pump(
      tester,
      ResultCard(
        result: _result,
        actions: [
          ResultAction(
            label: 'Random Event',
            icon: Icons.bolt_outlined,
            onPressed: () => taps++,
          ),
        ],
      ),
    );
    final chip = find.byKey(const Key('result-action-Random Event'));
    expect(chip, findsOneWidget);
    expect(find.text('Random Event'), findsOneWidget);
    await tester.tap(chip);
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('a null onPressed disables the chip', (tester) async {
    await _pump(
      tester,
      const ResultCard(
        result: _result,
        actions: [
          ResultAction(label: 'Disabled', icon: Icons.bolt_outlined),
        ],
      ),
    );
    final chip = tester.widget<ActionChip>(find.byType(ActionChip));
    expect(chip.onPressed, isNull);
  });
}
